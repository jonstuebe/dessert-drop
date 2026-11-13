"""Generate the game's sound effects as 16-bit mono WAVs (stdlib only).
Run: python3 tools/make_sfx.py  -> writes assets/sfx/*.wav"""
import math, random, struct, wave, os

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sfx")
random.seed(7)

def env(t, a, d):  # attack, exponential decay
    return min(1.0, t / a) * math.exp(-t / d) if a > 0 else math.exp(-t / d)

def write(name, samples, gain=0.8):
    peak = max(1e-9, max(abs(s) for s in samples))
    data = b"".join(struct.pack("<h", int(max(-1, min(1, s / peak * gain)) * 32767)) for s in samples)
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(data)

def render(dur, fn):
    return [fn(i / SR) for i in range(int(dur * SR))]

def tone(f, t, shape="sine"):
    p = 2 * math.pi * f * t
    if shape == "tri":
        return 2 / math.pi * math.asin(math.sin(p))
    return math.sin(p)

# Bubbly "pop" for merges: pitch drops fast, little noise click at start.
def pop(t):
    f = 520 + 900 * math.exp(-t / 0.018)
    return tone(f, t) * env(t, 0.002, 0.07) + random.uniform(-1, 1) * env(t, 0.0005, 0.004) * 0.4
write("merge.wav", render(0.22, pop))

# Soft drop: low thump plus a breathy whoosh.
def drop(t):
    f = 180 + 160 * math.exp(-t / 0.03)
    return tone(f, t) * env(t, 0.004, 0.06) * 0.8 + random.uniform(-1, 1) * env(t, 0.01, 0.05) * 0.15
write("drop.wav", render(0.2, drop), 0.6)

# Chime for big desserts: bell partials.
def bell(f0, t):
    return sum(a * tone(f0 * m, t) * env(t, 0.002, d) for m, a, d in ((1, 1, .5), (2.01, .5, .3), (3.0, .25, .18), (4.2, .12, .1)))
write("chime.wav", render(1.0, lambda t: bell(880, t) + bell(1318.5, max(0, t - .08)) * (t > .08)))

# Coin: classic two-step ding.
def coin(t):
    f = 988 if t < 0.07 else 1319
    return tone(f, t, "tri") * env(t if t < .07 else t - .07, 0.002, 0.12 if t < .07 else 0.25)
write("coin.wav", render(0.45, coin), 0.55)

# Perk sounds
write("pop.wav", render(0.3, lambda t: tone(300 + 1400 * math.exp(-t / .03), t) * env(t, .001, .06)
      + random.uniform(-1, 1) * env(t, .0005, .02) * .6))
def sweep(t):
    n = random.uniform(-1, 1)
    sweep.lp = getattr(sweep, "lp", 0) + (n - getattr(sweep, "lp", 0)) * (0.05 + 0.5 * t)
    return sweep.lp * math.sin(math.pi * min(1, t / 0.45))
write("sweep.wav", render(0.45, sweep), 0.7)
NOTES = [523.25, 659.25, 783.99, 1046.5]
def arp(t, step=0.07, d=0.25):
    s = 0
    for k, f in enumerate(NOTES):
        tt = t - k * step
        if tt > 0: s += tone(f, tt, "tri") * env(tt, .003, d)
    return s
write("upgrade.wav", render(0.7, arp), 0.6)
write("fanfare.wav", render(1.2, lambda t: arp(t, .09, .4) + bell(1046.5, max(0, t - .36)) * (t > .36) * .5), 0.6)

# Game over: gentle descending notes.
def over(t):
    s = 0
    for k, f in enumerate([659.25, 587.33, 523.25, 392.0]):
        tt = t - k * .16
        if tt > 0: s += tone(f, tt, "tri") * env(tt, .005, .35 if k == 3 else .18)
    return s
write("gameover.wav", render(1.4, over), 0.6)

# UI tap and "nope" buzz
write("tap.wav", render(0.08, lambda t: tone(1200 - 4000 * t, t) * env(t, .001, .02)), 0.5)
write("nope.wav", render(0.25, lambda t: (tone(180, t, "tri") + tone(190, t, "tri")) * env(t, .005, .1)), 0.5)
print("ok")
