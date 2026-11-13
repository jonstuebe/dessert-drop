#!/usr/bin/env python3
"""Build the Dessert Drop trailer: a 9:16 clip for social posts.

    python3 tools/make_trailer.py [out_dir] [--record]

Writes into out_dir (default export/trailer):
    dessert-drop-trailer.mp4          1080x1920, 60 fps, H.264 + AAC
    dessert-drop-trailer-poster.jpg   one strong frame
    trailer-strip.png                 five frames side by side, for a quick look

Steps: record gameplay with tools/record_trailer.sh (two autoplay takes and the
scripted "wedding" shot; kept in out_dir/work and reused unless --record is
given), pick the cuts from each take's event list, render the captions and the
end card with headless Chrome, synthesise a small music bed, and edit it all
together with ffmpeg. Needs godot 4.7, ffmpeg, Google Chrome and the Python
standard library. The gameplay is physics, so a fresh recording never plays out
exactly the same; the cuts follow the events, so the edit still lands.
"""
import math
import os
import random
import re
import struct
import subprocess
import sys
import wave

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_og as g  # the share-image generator: logo, art and Chrome helpers

ROOT = g.ROOT
W, H, FPS = 1080, 1920, 60
URL = "dessert-drop.jonstuebe.com"

# ---------- the edit, in seconds ----------
BAR = 2.0                 # one bar of the music bed (120 bpm)
HOOK_LEN = 2 * BAR        # opens on a cascade from an autoplay take
CLIMB_LEN = 3 * BAR       # a busy stretch of another take, sped up
CLIMB_SPEED = 1.3
HOOK_LEAD = 0.65          # the first merge of the hook lands this far in
WEDDING_AT = HOOK_LEN + CLIMB_LEN + BAR   # the wedding cake appears on this downbeat
END_AT = WEDDING_AT + 4.2
END_LEN = 3.6
TOTAL = END_AT + END_LEN

CAPTIONS = [  # lines, font size, start, end; a line starting with * is set in yellow
    (["Drop two."], 156, 0.12, 1.5),
    (["Bake something", "*bigger."], 124, 1.7, HOOK_LEN - 0.15),
    (["Every match bakes", "*the next dessert."], 106, HOOK_LEN + 0.2, HOOK_LEN + 2.8),
    (["Just don't let", "*the jar overflow."], 106, HOOK_LEN + 3.1, HOOK_LEN + CLIMB_LEN - 0.15),
    (["Can you reach", "*the wedding cake?"], 106, HOOK_LEN + CLIMB_LEN + 0.15, WEDDING_AT - 0.1),
]
CAPTION_Y = 740           # centre of the caption block: the empty top of the jar


def run(cmd, **kw):
    return subprocess.run(cmd, check=True, **kw)


# ---------- footage ----------
def events(mp4):
    """[(frame, kind, tier)] for a take, from the list record_trailer.sh writes."""
    out = []
    with open(os.path.splitext(mp4)[0] + ".events.txt") as fh:
        for line in fh:
            m = re.search(r"frame=(\d+) kind=(\w+) tier=(\d+)", line)
            if m:
                out.append((int(m.group(1)), m.group(2), int(m.group(3))))
    return out


def merges(mp4):
    return [(f, t) for f, k, t in events(mp4) if k == "merge"]


