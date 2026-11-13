"""Generate Dessert Drop's sound effects as 16-bit mono 44.1k WAVs (stdlib only).

Run:  python3 tools/make_sfx.py                    -> writes assets/sfx/*.wav, prints a loudness table
      python3 tools/make_sfx.py --preview out.wav  -> also writes every sound back to back for auditioning
      python3 tools/make_sfx.py --check            -> only analyse the WAVs already on disk

Design rules: sine-based layers with smooth raised-cosine attacks, gentle pitch glides,
filtered noise only, a small shared reverb, and every file faded to exact zero at both ends.
Loudness is matched across sounds (K-weighted, gated RMS) and then trimmed per sound, so
relative levels are set here in one table instead of by per-file peak normalisation.
"""
import math, os, random, struct, sys, wave

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "sfx")
TARGET_DB = -17.0    # K-weighted gated RMS that a sound with 0 dB trim is set to
CEILING_DB = -1.5    # no sample may exceed this
TAU = 2 * math.pi


# ---------- envelopes ----------
def ad(a, d):
    """Raised-cosine attack over `a` seconds, then exponential decay with time constant `d`."""
    def f(t):
        if t < 0:
            return 0.0
        g = 0.5 - 0.5 * math.cos(math.pi * t / a) if t < a else 1.0
        return g * math.exp(-max(0.0, t - a) / d)
    return f

def hump(dur, power=1.0):
    """Smooth swell up and back down across `dur`."""
    return lambda t: math.sin(math.pi * min(1.0, max(0.0, t / dur))) ** (2 * power)

def glide(f0, f1, tau):
    """Pitch that starts at f0 and settles exponentially on f1."""
    return lambda t: f1 + (f0 - f1) * math.exp(-t / tau)


# ---------- sources ----------
def tone(dur, freq, env, harm=((1, 1.0),)):
    """Sine partials sharing one phase. `freq` is Hz or f(t); harm is (multiple, gain) pairs."""
    n = int(dur * SR)
    out = [0.0] * n
    ph = 0.0
    fn = freq if callable(freq) else None
    step = 0.0 if fn else TAU * freq / SR
    for i in range(n):
        t = i / SR
        if fn:
            step = TAU * fn(t) / SR
        ph += step
        e = env(t)
        if e > 1e-6:
            s = 0.0
            for m, g in harm:
                s += g * math.sin(m * ph)
            out[i] = s * e
    return out

def noise(dur, env, seed):
    r = random.Random(seed)
    return [r.uniform(-1, 1) * env(i / SR) for i in range(int(dur * SR))]

def bell(f, d, bright=1.0):
    """Soft glockenspiel / music-box note: partials die away faster the higher they are."""
    parts = ((1.0, 1.0, d), (2.0, 0.28 * bright, d * 0.55), (3.0, 0.10 * bright, d * 0.35),
             (4.07, 0.05 * bright, d * 0.22))
    dur = d * 6
    out = [0.0] * int(dur * SR)
    for m, g, dd in parts:
        add(out, tone(min(dur, dd * 7), f * m, ad(0.004, dd)), 0.0, g)
    return out


# ---------- mixing and filters ----------
def add(dst, src, at=0.0, gain=1.0):
    """Mix src into dst starting at `at` seconds, growing dst if needed."""
    o = int(at * SR)
    if o + len(src) > len(dst):
        dst.extend([0.0] * (o + len(src) - len(dst)))
    for i, s in enumerate(src):
        dst[o + i] += s * gain
    return dst

def biquad(x, b0, b1, b2, a0, a1, a2):
    b0, b1, b2, a1, a2 = b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0
    x1 = x2 = y1 = y2 = 0.0
    out = [0.0] * len(x)
    for i, s in enumerate(x):
        y = b0 * s + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, s, y1, y
        out[i] = y
    return out

