#!/usr/bin/env python3
"""Open Graph / link-preview image options for Dessert Drop.

Builds five 1200x630 concepts from the game's own art (assets/art/*.svg) and fonts,
renders them with headless Chrome, then writes a 600x600 centre crop of each
(option-N-square.png) and a contact sheet.

    python3 tools/gen_og.py [out_dir] [--only N]

Needs only the Python standard library, Google Chrome (or Chromium) and macOS `sips`.
Nothing here is wired into the build; pick an option and copy it where it is needed.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ART = os.path.join(ROOT, "assets", "art")
FONTS = os.path.join(ROOT, "assets", "fonts")
DEFAULT_OUT = ("/private/tmp/claude-501/-Users-jonstuebe-orca-dessert-drop/"
               "5b00bb4a-3b2f-46e5-951b-c974127d2abc/scratchpad/og")
W, H = 1200, 630
CHROME_CANDIDATES = [
    os.environ.get("CHROME", ""),
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
    shutil.which("google-chrome") or "",
    shutil.which("chromium") or "",
]

# palette (web/shell.html and scripts/ui.gd)
INK, MUTED = "#4A2618", "#7A5648"
ACCENT, ACCENT_DK = "#E8427F", "#A81F58"
PLUM, PLUM_DK = "#7C1440", "#4E0A28"
SURFACE, LINE, EDGE = "#FFF9F2", "#F1DCCB", "#E6CBB4"
WALL = "#AEE0D8"

DESSERTS = ["d0_sprinkle", "d1_chip", "d2_cookie", "d3_macaron", "d4_cupcake",
            "d5_donut", "d6_pie", "d7_cake", "d8_wedding"]
GROWTH = [1.10, 1.13, 1.16, 1.19, 1.22, 1.25, 1.28, 1.31]   # scripts/tiers.gd
ART_R = 30.0

_uid = 0


def uid(prefix="g"):
    global _uid
    _uid += 1
    return f"{prefix}{_uid}"


def f(v):
    return f"{v:.2f}".rstrip("0").rstrip(".")


def game_radius(i):
    r = 26.0 * 1.6
    for k in range(i):
        r *= GROWTH[k]
    return r


_vb = {}


def viewbox(name):
    if name not in _vb:
        with open(os.path.join(ART, name + ".svg")) as fh:
            m = re.search(r'viewBox="([^"]+)"', fh.read(600))
        _vb[name] = [float(v) for v in m.group(1).split()]
    return _vb[name]


def art(name, cx, cy, s=1.0, rot=0.0, extra=""):
    """An art SVG with its own origin (viewBox 0,0) at cx,cy, scaled by s."""
    x, y, w, h = viewbox(name)
    href = "file://" + os.path.join(ART, name + ".svg")
    return (f'<g transform="translate({f(cx)} {f(cy)}) rotate({f(rot)}) scale({f(s)})" {extra}>'
            f'<image href="{href}" x="{f(x)}" y="{f(y)}" width="{f(w)}" height="{f(h)}"/></g>')


def dessert(i, cx, cy, r, rot=0.0, extra=""):
    """Dessert tier i centred at cx,cy with body radius r pixels."""
    return art(DESSERTS[i], cx, cy, r / ART_R, rot, extra)


def dessert_on(i, cx, base_y, r, rot=0.0, extra=""):
    """Dessert tier i standing on the line y=base_y."""
    x, y, w, h = viewbox(DESSERTS[i])
    s = r / ART_R
    return dessert(i, cx, base_y - (y + h) * s, r, rot, extra)


def star4(cx, cy, s, fill="#FFFFFF", stroke=None, rot=0.0):
    k = 0.2
    pts = [(0, -s), (k * s, -k * s), (s, 0), (k * s, k * s), (0, s), (-k * s, k * s), (-s, 0), (-k * s, -k * s)]
    d = "M" + "L".join(f"{f(x)} {f(y)}" for x, y in pts) + "Z"
    st = f' stroke="{stroke}" stroke-width="{f(s * 0.16)}" stroke-linejoin="round"' if stroke else ""
    return f'<path transform="translate({f(cx)} {f(cy)}) rotate({f(rot)})" d="{d}" fill="{fill}"{st}/>'


def _word(text, x, y, size, top, bottom, anchor="middle"):
    """Sticker lettering like the in-game logo: returns the three layers separately."""
    gid = uid("lg")
    base = (f'x="{f(x)}" y="{f(y)}" font-family="Lilita One" font-size="{f(size)}" '
            f'text-anchor="{anchor}" stroke-linejoin="round" stroke-linecap="round"')
    grad = (f'<linearGradient id="{gid}" x1="0" y1="0" x2="0" y2="1">'
            f'<stop offset="0.5" stop-color="{top}"/><stop offset="0.86" stop-color="{bottom}"/></linearGradient>')
    l0 = (f'<text {base} fill="{PLUM_DK}" stroke="{PLUM_DK}" stroke-width="{f(size * 0.36)}" '
          f'transform="translate(0 {f(size * 0.1)})">{text}</text>'
          f'<text {base} fill="{PLUM}" stroke="{PLUM}" stroke-width="{f(size * 0.36)}">{text}</text>')
    l1 = f'<text {base} fill="{ACCENT}" stroke="{ACCENT}" stroke-width="{f(size * 0.16)}">{text}</text>'
    l2 = f'{grad}<text {base} fill="url(#{gid})">{text}</text>'
    return l0, l1, l2


def logo(cx, cy, size, rot=-4.0, stacked=True, stars=True):
    """The Dessert Drop logo centred at cx,cy. `size` is the font size of "Dessert"."""
    S = size
    if stacked:
        big = 1.55 * S
        words = [_word("Dessert", -0.12 * S, -0.32 * S, S, "#FFFFFF", "#FFC4D9"),
                 _word("Drop", 0.22 * S, 0.98 * S, big, "#FFF6AE", "#FFA83D")]
        sp = [(1.95, -0.86, 0.3), (-1.95, 0.5, 0.2), (1.85, 1.1, 0.16)]
    else:
        # one line: "Dessert" then "Drop", centred as a pair (advance widths ~3.12em and ~1.94em)
        gap = 0.5 * S
        left, right = 3.12 * S, 1.94 * S
        x0 = -(left + gap + right) / 2
        words = [_word("Dessert", x0, 0.36 * S, S, "#FFFFFF", "#FFC4D9", "start"),
                 _word("Drop", x0 + left + gap, 0.36 * S, S, "#FFF6AE", "#FFA83D", "start")]
        sp = [(3.15, -0.62, 0.26), (-3.2, 0.5, 0.18)]
    out = [f'<g transform="translate({f(cx)} {f(cy)}) rotate({f(rot)})">']
    for layer in range(3):
        for wd in words:
            out.append(wd[layer])
    if stars:
        for x, y, s in sp:
            out.append(star4(x * S, y * S, s * S, "#FFF6AE", PLUM))
    out.append("</g>")
    return "".join(out)


def text(s, x, y, size, fill=INK, family="Fredoka", weight=700, anchor="middle", stroke=None, sw=0.0,
         spacing=0.0, extra=""):
    st = (f' stroke="{stroke}" stroke-width="{f(sw)}" stroke-linejoin="round" paint-order="stroke"'
          if stroke else "")
    return (f'<text x="{f(x)}" y="{f(y)}" font-family="{family}" font-weight="{weight}" font-size="{f(size)}" '
            f'letter-spacing="{f(spacing)}" text-anchor="{anchor}" fill="{fill}"{st} {extra}>{s}</text>')


def pill(cx, cy, w, h, label, size, fill=SURFACE, ink=INK, edge=EDGE, line=LINE, family="Fredoka", weight=700):
    """The cream card from the preloader, as a caption pill."""
    x, y, r = cx - w / 2, cy - h / 2, h / 2
    return (f'<rect x="{f(x)}" y="{f(y + 9)}" width="{f(w)}" height="{f(h)}" rx="{f(r)}" fill="#33140A" opacity="0.16"/>'
            f'<rect x="{f(x)}" y="{f(y + 5)}" width="{f(w)}" height="{f(h)}" rx="{f(r)}" fill="{edge}"/>'
            f'<rect x="{f(x)}" y="{f(y)}" width="{f(w)}" height="{f(h)}" rx="{f(r)}" fill="{fill}" stroke="{line}" stroke-width="2"/>'
            + text(label, cx, cy + size * 0.35, size, ink, family, weight))


def tile_wall():
    """Mint tiled wall, the same pattern as the preloader in web/shell.html."""
    pid, gid, lid = uid("tile"), uid("wall"), uid("glow")
    return (f'<defs><pattern id="{pid}" width="112" height="56" patternUnits="userSpaceOnUse">'
            f'<path d="M0 1H112M0 29H112M1 1V29M57 29V57" fill="none" stroke="#fff" stroke-opacity=".45" stroke-width="2"/>'
            f'<path d="M0 27H112M0 55H112M55 1V27M111 29V55" fill="none" stroke="#387f77" stroke-opacity=".12" stroke-width="2"/>'
            f'</pattern>'
            f'<linearGradient id="{gid}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#CDEFE7"/>'
            f'<stop offset="0.45" stop-color="#AEE0D8"/><stop offset="1" stop-color="#8ACCC4"/></linearGradient>'
            f'<radialGradient id="{lid}" cx="0.2" cy="0" r="0.7"><stop offset="0" stop-color="#FFF4D0" stop-opacity="0.55"/>'
            f'<stop offset="1" stop-color="#FFF4D0" stop-opacity="0"/></radialGradient></defs>'
            f'<rect width="{W}" height="{H}" fill="url(#{gid})"/><rect width="{W}" height="{H}" fill="url(#{pid})"/>'
            f'<rect width="{W}" height="{H}" fill="url(#{lid})"/>')


def rays(cx, cy, n, radius, fill, opacity):
    import math
    out = [f'<g fill="{fill}" opacity="{f(opacity)}">']
    step = math.tau / n
    for k in range(n):
        a0, a1 = k * step, k * step + step / 2
        out.append(f'<path d="M{f(cx)} {f(cy)}L{f(cx + radius * math.cos(a0))} {f(cy + radius * math.sin(a0))}'
                   f'L{f(cx + radius * math.cos(a1))} {f(cy + radius * math.sin(a1))}Z"/>')
    out.append("</g>")
    return "".join(out)


def sprinkles(items):
    """Loose sprinkle capsules: (x, y, angle, colour, length)."""
    out = []
    for x, y, ang, col, ln in items:
        out.append(f'<rect transform="translate({f(x)} {f(y)}) rotate({f(ang)})" x="{f(-ln / 2)}" y="{f(-ln * 0.17)}" '
                   f'width="{f(ln)}" height="{f(ln * 0.34)}" rx="{f(ln * 0.17)}" fill="{col}" '
                   f'stroke="#33140A" stroke-opacity="0.18" stroke-width="1.5"/>')
    return "".join(out)


def ground_shadow(cx, cy, rx, ry, a=0.18, col="#33140A"):
    gid = uid("sh")
    return (f'<radialGradient id="{gid}"><stop offset="0.3" stop-color="{col}" stop-opacity="{a}"/>'
            f'<stop offset="1" stop-color="{col}" stop-opacity="0"/></radialGradient>'
            f'<ellipse cx="{f(cx)}" cy="{f(cy)}" rx="{f(rx)}" ry="{f(ry)}" fill="url(#{gid})"/>')


# ---------- the five concepts ----------

def option_1():
    """Jar hero: the game scene, wide. A full jar on the counter under the logo."""
    k = 0.62                      # jar scale; jar art is 640x940 with the inner floor at y=889
    jx, jy = 600 - 320 * k, 24
    floor = jy + 889 * k
    o = [tile_wall()]
    # counter, stretched across like the game does
    ctop = floor - 70 * k
    o.append(f'<image href="file://{ART}/counter.svg" x="0" y="{f(ctop)}" width="{W}" height="{f(310 * k)}" preserveAspectRatio="none"/>')
    o.append(art("prop_plant", 96 - 70 * 0.86, floor - 6 - 222 * 0.86, 0.86))
    o.append(art("prop_crock", 1104 - 70 * 0.86, floor - 6 - 242 * 0.86, 0.86))
    # friends on the counter
    o.append(ground_shadow(262, floor + 2, 120, 14))
    o.append(dessert_on(7, 262, floor + 6, 62))
    o.append(dessert_on(2, 372, floor + 10, 26, -8))
    o.append(ground_shadow(930, floor + 2, 100, 14))
    o.append(dessert_on(6, 940, floor + 8, 60, 6))
    o.append(dessert_on(0, 846, floor + 8, 21, 0))
    # jar and its pile (jar-local coordinates, game-sized desserts)
    o.append(f'<g transform="translate({f(jx)} {f(jy)}) scale({k})">')
    o.append(f'<image href="file://{ART}/jar_back.svg" width="640" height="940"/>')
    pile = [(8, 196, 705, 0), (5, 492, 800, 14), (4, 520, 628, 16), (6, 400, 566, -12),
            (3, 116, 470, -78), (0, 536, 506, -28), (2, 420, 720, -30), (1, 372, 812, -8), (0, 300, 868, 0)]
    for i, x, y, rot in pile:
        o.append(dessert(i, x, y, game_radius(i), rot))
    o.append(f'<image href="file://{ART}/jar_front.svg" width="640" height="940"/>')
    o.append("</g>")
    o.append(logo(600, 164, 90))
    return "".join(o)


def option_2():
    """Merge chain: all nine desserts in order on a shelf, small to wedding cake."""
    o = [f'<rect width="{W}" height="{H}" fill="{SURFACE}"/>']
    pid = uid("dots")
    o.append(f'<defs><pattern id="{pid}" width="44" height="44" patternUnits="userSpaceOnUse">'
             f'<circle cx="11" cy="11" r="3.2" fill="{LINE}"/><circle cx="33" cy="33" r="3.2" fill="{LINE}"/></pattern></defs>'
             f'<rect width="{W}" height="{H}" fill="url(#{pid})"/>')
    o.append(logo(600, 138, 96, rot=-3, stacked=False))
    base = 432
    o.append(f'<image href="file://{ART}/shelf.svg" x="70" y="{base - 7}" width="1060" height="64" preserveAspectRatio="none"/>')
    radii = [19.0 * (1.158 ** i) for i in range(9)]
    widths = []
    for i, r in enumerate(radii):
        widths.append(viewbox(DESSERTS[i])[2] * r / ART_R)
    gap = (1000 - sum(widths)) / 8
    x = 100.0
    for i, r in enumerate(radii):
        cx = x + widths[i] / 2
        o.append(dessert_on(i, cx, base, r))
        if i < 8:
            ax = x + widths[i] + gap / 2
            ay = base - 30 - i * 3.2
            a = 7 + i * 0.5
            o.append(f'<path d="M{f(ax - a * 0.55)} {f(ay - a)}L{f(ax + a * 0.55)} {f(ay)}L{f(ax - a * 0.55)} {f(ay + a)}" '
                     f'fill="none" stroke="{ACCENT}" stroke-width="{f(5 + i * 0.3)}" stroke-linecap="round" stroke-linejoin="round"/>')
        x += widths[i] + gap
    o.append(text("Match two. Bake the next one.", 600, 556, 48, INK, weight=600))
    return "".join(o)


def option_3():
    """Merge moment: cupcake + cupcake = donut, on a sunburst."""
    gid = uid("sun")
    o = [f'<defs><radialGradient id="{gid}" cx="0.5" cy="0.56" r="0.75"><stop offset="0" stop-color="#FFF6C4"/>'
         f'<stop offset="0.55" stop-color="#FFE07A"/><stop offset="1" stop-color="#FFC24A"/></radialGradient></defs>'
         f'<rect width="{W}" height="{H}" fill="url(#{gid})"/>']
    o.append(rays(600, 352, 18, 900, "#FFFFFF", 0.26))
    cy = 356
    o.append(ground_shadow(600, cy + 104, 330, 20, 0.2, "#A8560A"))
    o.append(dessert(4, 372, cy + 4, 70, -8))
    o.append(dessert(4, 566, cy + 4, 70, 8))
    o.append(dessert(5, 812, cy, 92, 6))
    for x, sym in [(469, "+"), (676, "=")]:
        o.append(text(sym, x, cy + 30, 84, "#FFFFFF", "Lilita One", 400, stroke=PLUM, sw=16))
    for x, y, s in [(925, 250, 20), (716, 238, 12), (916, 462, 13)]:
        o.append(star4(x, y, s, "#FFFFFF", "#E8427F"))
    o.append(logo(600, 124, 88, rot=-3, stacked=False))
    o.append(pill(600, 552, 610, 70, "Drop two. Bake something bigger.", 36))
    return "".join(o)


def option_4():
    """Wordmark card: the logo, huge, on the striped pink of the loading bar."""
    gid, pid = uid("pink"), uid("stripe")
    o = [f'<defs><linearGradient id="{gid}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#F7799F"/>'
         f'<stop offset="1" stop-color="{ACCENT}"/></linearGradient>'
         f'<pattern id="{pid}" width="56" height="56" patternUnits="userSpaceOnUse" patternTransform="rotate(-45)">'
         f'<rect width="56" height="28" fill="#FFFFFF" opacity="0.13"/></pattern></defs>'
         f'<rect width="{W}" height="{H}" fill="url(#{gid})"/><rect width="{W}" height="{H}" fill="url(#{pid})"/>']
    cols = ["#FFF6AE", "#8ED4F7", "#CBB5F7", "#FFFFFF", "#9BE28F", "#FFC83D"]
    pts = [(96, 92, 30), (204, 180, -50), (132, 330, 70), (236, 470, 15), (88, 520, -30), (330, 76, 60),
           (1104, 100, -25), (1010, 186, 40), (1092, 318, -70), (968, 452, 20), (1112, 528, 55), (880, 70, -40),
           (470, 566, 35), (752, 574, -20), (300, 572, -60), (560, 50, 12), (1040, 580, -8), (170, 590, 44)]
    o.append(sprinkles([(x, y, a, cols[n % len(cols)], 30 + (n % 3) * 6) for n, (x, y, a) in enumerate(pts)]))
    o.append(logo(600, 268, 150, rot=-4))
    o.append(dessert(5, 884, 440, 60, 12))
    o.append(dessert(4, 236, 452, 54, -10))
    o.append(pill(600, 546, 430, 64, "Play now in your browser", 31))
    return "".join(o)


def option_5():
    """The hook: a mystery top tier in silhouette. Can you bake it?"""
    gid, fid = uid("plum"), uid("sil")
    o = [f'<defs><radialGradient id="{gid}" cx="0.5" cy="0.6" r="0.75"><stop offset="0" stop-color="#A32560"/>'
         f'<stop offset="0.5" stop-color="{PLUM}"/><stop offset="1" stop-color="#3A061D"/></radialGradient>'
         f'<filter id="{fid}" x="-20%" y="-20%" width="140%" height="140%" color-interpolation-filters="sRGB">'
         f'<feColorMatrix type="matrix" values="0 0 0 0 0.19  0 0 0 0 0.03  0 0 0 0 0.11  0 0 0 12 -6" result="flat"/>'
         f'<feMorphology in="flat" operator="dilate" radius="1" result="fat"/>'
         f'<feFlood flood-color="#FFD76A"/><feComposite in2="fat" operator="in" result="rim"/>'
         f'<feGaussianBlur in="rim" stdDeviation="2.2" result="glow"/>'
         f'<feMerge><feMergeNode in="glow"/><feMergeNode in="rim"/><feMergeNode in="flat"/></feMerge></filter></defs>'
         f'<rect width="{W}" height="{H}" fill="url(#{gid})"/>']
    o.append(rays(600, 380, 16, 900, "#FFD76A", 0.09))
    base = 536
    o.append(ground_shadow(600, base - 2, 470, 26, 0.5, "#1E020E"))
    for i, x, r, rot in [(4, 172, 46, -4), (6, 318, 58, 0), (7, 886, 62, 0), (5, 1036, 50, 6)]:
        o.append(dessert_on(i, x, base + 4, r, rot))
    o.append(dessert_on(8, 600, base + 6, 128, 0, f'filter="url(#{fid})"'))
    o.append(text("?", 600, 470, 150, "#FFE9A6", "Lilita One", 400, stroke="#7C1440", sw=14))
    for x, y, s in [(432, 290, 14), (772, 262, 18), (790, 440, 10), (416, 452, 9)]:
        o.append(star4(x, y, s, "#FFE9A6"))
    o.append(text("Can you bake", 600, 92, 62, "#FFFFFF", "Lilita One", 400, stroke=PLUM_DK, sw=14))
    tg = uid("tg")
    o.append(f'<linearGradient id="{tg}" x1="0" y1="0" x2="0" y2="1"><stop offset="0.45" stop-color="#FFF6AE"/>'
             f'<stop offset="0.85" stop-color="#FFA83D"/></linearGradient>')
    o.append(text("the top tier?", 600, 178, 92, PLUM_DK, "Lilita One", 400, stroke=PLUM_DK, sw=22,
                  extra='transform="translate(0 7)"'))
    o.append(text("the top tier?", 600, 178, 92, f"url(#{tg})", "Lilita One", 400, stroke=PLUM_DK, sw=16))
    o.append(logo(600, 584, 40, rot=0, stacked=False, stars=False))
    return "".join(o)


OPTIONS = [
    ("Jar hero", option_1),
    ("Merge chain", option_2),
    ("Merge moment", option_3),
    ("Wordmark card", option_4),
    ("Top-tier hook", option_5),
]

# ---------- rendering ----------

PAGE = """<!DOCTYPE html><html><head><meta charset="utf-8"><style>
@font-face {{ font-family: 'Lilita One'; src: url('file://{fonts}/LilitaOne.ttf'); }}
@font-face {{ font-family: 'Fredoka'; src: url('file://{fonts}/Fredoka.ttf'); font-weight: 300 700; }}
html, body {{ margin: 0; padding: 0; background: {bg}; overflow: hidden; }}
svg {{ display: block; }}
{css}
</style></head><body>{body}</body></html>"""


def chrome():
    for c in CHROME_CANDIDATES:
        if c and os.path.exists(c):
            return c
    sys.exit("No Chrome/Chromium found; set CHROME=/path/to/chrome")


def shoot(html, png, w, h, tmp):
    page = os.path.join(tmp, os.path.basename(png) + ".html")
    with open(page, "w") as fh:
        fh.write(html)
    subprocess.run([chrome(), "--headless=new", "--disable-gpu", "--hide-scrollbars", "--no-first-run",
                    "--force-device-scale-factor=1", "--allow-file-access-from-files",
                    f"--user-data-dir={os.path.join(tmp, 'profile')}", f"--window-size={w},{h}",
                    "--virtual-time-budget=4000", f"--screenshot={png}", "file://" + page],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=120)
    if not os.path.exists(png):
        sys.exit(f"Chrome did not write {png}")


def png_size(path):
    with open(path, "rb") as fh:
        head = fh.read(24)
    return int.from_bytes(head[16:20], "big"), int.from_bytes(head[20:24], "big")


def main():
    args = [a for a in sys.argv[1:]]
    only = None
    if "--only" in args:
        k = args.index("--only")
        only = int(args[k + 1])
        del args[k:k + 2]
    out = args[0] if args else DEFAULT_OUT
    os.makedirs(out, exist_ok=True)
    tmp = tempfile.mkdtemp(prefix="gen_og_")
    try:
        for n, (name, fn) in enumerate(OPTIONS, 1):
            if only and n != only:
                continue
            svg = f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">{fn()}</svg>'
            png = os.path.join(out, f"option-{n}.png")
            shoot(PAGE.format(fonts=FONTS, bg=WALL, css="", body=svg), png, W, H, tmp)
            if png_size(png) != (W, H):
                sys.exit(f"{png} is {png_size(png)}, expected {(W, H)}")
            sq = os.path.join(out, f"option-{n}-square.png")
            # centre 630x630 of the frame, scaled to 600x600
            subprocess.run(["sips", "-c", str(H), str(H), png, "--out", sq], check=True, stdout=subprocess.DEVNULL)
            subprocess.run(["sips", "-z", "600", "600", sq], check=True, stdout=subprocess.DEVNULL)
            print(f"option-{n}.png  {name:14s} {os.path.getsize(png) / 1024:6.0f} KB   square {os.path.getsize(sq) / 1024:5.0f} KB")
        if not only:
            contact_sheet(out, tmp)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def contact_sheet(out, tmp):
    rows = []
    for n, (name, fn) in enumerate(OPTIONS, 1):
        src = "file://" + os.path.join(out, f"option-{n}.png")
        sq = "file://" + os.path.join(out, f"option-{n}-square.png")
        rows.append(f'<div class="row"><div class="num">{n}</div>'
                    f'<div class="cell"><img src="{src}" width="800" height="420"><span>{name} &middot; 1200&times;630</span></div>'
                    f'<div class="cell"><img src="{sq}" width="420" height="420"><span>square crop</span></div>'
                    f'<div class="cell"><img src="{src}" width="300" height="158"><span>300 px thumbnail</span></div></div>')
    css = """
body { font-family: 'Fredoka'; font-weight: 600; color: #4A2618; padding: 36px 40px; box-sizing: border-box; }
.row { display: flex; align-items: flex-start; gap: 28px; margin-bottom: 30px; }
.num { font-family: 'Lilita One'; font-size: 76px; width: 80px; height: 80px; line-height: 80px; text-align: center;
  color: #fff; background: #E8427F; border-radius: 50%; box-shadow: 0 6px 0 #A81F58; flex: none; }
.cell { display: flex; flex-direction: column; gap: 8px; font-size: 20px; color: #7A5648; }
img { display: block; border-radius: 12px; box-shadow: 0 6px 18px rgba(51, 20, 10, 0.25); }
"""
    sheet_w, sheet_h = 40 * 2 + 80 + 800 + 420 + 300 + 28 * 3, 36 * 2 + len(OPTIONS) * (420 + 36 + 30)
    png = os.path.join(out, "contact-sheet.png")
    shoot(PAGE.format(fonts=FONTS, bg="#FFF9F2", css=css, body="".join(rows)), png, sheet_w, sheet_h, tmp)
    print(f"contact-sheet.png {png_size(png)} {os.path.getsize(png) / 1024:.0f} KB")


if __name__ == "__main__":
    main()