def record(work, name, seconds, shot, seeds, good):
    """Record a take, trying each seed until good(mp4) says it has what the edit needs."""
    mp4 = os.path.join(work, name + ".mp4")
    if os.path.exists(mp4) and good(mp4):
        return mp4
    for seed in seeds:
        print(f"recording {name} (seed {seed})", flush=True)
        run([os.path.join(ROOT, "tools", "record_trailer.sh"), mp4, str(seconds), str(seed), shot],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if good(mp4):
            return mp4
    sys.exit(f"no usable {name} take from seeds {seeds}")


def best_window(mp4, length, first=0.0, last=None):
    """Start (s) of the `length`-second stretch whose merges add up to the most tiers."""
    ms = merges(mp4)
    last = (ms[-1][0] / FPS if last is None else last) - length
    best, best_score = first, -1.0
    t = first
    while t <= max(first, last):
        score = sum(tier * tier for f, tier in ms if t <= f / FPS < t + length)
        if score > best_score:
            best, best_score = t, score
        t += 0.1
    return best


def hook_start(mp4, total):
    """Open just before the densest cascade: the most tiers baked inside 1.5 s."""
    ms = merges(mp4)
    burst = best_window(mp4, 1.5, first=HOOK_LEAD, last=total - HOOK_LEN + 1.5)
    first = min(f for f, _ in ms if f / FPS >= burst)
    return max(0.0, first / FPS - HOOK_LEAD)


# ---------- cards ----------
def shoot(svg, png, tmp):
    """Render an SVG to a transparent 1080x1920 PNG with headless Chrome."""
    html = g.PAGE.format(fonts=g.FONTS, bg="transparent", css="", body=svg)
    page = os.path.join(tmp, os.path.basename(png) + ".html")
    with open(page, "w") as fh:
        fh.write(html)
    run([g.chrome(), "--headless=new", "--disable-gpu", "--hide-scrollbars", "--no-first-run",
         "--force-device-scale-factor=1", "--allow-file-access-from-files", "--default-background-color=00000000",
         f"--user-data-dir={os.path.join(tmp, 'profile')}", f"--window-size={W},{H}",
         "--virtual-time-budget=4000", f"--screenshot={png}", "file://" + page],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=120)
    if g.png_size(png) != (W, H):
        sys.exit(f"{png} is {g.png_size(png)}, expected {(W, H)}")


def svg(body):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">{body}</svg>'


def caption(lines, size):
    """Sticker lettering like the logo: plum outline, pink rim, white or yellow face."""
    gap = size * 1.08
    y0 = CAPTION_Y - gap * (len(lines) - 1) / 2 + size * 0.34
    words = []
    for k, line in enumerate(lines):
        yellow = line.startswith("*")
        top, bottom = ("#FFF6AE", "#FFA83D") if yellow else ("#FFFFFF", "#FFC4D9")
        words.append(g._word(line.lstrip("*"), W / 2, y0 + k * gap, size, top, bottom))
    out = [f'<g transform="rotate(-3 {W / 2} {CAPTION_Y})">']
    for layer in range(3):
        out += [w[layer] for w in words]
    out.append("</g>")
    return svg("".join(out))


def end_card():
    """The end card as layers (background, logo, desserts, call to action) so they can arrive in turn."""
    gid = g.uid("sun")
    bg = (f'<defs><radialGradient id="{gid}" cx="0.5" cy="0.5" r="0.75"><stop offset="0" stop-color="#FFF6C4"/>'
          f'<stop offset="0.55" stop-color="#FFE07A"/><stop offset="1" stop-color="#FFC24A"/></radialGradient></defs>'
          f'<rect width="{W}" height="{H}" fill="url(#{gid})"/>' + g.rays(W / 2, 980, 18, 1500, "#FFFFFF", 0.26))
    logo = g.logo(W / 2, 400, 200)
    base = 1250
    hero = [g.ground_shadow(W / 2, base, 430, 26, 0.2, "#A8560A"),
            g.dessert_on(5, 190, base + 4, 112, -8), g.dessert_on(4, 900, base + 4, 98, 8),
            g.dessert_on(8, W / 2, base + 8, 216)]
    for x, y, s in [(150, 880, 26), (940, 800, 34), (800, 900, 16), (280, 780, 16)]:
        hero.append(g.star4(x, y, s, "#FFFFFF", g.ACCENT))
    cta = [g.pill(W / 2, 1440, 860, 132, "Play free in your browser", 62),
           g.text(URL, W / 2, 1640, 74, g.PLUM, "Lilita One", 400, stroke="#FFFFFF", sw=14)]
    return {"end_bg": svg(bg), "end_logo": svg(logo), "end_hero": svg("".join(hero)), "end_cta": svg("".join(cta))}


# ---------- music bed ----------
SR = 44100
NOTE = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def hz(name):
    return 440.0 * 2 ** ((NOTE[name[0]] + 12 * (int(name[-1]) + 1) - 69) / 12)


def pluck(buf, at, freq, dur, gain, bright=0.3):
    """A soft mallet note: a sine with two quieter partials that die away faster."""
    i0 = int(at * SR)
    n = min(int(dur * 5 * SR), len(buf) - i0)
    w = 2 * math.pi * freq / SR
    for i in range(max(0, n)):
        t = i / SR
        a = min(1.0, t / 0.004)
        s = (math.sin(w * i) * math.exp(-t / dur) + bright * math.sin(2 * w * i) * math.exp(-t / (dur * 0.5))
             + bright * 0.35 * math.sin(4 * w * i) * math.exp(-t / (dur * 0.25)))
        buf[i0 + i] += s * a * gain


def music(path):
    """Eight bars of plucked arpeggios over a soft bass, a run up into the wedding cake, and a last chord."""
    buf = [0.0] * int((TOTAL + 0.5) * SR)
    chords = {"C": ("C3", ["C5", "G4", "E5", "G4"]), "Am": ("A2", ["A4", "E5", "C5", "E5"]),
              "F": ("F2", ["F4", "C5", "A4", "C5"]), "G": ("G2", ["G4", "D5", "B4", "D5"])}
    bars = ["C", "Am", "F", "G", "C", "Am", "F", "G", "C", "F"]
    beat = BAR / 4
    rnd = random.Random(3)
    for b, name in enumerate(bars):
        t0 = b * BAR
        if t0 >= END_AT - 0.1:
            break
        bass, arp = chords[name]
        lift = 2.0 if t0 >= WEDDING_AT else 1.0   # an octave up once the cake is baked
        for k in range(8):
            t = t0 + k * beat / 2
            pluck(buf, t, hz(arp[k % 4]) * lift, 0.16, 0.20 if k % 2 == 0 else 0.13)
            if lift > 1.0:
                pluck(buf, t, hz(arp[k % 4]), 0.16, 0.08)
        for k in (0, 2.5):
            pluck(buf, t0 + k * beat, hz(bass), 0.3, 0.34, 0.12)
        for k in (1, 3):   # a little shaker on the backbeat
            i0 = int((t0 + k * beat) * SR)
            prev = 0.0
            for i in range(int(0.05 * SR)):
                x = rnd.uniform(-1, 1)
                buf[i0 + i] += (x - prev) * 0.035 * math.exp(-i / (0.012 * SR))
                prev = x
    for k, n in enumerate(["G5", "C6", "E6", "G6", "C7"]):   # the run into the wedding cake
        pluck(buf, WEDDING_AT - 0.3 + k * 0.075, hz(n), 0.25, 0.16, 0.2)
    for n, gain in [("C3", 0.34), ("C5", 0.2), ("E5", 0.17), ("G5", 0.17), ("C6", 0.14)]:   # the end card
        pluck(buf, END_AT, hz(n), 0.9, gain, 0.2)
    peak = max(abs(x) for x in buf)
    with wave.open(path, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SR)
        wf.writeframes(b"".join(struct.pack("<h", int(x / peak * 0.7 * 32767)) for x in buf))


# ---------- the edit ----------
def edit(shots, cuts, cards, bed, out):
    hook, climb, wed = cuts
    inputs = []
    for mp4 in shots:
        inputs += ["-i", mp4]
    names = [f"cap{k}" for k in range(len(CAPTIONS))] + ["end_bg", "end_logo", "end_hero", "end_cta"]
    for n in names:
        inputs += ["-loop", "1", "-framerate", str(FPS), "-t", f"{TOTAL}", "-i", cards[n]]
    inputs += ["-i", bed]
    first_card, bed_in = 3, 3 + len(names)
    wed_len = END_AT - (HOOK_LEN + CLIMB_LEN)
    climb_src = CLIMB_LEN * CLIMB_SPEED

    fc = [f"[0:v]trim=start={hook:.3f}:duration={HOOK_LEN},setpts=PTS-STARTPTS[v0]",
          f"[1:v]trim=start={climb:.3f}:duration={climb_src},setpts=(PTS-STARTPTS)/{CLIMB_SPEED}[v1]",
          f"[2:v]trim=start={wed:.3f}:duration={wed_len},setpts=PTS-STARTPTS[v2]",
          f"[v0][v1][v2]concat=n=3:v=1:a=0,fps={FPS},tpad=stop_mode=clone:stop_duration={END_LEN + 1}[base0]"]
    last = "base0"

    def layer(k, name, a, b, rise):
        """Fade a full-frame card in at a (sliding up `rise` px into place) and out at b."""
        nonlocal last
        fade = f"format=rgba,fade=t=in:st={a:.3f}:d=0.14:alpha=1"
        if b < TOTAL:
            fade += f",fade=t=out:st={b - 0.14:.3f}:d=0.14:alpha=1"
        fc.append(f"[{k}:v]{fade}[c{name}]")
        y = f"if(lt(t,{a + 0.22:.3f}),{rise}*pow(1-(t-{a:.3f})/0.22,2),0)"
        fc.append(f"[{last}][c{name}]overlay=x=0:y='{y}':enable='between(t,{a:.3f},{b:.3f})'[o{name}]")
        last = f"o{name}"

    for k, (_, _, a, b) in enumerate(CAPTIONS):
        layer(first_card + k, f"cap{k}", a, b, 46)
    n = first_card + len(CAPTIONS)
    layer(n, "bg", END_AT, TOTAL, 0)
    layer(n + 1, "logo", END_AT + 0.15, TOTAL, -70)
    layer(n + 2, "hero", END_AT + 0.4, TOTAL, 70)
    layer(n + 3, "cta", END_AT + 0.7, TOTAL, 50)
    fc.append(f"[{last}]trim=duration={TOTAL},format=yuv420p[v]")

    fc += [f"[0:a]atrim=start={hook:.3f}:duration={HOOK_LEN},asetpts=PTS-STARTPTS[a0]",
           f"[1:a]atrim=start={climb:.3f}:duration={climb_src},asetpts=PTS-STARTPTS,atempo={CLIMB_SPEED}[a1]",
           f"[2:a]atrim=start={wed:.3f}:duration={wed_len},asetpts=PTS-STARTPTS[a2]",
           f"[a0][a1][a2]concat=n=3:v=0:a=1,afade=t=out:st={END_AT - 0.1}:d=0.9,apad=whole_dur={TOTAL},"
           f"aformat=channel_layouts=stereo,asplit[sfx][key]",
           # the bed sits under the game sounds and dips whenever they play
           f"[{bed_in}:a]aformat=channel_layouts=stereo,volume=0.5[bed]",
           "[bed][key]sidechaincompress=threshold=0.03:ratio=5:attack=8:release=280[ducked]",
           f"[sfx][ducked]amix=inputs=2:normalize=0,loudnorm=I=-16:TP=-1.5:LRA=11,"
           f"atrim=duration={TOTAL},afade=t=in:d=0.03,afade=t=out:st={TOTAL - 0.5}:d=0.5,aresample=48000[a]"]

    run(["ffmpeg", "-y", "-loglevel", "error", *inputs, "-filter_complex", ";".join(fc),
         "-map", "[v]", "-map", "[a]", "-r", str(FPS), "-c:v", "libx264", "-preset", "slow", "-crf", "19",
         "-profile:v", "high", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k",
         "-movflags", "+faststart", "-t", f"{TOTAL}", out])


def stills(mp4, out_dir):
    poster = os.path.join(out_dir, "dessert-drop-trailer-poster.jpg")
    run(["ffmpeg", "-y", "-loglevel", "error", "-ss", f"{WEDDING_AT + 2.6}", "-i", mp4,
         "-frames:v", "1", "-q:v", "2", poster])
    times = [1.6, HOOK_LEN + 1.5, WEDDING_AT - 0.9, WEDDING_AT + 2.6, END_AT + 2.0]
    sel = "+".join(f"eq(n,{int(t * FPS)})" for t in times)
    strip = os.path.join(out_dir, "trailer-strip.png")
    run(["ffmpeg", "-y", "-loglevel", "error", "-i", mp4, "-vf",
         f"select='{sel}',scale=432:-1,tile=5x1:padding=12:color=white", "-frames:v", "1", strip])
    return poster, strip


def main():
    args = sys.argv[1:]
    fresh = "--record" in args
    args = [a for a in args if a != "--record"]
    out_dir = os.path.abspath(args[0]) if args else os.path.join(ROOT, "export", "trailer")
    work = os.path.join(out_dir, "work")
    os.makedirs(work, exist_ok=True)
    if fresh:
        for f in os.listdir(work):
            if f.endswith((".mp4", ".events.txt")):
                os.remove(os.path.join(work, f))

    take = 16
    busy = lambda mp4: max((t for _, t in merges(mp4)), default=0) >= 6
    # the wedding cake must be baked late enough to cut in a bar ahead of it, with room to celebrate
    baked = lambda mp4: [f for f, t in merges(mp4) if t == 8]
    wedded = lambda mp4: (bool(baked(mp4)) and BAR * FPS <= baked(mp4)[0] <= (8.5 - 4.3) * FPS
                          and ("upright", 8) in [(k, t) for _, k, t in events(mp4)])
    a = record(work, "play-a", take, "auto", [7, 8, 9, 10], busy)
    b = record(work, "play-b", take, "auto", [11, 12, 13, 14], busy)
    w = record(work, "wedding", 8.5, "wedding", list(range(1, 13)), wedded)

    cuts = (hook_start(a, take), best_window(b, CLIMB_LEN * CLIMB_SPEED, 0.5, take - 0.5),
            baked(w)[0] / FPS - BAR)
    print("cuts (s): hook %.2f, climb %.2f, wedding %.2f" % cuts)

    cards = {}
    sheets = {f"cap{k}": caption(lines, size) for k, (lines, size, _, _) in enumerate(CAPTIONS)}
    sheets.update(end_card())
    for name, body in sheets.items():
        cards[name] = os.path.join(work, name + ".png")
        shoot(body, cards[name], work)
    bed = os.path.join(work, "bed.wav")
    music(bed)

    out = os.path.join(out_dir, "dessert-drop-trailer.mp4")
    edit([a, b, w], cuts, cards, bed, out)
    poster, strip = stills(out, out_dir)
    print(f"{out}  {os.path.getsize(out) / 1e6:.1f} MB, {TOTAL:.1f} s")
    print(poster)
    print(strip)


if __name__ == "__main__":
    main()