def lowpass(x, fc, q=0.707):
    w = TAU * fc / SR; c = math.cos(w); al = math.sin(w) / (2 * q)
    return biquad(x, (1 - c) / 2, 1 - c, (1 - c) / 2, 1 + al, -2 * c, 1 - al)

def highpass(x, fc, q=0.707):
    w = TAU * fc / SR; c = math.cos(w); al = math.sin(w) / (2 * q)
    return biquad(x, (1 + c) / 2, -(1 + c), (1 + c) / 2, 1 + al, -2 * c, 1 - al)

def highshelf(x, fc, gain_db):
    a = 10 ** (gain_db / 40); w = TAU * fc / SR; c = math.cos(w)
    al = math.sin(w) / 2 * math.sqrt(2); k = 2 * math.sqrt(a) * al
    return biquad(x, a * ((a + 1) + (a - 1) * c + k), -2 * a * ((a - 1) + (a + 1) * c),
                  a * ((a + 1) + (a - 1) * c - k), (a + 1) - (a - 1) * c + k,
                  2 * ((a - 1) - (a + 1) * c), (a + 1) - (a - 1) * c - k)

def swept_bandpass(x, fc, damp=0.6):
    """State-variable band-pass whose centre follows fc(t). Used for whooshes."""
    low = band = 0.0
    out = [0.0] * len(x)
    for i, s in enumerate(x):
        f = 2 * math.sin(math.pi * min(fc(i / SR), SR / 7) / SR)
        low += f * band
        band += f * (s - low - damp * band)
        out[i] = band
    return out

def reverb(x, mix=0.18, rt=0.5, damp=0.45, tail=None):
    """Small Schroeder room (4 damped combs, 2 all-passes). Returns dry + mix * wet."""
    n = len(x) + int((rt * 1.3 if tail is None else tail) * SR)
    dry = x + [0.0] * (n - len(x))
    wet = [0.0] * n
    for delay in (1116, 1188, 1277, 1356):
        g = 10 ** (-3.0 * delay / SR / rt)
        buf = [0.0] * delay
        k = 0; store = 0.0
        for i in range(n):
            y = buf[k]
            store = y * (1 - damp) + store * damp
            buf[k] = dry[i] + store * g
            k = k + 1 if k + 1 < delay else 0
            wet[i] += y * 0.25
    for delay in (556, 441):
        buf = [0.0] * delay
        k = 0
        for i in range(n):
            b = buf[k]
            y = b - 0.5 * wet[i]
            buf[k] = wet[i] + 0.5 * y
            k = k + 1 if k + 1 < delay else 0
            wet[i] = y
    wet = highpass(wet, 250)   # keep the tail airy, never boomy
    return [d + mix * w for d, w in zip(dry, wet)]


# ---------- analysis ----------
def db(v):
    return 20 * math.log10(max(v, 1e-9))

def gated_rms(x, block=0.010, gate_db=20.0):
    """RMS of the 10 ms blocks within gate_db of the loudest one: the part you actually hear."""
    n = max(1, int(block * SR))
    powers = [sum(s * s for s in x[i:i + n]) / n for i in range(0, max(1, len(x) - n + 1), n)]
    floor = max(powers) * 10 ** (-gate_db / 10)
    kept = [p for p in powers if p >= floor]
    return math.sqrt(sum(kept) / len(kept))

def k_weight(x):
    """Rough BS.1770 K-weighting so bright sounds are not mixed louder than low ones."""
    return highshelf(highpass(x, 60, 0.5), 1500, 4.0)

def stats(x):
    return {
        "dur": len(x) / SR,
        "peak": db(max(abs(s) for s in x)),
        "rms": db(gated_rms(x)),
        "loud": db(gated_rms(k_weight(x))),
        "head": max(abs(s) for s in x[:2]),
        "tail": max(abs(s) for s in x[-2:]),
        "step": max(abs(a - b) for a, b in zip(x[:300] + x[-300:], x[1:301] + x[-299:] + [0.0])),
    }


# ---------- finishing ----------
def finish(x, trim_db):
    """Remove DC, cut the inaudible tail, fade both ends to zero, then set loudness to TARGET_DB + trim_db."""
    x = highpass(x, 35)
    quiet = max(abs(s) for s in x) * 10 ** (-54 / 20)   # tails below this only tie up voices
    last = max(i for i, s in enumerate(x) if abs(s) > quiet)
    x = x[:min(len(x), last + int(0.030 * SR))]
    fin = min(len(x) // 8, int(0.002 * SR))
    fout = min(len(x) // 3, int(0.030 * SR))
    for i in range(fin):
        x[i] *= 0.5 - 0.5 * math.cos(math.pi * i / fin)
    for i in range(fout):
        x[-1 - i] *= 0.5 - 0.5 * math.cos(math.pi * i / fout)
    g = 10 ** ((TARGET_DB + trim_db - db(gated_rms(k_weight(x)))) / 20)
    x = [s * g for s in x]
    peak = max(abs(s) for s in x)
    ceil = 10 ** (CEILING_DB / 20)
    limited = peak > ceil
    if limited:
        x = [s * ceil / peak for s in x]
    return x, limited

def write_wav(path, x):
    data = b"".join(struct.pack("<h", int(round(max(-1.0, min(1.0, s)) * 32767))) for s in x)
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(data)

def read_wav(path):
    with wave.open(path, "rb") as w:
        raw = w.readframes(w.getnframes())
    return [v[0] / 32767 for v in struct.iter_unpack("<h", raw)]


# ---------- the sounds ----------
C5, D5, E5, G5 = 523.25, 587.33, 659.25, 783.99
G4, B5 = 392.0, 987.77
C6, E6, G6, C7, E7, G7 = 1046.5, 1318.5, 1568.0, 2093.0, 2637.0, 3136.0

def merge(f_lo, f_hi, sparkle, seed):
    """Squishy bubbly bloop: a soft low squish, a rounded note that scoops upward, then twinkles."""
    out = tone(0.10, glide(f_lo * 0.62, f_lo * 0.42, 0.03), ad(0.004, 0.035), ((1, 1.0), (2, 0.2)))
    add(out, tone(0.40, glide(f_lo, f_hi, 0.035), ad(0.008, 0.075), ((1, 1.0), (2, 0.22), (3, 0.05))), 0.012, 1.0)
    add(out, lowpass(noise(0.06, ad(0.004, 0.012), seed), 1400), 0.0, 0.10)
    for k, f in enumerate(sparkle):
        add(out, tone(0.35, f, ad(0.004, 0.07)), 0.055 + k * 0.038, 0.085)
    return reverb(out, 0.16, 0.35)

def drop(f_hi, f_lo, seed):
    """Soft plop for letting go: a note that falls away with a little puff of air."""
    out = tone(0.30, glide(f_hi, f_lo, 0.040), ad(0.006, 0.060), ((1, 1.0), (2, 0.18)))
    add(out, lowpass(noise(0.20, ad(0.015, 0.045), seed), 1100), 0.0, 0.16)
    return reverb(out, 0.08, 0.25)

def land(f_hi, f_lo, seed):
    """Tiny padded thud for desserts bumping the jar or each other."""
    out = tone(0.20, glide(f_hi, f_lo, 0.022), ad(0.003, 0.040), ((1, 1.0), (2, 0.30), (3, 0.08)))
    add(out, lowpass(noise(0.08, ad(0.002, 0.014), seed), 650), 0.0, 0.30)
    return out

def chime():
    """Three quick rising bell notes for a big dessert appearing."""
    out = []
    for k, f in enumerate((G5, C6, E6)):
        add(out, bell(f, 0.30 if k < 2 else 0.42), k * 0.065, 0.8 if k < 2 else 1.0)
    add(out, tone(0.5, G7, ad(0.006, 0.10)), 0.20, 0.05)
    return reverb(out, 0.24, 0.7)

def coin():
    """Bright two-note ding: a short pickup note, then a ringing one a fourth higher."""
    out = bell(B5, 0.045, 0.8)
    add(out, bell(E6, 0.12, 1.0), 0.062, 1.0)
    return reverb(out, 0.12, 0.3)

def pop():
    """Pop perk: a round bubble bursting, with a puff of air and two tiny sparkles."""
    out = tone(0.20, glide(260, 980, 0.016), ad(0.003, 0.038), ((1, 1.0), (2, 0.15)))
    add(out, swept_bandpass(noise(0.10, ad(0.002, 0.020), 11), lambda t: 1900.0), 0.0, 0.35)
    add(out, tone(0.30, E7, ad(0.004, 0.06)), 0.050, 0.07)
    add(out, tone(0.30, G7, ad(0.004, 0.07)), 0.085, 0.06)
    return reverb(out, 0.20, 0.4)

def sweep():
    """Sweep perk: an airy rising swish with a glittery run on top."""
    air = swept_bandpass(noise(0.50, hump(0.50, 1.2), 23), lambda t: 500 + 3200 * (t / 0.5) ** 1.6, 0.5)
    out = [s * 0.55 for s in air]
    for k, f in enumerate((C6, E6, G6, C7, E7)):
        add(out, tone(0.35, f, ad(0.004, 0.06)), 0.12 + k * 0.060, 0.09 + k * 0.012)
    return reverb(out, 0.22, 0.5)

def upgrade():
    """Upgrade perk: quick rising arpeggio that lands on a ringing top note."""
    out = []
    for k, f in enumerate((C5, E5, G5, C6)):
        add(out, bell(f, 0.14 if k < 3 else 0.32), k * 0.068, 0.75 if k < 3 else 1.0)
    add(out, tone(0.5, E7, ad(0.006, 0.10)), 0.30, 0.05)
    return reverb(out, 0.22, 0.6)

def fanfare():
    """New dessert discovered: happy rising arpeggio into a held chord with a sparkle on top."""
    out = []
    for k, f in enumerate((G4, C5, E5, G5)):
        add(out, bell(f, 0.16), k * 0.085, 0.8)
    for f, g in ((C5, 0.55), (E5, 0.5), (G5, 0.5), (C6, 0.9)):
        add(out, bell(f, 0.45), 0.36, g)
    for k, f in enumerate((G6, C7, E7)):
        add(out, tone(0.6, f, ad(0.006, 0.12)), 0.50 + k * 0.075, 0.06)
    return reverb(out, 0.26, 0.9)

def gameover():
    """Sad but cute: three soft notes stepping down, then a low one that droops and fades."""
    soft = ((1, 1.0), (2, 0.20), (3, 0.05))
    out = []
    for k, f in enumerate((E5, D5, C5)):
        add(out, tone(0.9, f, ad(0.012, 0.16), soft), k * 0.21, 0.85)
    droop = lambda t: G4 * 2 ** (-(1.5 / 12) * min(1.0, t / 0.6) ** 2) * (1 + 0.006 * math.sin(TAU * 5.5 * t))
    add(out, tone(1.3, droop, ad(0.015, 0.30), soft), 0.63, 1.0)
    return reverb(lowpass(out, 3200), 0.28, 0.9)

def tap():
    """UI tap: a small wooden tick, crisp but with no hard edge."""
    out = tone(0.07, glide(1250, 820, 0.012), ad(0.0015, 0.013), ((1, 1.0), (2, 0.15)))
    add(out, tone(0.03, 2600, ad(0.001, 0.004)), 0.0, 0.18)
    return out

def nope():
    """Can't afford it: two muted notes stepping down, like a gentle "uh-uh"."""
    soft = ((1, 1.0), (2, 0.30), (3, 0.12))
    out = tone(0.12, 329.63, ad(0.005, 0.040), soft)
    add(out, tone(0.22, glide(285, 262, 0.05), ad(0.005, 0.060), soft), 0.105, 1.0)
    return lowpass(out, 2200)

# name -> (builder, trim dB relative to TARGET_DB). The trims are the mix:
# merges and rewards lead, drops and landings sit underneath, UI stays out of the way.
SOUNDS = [
    ("merge_1", lambda: merge(390, 640, (C7, E7), 1), 0.0),
    ("merge_2", lambda: merge(415, 700, (E7, G7), 2), 0.0),
    ("merge_3", lambda: merge(370, 590, (C7, G7, E7), 3), 0.0),
    ("drop_1", lambda: drop(430, 190, 4), -2.0),
    ("drop_2", lambda: drop(465, 205, 5), -2.0),
    ("drop_3", lambda: drop(400, 175, 6), -2.0),
    ("land_1", lambda: land(190, 96, 7), -4.0),
    ("land_2", lambda: land(215, 108, 8), -4.0),
    ("land_3", lambda: land(172, 88, 9), -4.0),
    ("chime", chime, 0.0),
    ("coin", coin, -2.0),
    ("pop", pop, 0.0),
    ("sweep", sweep, -1.0),
    ("upgrade", upgrade, 0.0),
    ("fanfare", fanfare, 0.0),
    ("gameover", gameover, 0.0),
    ("tap", tap, -6.0),
    ("nope", nope, -4.0),
]


def report(rows):
    """Print the table and return False if anything clips or would click."""
    ok = True
    print("%-10s %6s %8s %8s %8s %6s %9s  %s" % ("file", "dur s", "peak dB", "rms dB", "loud dB", "trim", "loud-trim", "start/end"))
    for name, x, trim in rows:
        s = stats(x)
        bad = []
        if s["peak"] > CEILING_DB + 0.01:
            bad.append("CLIPS")
        if s["head"] > 0.002 or s["tail"] > 0.002 or s["step"] > 0.08:
            bad.append("CLICK")
        if trim is not None and abs(s["loud"] - trim - TARGET_DB) > 0.3:
            bad.append("LOUDNESS OFF")
        ok = ok and not bad
        print("%-10s %6.2f %8.1f %8.1f %8.1f %6s %9s  %.4f/%.4f %s" % (
            name, s["dur"], s["peak"], s["rms"], s["loud"],
            "" if trim is None else "%+.0f" % trim,
            "" if trim is None else "%.1f" % (s["loud"] - trim),
            s["head"], s["tail"], " ".join(bad) or "ok"))
    print("peak/rms in dBFS; rms and loud are gated (10 ms blocks within 20 dB of the loudest); "
          "loud is K-weighted; target %.0f, ceiling %.1f" % (TARGET_DB, CEILING_DB))
    return ok


def main():
    args = sys.argv[1:]
    if "--check" in args:
        rows = [(n, read_wav(os.path.join(OUT, n + ".wav")), t) for n, _, t in SOUNDS]
        sys.exit(0 if report(rows) else 1)
    os.makedirs(OUT, exist_ok=True)
    rows = []
    for name, build, trim in SOUNDS:
        x, limited = finish(build(), trim)
        if limited:
            print("note: %s hit the peak ceiling and was turned down" % name)
        write_wav(os.path.join(OUT, name + ".wav"), x)
        rows.append((name, read_wav(os.path.join(OUT, name + ".wav")), trim))
    ok = report(rows)
    if "--preview" in args:
        path = args[args.index("--preview") + 1]
        strip = []
        for _, x, _ in rows:
            strip += x + [0.0] * int(0.45 * SR)
        write_wav(path, strip)
        print("preview: %s (%.1f s, order: %s)" % (path, len(strip) / SR, ", ".join(n for n, _, _ in rows)))
    print("ok" if ok else "FAILED")
    sys.exit(0 if ok else 1)

if __name__ == "__main__":
    main()
