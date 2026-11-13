#!/usr/bin/env python3
"""Generates every SVG in assets/art/. Run: python3 tools/gen_art.py

Desserts are drawn in design units where the base radius r = 30, centred on the
physics body. Godot rasterises these with ThorVG, so: no filters, patterns, text
or CSS. Soft shadows are radial gradients that fade to transparent.
"""
import math, os, random

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "art")
TAU = math.tau


def f(v):
    s = f"{v:.2f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


class SVG:
    def __init__(self, vb):
        self.vb = vb
        self.defs = []
        self.body = []
        self.n = 0

    def uid(self, p="g"):
        self.n += 1
        return f"{p}{self.n}"

    def _stops(self, stops):
        out = []
        for o, c in stops:
            col, op = c if isinstance(c, tuple) else (c, 1)
            out.append(f'<stop offset="{f(o)}" stop-color="{col}" stop-opacity="{f(op)}"/>')
        return "".join(out)

    def lg(self, x1, y1, x2, y2, stops):
        i = self.uid("l")
        self.defs.append(f'<linearGradient id="{i}" gradientUnits="userSpaceOnUse" x1="{f(x1)}" y1="{f(y1)}" x2="{f(x2)}" y2="{f(y2)}">{self._stops(stops)}</linearGradient>')
        return f"url(#{i})"

    def rg(self, cx, cy, r, stops, fx=None, fy=None):
        i = self.uid("r")
        fxy = f' fx="{f(fx)}" fy="{f(fy)}"' if fx is not None else ""
        self.defs.append(f'<radialGradient id="{i}" gradientUnits="userSpaceOnUse" cx="{f(cx)}" cy="{f(cy)}" r="{f(r)}"{fxy}>{self._stops(stops)}</radialGradient>')
        return f"url(#{i})"

    def clip(self, d):
        i = self.uid("c")
        self.defs.append(f'<clipPath id="{i}"><path d="{d}"/></clipPath>')
        return i

    def add(self, s):
        self.body.append(s)

    def path(self, d, fill="none", stroke=None, w=None, op=None, extra=""):
        a = f'<path d="{d}" fill="{fill}"'
        if stroke:
            a += f' stroke="{stroke}" stroke-width="{f(w)}" stroke-linejoin="round" stroke-linecap="round"'
        if op is not None:
            a += f' opacity="{f(op)}"'
        self.add(a + f"{extra}/>")

    def group(self, inner_fn, clip=None, transform=None, op=None):
        attrs = ""
        if clip:
            attrs += f' clip-path="url(#{clip})"'
        if transform:
            attrs += f' transform="{transform}"'
        if op is not None:
            attrs += f' opacity="{f(op)}"'
        self.add(f"<g{attrs}>")
        inner_fn()
        self.add("</g>")

    def save(self, name):
        x, y, w, h = self.vb
        s = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{f(x)} {f(y)} {f(w)} {f(h)}" width="{f(w)}" height="{f(h)}">'
             f'<defs>{"".join(self.defs)}</defs>{"".join(self.body)}</svg>\n')
        with open(os.path.join(OUT, name), "w") as fh:
            fh.write(s)


# ---------- path helpers ----------
def circ(cx, cy, r):
    return f"M{f(cx-r)} {f(cy)}A{f(r)} {f(r)} 0 1 0 {f(cx+r)} {f(cy)}A{f(r)} {f(r)} 0 1 0 {f(cx-r)} {f(cy)}Z"


def ell(cx, cy, rx, ry, rot=0.0):
    pts = []
    for i in range(48):
        a = i / 48 * TAU
        x, y = math.cos(a) * rx, math.sin(a) * ry
        c, s = math.cos(rot), math.sin(rot)
        pts.append((cx + x * c - y * s, cy + x * s + y * c))
    return poly(pts)


def poly(pts, close=True):
    d = "M" + "L".join(f"{f(x)} {f(y)}" for x, y in pts)
    return d + ("Z" if close else "")


def arc(cx, cy, r, a0, a1, rx=None):
    """Open arc as a polyline, angles in radians, canvas convention (y down)."""
    rx = rx or r
    n = max(6, int(abs(a1 - a0) / TAU * 64))
    return poly([(cx + math.cos(a0 + (a1 - a0) * i / n) * rx, cy + math.sin(a0 + (a1 - a0) * i / n) * r) for i in range(n + 1)], close=False)


def rrect(x, y, w, h, r):
    r = min(r, w / 2, h / 2)
    return (f"M{f(x+r)} {f(y)}H{f(x+w-r)}A{f(r)} {f(r)} 0 0 1 {f(x+w)} {f(y+r)}V{f(y+h-r)}"
            f"A{f(r)} {f(r)} 0 0 1 {f(x+w-r)} {f(y+h)}H{f(x+r)}A{f(r)} {f(r)} 0 0 1 {f(x)} {f(y+h-r)}"
            f"V{f(y+r)}A{f(r)} {f(r)} 0 0 1 {f(x+r)} {f(y)}Z")


def blob(r, offs, x0=0, y0=0, n_pts=96):
    n = len(offs)
    pts = []
    for i in range(n_pts):
        a = i / n_pts * TAU
        fr = i / n_pts * n
        i0 = int(math.floor(fr)) % n
        i1 = (i0 + 1) % n
        t = fr - math.floor(fr)
        s = (1 - math.cos(t * math.pi)) / 2
        rad = r * (offs[i0] * (1 - s) + offs[i1] * s)
        pts.append((x0 + math.cos(a) * rad, y0 + math.sin(a) * rad))
    return poly(pts)


def offs(R, n, amp):
    return [1 + (R.random() * 2 - 1) * amp for _ in range(n)]


def star4(x, y, s):
    return (f"M{f(x)} {f(y-s)}Q{f(x)} {f(y)} {f(x+s)} {f(y)}Q{f(x)} {f(y)} {f(x)} {f(y+s)}"
            f"Q{f(x)} {f(y)} {f(x-s)} {f(y)}Q{f(x)} {f(y)} {f(x)} {f(y-s)}Z")


# ---------- shared drawing ----------
def shadow(g, cx, cy, rx, ry, a=0.28):
    g.path(ell(cx, cy, rx, ry), fill=g.rg(cx, cy, rx, [(0, ("#3A1420", a)), (0.6, ("#3A1420", a * 0.55)), (1, ("#3A1420", 0))]),
           extra=f' transform="translate({f(cx)} {f(cy)}) scale(1 {f(ry/rx)}) translate({f(-cx)} {f(-cy)})"')


def soft_shadow(g, cx, cy, rx, ry, a=0.28):
    """Contact shadow: radial ellipse fading out (circle gradient squashed by transform)."""
    g.add(f'<g transform="translate({f(cx)} {f(cy)}) scale(1 {f(ry/rx)})">')
    g.path(circ(0, 0, rx), fill=g.rg(0, 0, rx, [(0, ("#2A0E18", a)), (0.55, ("#2A0E18", a * 0.5)), (1, ("#2A0E18", 0))]))
    g.add("</g>")


def gloss(g, x, y, rx, ry, rot=0.0, a=0.8):
    g.path(ell(x, y, rx, ry, rot), fill="#FFFFFF", op=a)


def shade(g, cx, cy, r, dark, light=("#FFFFFF", 0.28)):
    """Lit-from-upper-left overlay for a clipped region."""
    g.path(rrect(cx - r * 2, cy - r * 2, r * 4, r * 4, 0),
           fill=g.rg(cx, cy, r * 1.25, [(0, light), (0.45, ("#FFFFFF", 0)), (0.72, ("#000000", 0)), (1, dark)],
                     fx=cx - r * 0.45, fy=cy - r * 0.55))


def mix(c1, c2, t):
    a = [int(c1[i:i + 2], 16) for i in (1, 3, 5)]
    b = [int(c2[i:i + 2], 16) for i in (1, 3, 5)]
    return "#" + "".join(f"{round(a[i] + (b[i] - a[i]) * t):02X}" for i in range(3))


FACES = {  # mood -> (left eye, right eye, mouth)
    "smile": ("round", "round", "smile"), "open": ("round", "round", "open"), "cat": ("round", "round", "cat"),
    "wow": ("round", "round", "o"), "lash": ("lash", "lash", "smile"), "happy": ("up", "up", "smile"),
    "grin": ("up", "up", "open"), "sleepy": ("down", "down", "tiny"), "wink": ("round", "up", "tongue"),
    "none": ("round", "round", None), "winknone": ("round", "up", None),
}


def face(g, x, y, s, mood, col="#4A2618", ex=7.8):
    """Kawaii face. Eyes sit at (x +- ex*s, y); the mouth hangs just below."""
    ex *= s
    er = 3.15 * s
    le, re_, mouth = FACES[mood]
    iris = mix(col, "#FFB0C8", 0.45)
    for d in (-1, 1):
        bx, by = x + d * (ex + 4.3 * s), y + 4.4 * s
        g.add(f'<g transform="translate({f(bx)} {f(by)}) scale(1 0.62)">')
        g.path(circ(0, 0, 4.3 * s), fill=g.rg(0, 0, 4.3 * s, [(0, ("#FF4F80", 0.72)), (0.6, ("#FF6F95", 0.4)), (1, ("#FF6F95", 0))]))
        g.add("</g>")
    for d, kind in ((-1, le), (1, re_)):
        cx = x + d * ex
        if kind == "up":
            g.path(arc(cx, y + 1.7 * s, er * 1.02, math.pi * 1.1, math.pi * 1.9), stroke=col, w=2.2 * s)
        elif kind == "down":
            g.path(arc(cx, y - 1.0 * s, er * 0.98, math.pi * 0.1, math.pi * 0.9), stroke=col, w=2.1 * s)
            for k in (0.25, 0.75):
                a = math.pi * (0.1 + 0.8 * k)
                px, py = cx + math.cos(a) * er, y - 1.0 * s + math.sin(a) * er
                g.path(f"M{f(px)} {f(py)}L{f(px + (k - 0.5) * 1.6 * s)} {f(py + 1.5 * s)}", stroke=col, w=1.1 * s)
        else:
            g.path(ell(cx, y, er, er * 1.16), fill=g.rg(cx, y + er * 0.75, er * 1.5, [(0, iris), (0.5, col), (1, col)]))
            g.path(circ(cx - er * 0.3, y - er * 0.42, er * 0.5), fill="#FFFFFF")
            g.path(circ(cx + er * 0.38, y + er * 0.5, er * 0.23), fill="#FFFFFF", op=0.9)
            if kind == "lash":
                for a in (-0.35, 0.2):
                    px, py = cx + d * er * math.cos(a), y + er * 1.16 * math.sin(a) - er * 0.5
                    g.path(f"M{f(px)} {f(py)}L{f(px + d * 2.1 * s)} {f(py - 1.3 * s)}", stroke=col, w=1.2 * s)
    my = y + 3.3 * s
    if mouth == "open":
        g.path(arc(x, my, 3.3 * s, 0, math.pi) + "Z", fill="#8E2B3A", stroke=col, w=1.6 * s)
        g.path(ell(x, my + 2.1 * s, 1.8 * s, 0.95 * s), fill="#FF8FA3")
    elif mouth == "cat":
        g.path(arc(x - 1.9 * s, my, 1.9 * s, 0, math.pi), stroke=col, w=1.7 * s)
        g.path(arc(x + 1.9 * s, my, 1.9 * s, 0, math.pi), stroke=col, w=1.7 * s)
    elif mouth == "o":
        g.path(ell(x, my + 1.3 * s, 1.7 * s, 2.0 * s), fill="#8E2B3A", stroke=col, w=1.4 * s)
    elif mouth == "tiny":
        g.path(arc(x, my - 0.4 * s, 2.0 * s, math.pi * 0.15, math.pi * 0.85), stroke=col, w=1.6 * s)
    elif mouth == "tongue":
        g.path(arc(x, my - 1.0 * s, 3.1 * s, math.pi * 0.12, math.pi * 0.88), stroke=col, w=1.8 * s)
        g.path(ell(x + 1.5 * s, my + 2.3 * s, 1.5 * s, 1.25 * s), fill="#FF7F9E", stroke=col, w=1.0 * s)
    elif mouth == "smile":
        g.path(arc(x, my - 1.0 * s, 3.0 * s, math.pi * 0.13, math.pi * 0.87), stroke=col, w=1.9 * s)


def sprinkle_bit(g, x, y, ang, col, L=4.6, T=1.7, edge=True):
    d = rrect(-L / 2, -T / 2, L, T, T / 2)
    g.add(f'<g transform="translate({f(x)} {f(y)}) rotate({f(math.degrees(ang))})">')
    g.path(d, fill=col, stroke=("#000000" if edge else None), w=0.5, extra=' stroke-opacity="0.18"' if edge else "")
    g.path(rrect(-L / 2 + 0.6, -T / 2 + 0.25, L - 1.6, T * 0.32, T * 0.16), fill="#FFFFFF", op=0.55)
    g.add("</g>")


def dessert_svg(W, H):
    return SVG((-(W / 2 + 10), -(H / 2 + 10), W + 20, H + 20))


# ---------- desserts ----------
def d0_sprinkle():
    W, H = 78, 33
    g = dessert_svg(W, H)
    soft_shadow(g, 0, H / 2 - 0.5, W * 0.42, 4.2, 0.24)
    body = rrect(-39, -16.5, 78, 33, 16.5)
    g.path(body, fill=g.lg(0, -16.5, 0, 16.5, [(0, "#FFC9DB"), (0.4, "#FF7FAA"), (1, "#E33D7A")]))
    c = g.clip(body)

    def inner():
        for x in range(-70, 50, 16):
            g.path(poly([(x, 18), (x + 7, 18), (x + 22, -18), (x + 15, -18)]), fill="#FFFFFF", op=0.16)
        g.path(rrect(-40, 2, 80, 16, 0), fill=g.lg(0, 2, 0, 17, [(0, ("#9A0F4E", 0)), (1, ("#9A0F4E", 0.42))]))
        # rim light along bottom
        g.path(arc(0, -2, 15.5, math.pi * 0.2, math.pi * 0.8, rx=37), stroke="#FFD6E4", w=1.6, op=0.6)
        # sugar sparkle
        R = random.Random(3)
        for _ in range(14):
            g.path(circ(-34 + R.random() * 68, -12 + R.random() * 22, 0.45 + R.random() * 0.5), fill="#FFFFFF", op=0.55)
    g.group(inner, clip=c)
    g.path(rrect(-30, -12.6, 40, 5.6, 2.8), fill="#FFFFFF", op=0.78)
    gloss(g, 17, -9.6, 2.8, 2.2, 0, 0.8)
    g.path(body, stroke="#AD1B5A", w=2.4)
    face(g, 0, -1.6, 1.0, "smile", "#6E0F38")
    g.path(star4(-26, 6, 3.2), fill="#FFFFFF", op=0.9)
    g.save("d0_sprinkle.svg")


def d1_chip():
    g = dessert_svg(60, 60)
    soft_shadow(g, 0, 27, 24, 4, 0.26)
    p = "M1 -28C5 -15 27 -5 27 12C27 24 13 27.5 0 27.5C-13 27.5 -27 24 -27 12C-27 -4 -6 -12 -3 -22C-2.4 -25 -1 -27 1 -28Z"
    g.path(p, fill=g.rg(0, 7, 34, [(0, "#C9895A"), (0.45, "#8E522B"), (1, "#4E240E")], fx=-10, fy=-2))
    c = g.clip(p)

    def inner():
        g.path(rrect(-30, 0, 60, 30, 0), fill=g.rg(14, 25, 20, [(0, ("#FFB070", 0.42)), (1, ("#FFB070", 0))]))
        g.path(rrect(-30, 14, 60, 16, 0), fill=g.lg(0, 14, 0, 28, [(0, ("#280C00", 0)), (1, ("#280C00", 0.38))]))
        # chocolate ridges (conching swirl)
        for i, (y, a) in enumerate([(-6, 0.22), (2, 0.18), (10, 0.14)]):
            g.path(f"M{-22+i*2} {y+6}Q0 {y-2} {22-i*2} {y+5}", stroke="#3A1806", w=1.2, op=a)
        R = random.Random(7)
        for _ in range(16):
            g.path(circ(-20 + R.random() * 40, -2 + R.random() * 26, 0.35 + R.random() * 0.5), fill="#E9B98C", op=0.35)
    g.group(inner, clip=c)
    g.path("M-4 -17C-9 -7 -21 -3 -20.5 9", stroke="#FFECD7", w=3.6, op=0.82)
    g.path("M2.5 -21C4.5 -16 7 -13 9 -11", stroke="#FFECD7", w=1.8, op=0.6)
    gloss(g, -17, 15.5, 2.4, 1.8, 0, 0.55)
    g.path(p, stroke="#3A1806", w=2.4)
    face(g, 0, 9.5, 1.0, "wow", "#2A0F03")
    g.save("d1_chip.svg")


def d2_cookie():
    g = dessert_svg(60, 60)
    R = random.Random(11)
    soft_shadow(g, 0, 27.5, 25, 4, 0.26)
    o = offs(R, 12, 0.03)
    b = blob(28.6, o)
    g.path(b, fill=g.rg(0, 0, 31, [(0, "#FCE2AA"), (0.55, "#EBB467"), (0.9, "#CF8C3C"), (1, "#B97226")], fx=-8, fy=-10))
    c = g.clip(b)

    def inner():
        shade(g, 0, 0, 29, ("#6E3504", 0.42))
        for _ in range(40):
            a, d = R.random() * TAU, math.sqrt(R.random()) * 25
            g.path(circ(math.cos(a) * d, math.sin(a) * d, 0.5 + R.random() * 0.8), fill="#FFF0CC", op=0.5)
        for _ in range(26):
            a, d = R.random() * TAU, math.sqrt(R.random()) * 25
            g.path(circ(math.cos(a) * d, math.sin(a) * d, 0.4 + R.random() * 0.7), fill="#8C4E16", op=0.32)
        # toasted rim
        g.path(circ(0, 0, 27.4), stroke="#A8641F", w=3, op=0.35)
    g.group(inner, clip=c)
    for a, b2, d, e, f2, gg in [(-13, -4, -9, -9, -4, -10), (10, -13, 14, -9, 13, -4), (-3, 15, 2, 17, 6, 14), (-20, 12, -17, 14, -15, 11)]:
        g.path(f"M{a} {b2}Q{d} {e} {f2} {gg}", stroke="#96581C", w=1.3, op=0.5)
        g.path(f"M{a} {b2+0.9}Q{d} {e+0.9} {f2} {gg+0.9}", stroke="#FFF2D2", w=0.8, op=0.45)
    for x, y, s in [(-15, -15, 5.4), (3, -20.5, 4.4), (18, -10, 5), (-21.5, 3, 4), (20.5, 9.5, 4.5), (-10, 19, 4.8), (9, 20, 4)]:
        cb = blob(s, offs(R, 5, 0.2), x, y, 40)
        soft_shadow(g, x + 0.6, y + s * 0.6, s * 1.05, s * 0.45, 0.22)
        g.path(cb, fill=g.rg(x, y, s * 1.15, [(0, "#9A5C34"), (0.6, "#5A2A12"), (1, "#3A1608")], fx=x - s * 0.35, fy=y - s * 0.4), stroke="#2D1004", w=1.1)
        gloss(g, x - s * 0.3, y - s * 0.38, s * 0.38, s * 0.2, -0.5, 0.55)
    g.path(b, stroke="#8C4E1A", w=2.4)
    face(g, 0, 2, 1.0, "open")
    g.save("d2_cookie.svg")


def d3_macaron():
    g = dessert_svg(63, 45)
    soft_shadow(g, 0, 21.5, 26, 3.6, 0.26)
    top = "M-30 -4C-32.5 -27 32.5 -27 30 -4Z"
    bot = "M-30 5C-31.5 26.5 31.5 26.5 30 5Z"
    g.path(bot, fill=g.lg(0, 5, 0, 22, [(0, "#C2ACF4"), (1, "#8466D2")]))
    cb = g.clip(bot)
    g.group(lambda: g.path(ell(-6, 11, 18, 4), fill="#FFFFFF", op=0.18), clip=cb)
    g.path(bot, stroke="#6748BE", w=2.2)
    # cream filling
    cream = rrect(-27.5, -6.8, 55, 14, 7)
    g.path(cream, fill=g.lg(0, -6.5, 0, 7, [(0, "#FFFEF6"), (0.6, "#FBEBCB"), (1, "#EFD3A1")]), stroke="#C79A5E", w=1.5)
    for x in range(-24, 26, 6):
        g.path(ell(x + 2, 4.6, 2.6, 1.1), fill="#E3BE85", op=0.5)
    g.path(rrect(-22, -3.8, 30, 2.6, 1.3), fill="#FFFFFF", op=0.9)
    # top shell
    g.path(top, fill=g.rg(0, -8, 36, [(0, "#F3EBFF"), (0.5, "#CDB8F8"), (1, "#9E7EE2")], fx=-10, fy=-18))
    ct = g.clip(top)

    def inner():
        g.path(rrect(-32, -12, 64, 9, 0), fill=g.lg(0, -12, 0, -3, [(0, ("#5A32AA", 0)), (1, ("#5A32AA", 0.24))]))
        R = random.Random(5)
        for _ in range(18):
            g.path(circ(-24 + R.random() * 48, -19 + R.random() * 12, 0.35 + R.random() * 0.4), fill="#8E6BD6", op=0.3)
    g.group(inner, clip=ct)
    # ruffled feet
    for i in range(13):
        x = -27 + i * 4.5
        g.path(circ(x, -4.6, 2.75), fill="#B79DF0", stroke="#6748BE", w=0.9, extra=' stroke-opacity="0.55"')
        g.path(circ(x - 0.7, -5.4, 0.9), fill="#FFFFFF", op=0.45)
        g.path(circ(x, 5.6, 2.75), fill="#A98EEA", stroke="#6748BE", w=0.9, extra=' stroke-opacity="0.55"')
    gloss(g, -10, -17.2, 11, 2.6, -0.1, 0.7)
    gloss(g, 9, -18.4, 2.4, 1.3, 0, 0.6)
    g.path(top, stroke="#6748BE", w=2.2)
    face(g, 0, -13.4, 0.84, "sleepy", "#3F2685")
    g.save("d3_macaron.svg")


def d4_cupcake():
    g = dessert_svg(49.5, 58.5)
    soft_shadow(g, 0, 28.3, 18, 3.4, 0.28)
    liner = "M-20.5 3L20.5 3L16.6 25Q16 28.6 12.5 28.6L-12.5 28.6Q-16 28.6 -16.6 25Z"
    g.path(liner, fill=g.lg(-21, 0, 21, 0, [(0, "#A6E2FC"), (0.45, "#5CB9EE"), (1, "#2C82C8")]))
    c = g.clip(liner)

    def inner():
        for i in range(-5, 6):
            xt, xb = i * 4.1, i * 3.3
            g.path(f"M{f(xt)} 3L{f(xb)} 29", stroke="#14558F", w=1.6, op=0.3)
            g.path(f"M{f(xt+1.5)} 3L{f(xb+1.2)} 29", stroke="#FFFFFF", w=1.1, op=0.42)
        g.path(rrect(-22, 3, 44, 8, 0), fill=g.lg(0, 3, 0, 11, [(0, ("#0F3C78", 0.4)), (1, ("#0F3C78", 0))]))
        g.path(rrect(-22, 21, 44, 9, 0), fill=g.lg(0, 21, 0, 29, [(0, ("#0F3C78", 0)), (1, ("#0F3C78", 0.25))]))
    g.group(inner, clip=c)
    g.path(liner, stroke="#1F68AC", w=2.2)

    def puffy(x, y, rx, ry):
        soft_shadow(g, x, y + ry * 0.7, rx * 0.95, ry * 0.5, 0.2)
        g.path(ell(x, y, rx, ry), fill=g.rg(x, y, rx * 1.05, [(0, "#FFFFFF"), (0.55, "#FFE6EF"), (1, "#F2A6BF")], fx=x - rx * 0.4, fy=y - ry * 0.55), stroke="#D56F96", w=1.8)
        g.path(arc(x + rx * 0.05, y + ry * 0.2, ry * 0.5, math.pi * 0.12, math.pi * 0.8, rx=rx * 0.72), stroke="#E28CAA", w=1.2, op=0.6)
        gloss(g, x - rx * 0.45, y - ry * 0.42, rx * 0.24, ry * 0.2, -0.4, 0.92)
    puffy(0, -0.5, 23.8, 8.6)
    puffy(0, -10, 17.6, 7.8)
    puffy(0.5, -18.6, 10.6, 6.3)
    cols = ["#FF5C8A", "#3FB6E8", "#FFD23F", "#7ED957", "#B57BFF"]
    for i, (x, y, a) in enumerate([(-15, -1, .4), (-6, 2, -.5), (6, 1.5, .9), (15, -2, -.3), (-9, -10, .8), (2, -8.5, -.9), (10, -11, .3), (-3, -18, .5), (5, -19.5, -.6), (-18, 2.5, 1.2), (19, 1.5, .2)]):
        sprinkle_bit(g, x, y, a, cols[i % 5], 4.2, 1.6)
    # cherry
    g.path("M2.5 -27Q3.5 -31.5 8 -33", stroke="#3E7A2A", w=1.6)
    g.path(ell(9.5, -33, 2.6, 1.2, -0.4), fill="#6FBF4A", stroke="#3E7A2A", w=0.8)
    g.path(circ(1.6, -25.6, 4.6), fill=g.rg(1.6, -25.6, 5, [(0, "#FF9A9A"), (0.55, "#E12643"), (1, "#9A0C26")], fx=0, fy=-27.2), stroke="#8A0B22", w=1.5)
    gloss(g, 0.1, -27.3, 1.4, 0.95, -0.5, 0.95)
    face(g, 0, 14.5, 0.92, "grin", "#12406E")
    g.save("d4_cupcake.svg")


def d5_donut():
    g = dessert_svg(60, 60)
    R = random.Random(17)
    soft_shadow(g, 0, 27.5, 25, 4, 0.26)
    od, og = offs(R, 10, 0.018), offs(R, 12, 0.065)
    hole = circ(0, 0, 7.6)
    dough = blob(28.6, od)
    ring = dough + hole
    g.path(ring, fill=g.rg(0, 0, 31, [(0, "#FFE3B2"), (0.6, "#EBB26A"), (1, "#BF7C34")], fx=-9, fy=-10), extra=' fill-rule="evenodd"')
    c = g.clip(dough)
    g.group(lambda: shade(g, 0, 0, 29, ("#7D3E0A", 0.4), ("#FFFFFF", 0.1)), clip=c)
    glaze = blob(23.6, og) + circ(0, 0, 11)
    g.path(glaze, fill=g.rg(0, 0, 26, [(0, "#FFD8E6"), (0.5, "#FF8FB6"), (1, "#E6508D")], fx=-8, fy=-9), extra=' fill-rule="evenodd"')
    g.path(glaze, fill=g.rg(9, 12, 22, [(0, ("#BE1E64", 0.3)), (1, ("#BE1E64", 0))]), extra=' fill-rule="evenodd"')
    g.path(glaze, stroke="#C4367A", w=1.6)
    cols = ["#FFFFFF", "#3FB6E8", "#FFD23F", "#7ED957", "#B57BFF", "#FFF3A8"]
    n = tries = 0
    while n < 22 and tries < 300:
        tries += 1
        a, d = R.random() * TAU, 13.5 + R.random() * 7.8
        x, y = math.cos(a) * d, math.sin(a) * d
        if math.hypot(abs(x) - 16.5, y + 2) < 5.8 or math.hypot(abs(x) - 19.6, y - 1.4) < 4.2 or math.hypot(x, y - 15.5) < 5:
            continue
        sprinkle_bit(g, x, y, R.random() * math.pi, cols[n % 6], 5, 1.8)
        n += 1
    g.path(arc(0, 0, 18.6, math.pi * 1.12, math.pi * 1.42), stroke="#FFFFFF", w=2.8, op=0.85)
    g.path(arc(0, 0, 18.6, math.pi * 1.47, math.pi * 1.53), stroke="#FFFFFF", w=2.8, op=0.85)
    g.path(hole, stroke="#97571E", w=2)
    g.path(arc(0, 0.6, 6.6, math.pi * 1.05, math.pi * 1.95), stroke="#6E370C", w=1.6, op=0.45)
    g.path(dough, stroke="#97571E", w=2.4)
    face(g, 0, -2, 0.88, "winknone", "#5A1238", 18.5)
    g.path(arc(0, 13.6, 3, math.pi * 0.12, math.pi * 0.88), stroke="#5A1238", w=1.7)
    g.path(ell(1.4, 17.2, 1.4, 1.2), fill="#FF7F9E", stroke="#5A1238", w=0.9)
    g.save("d5_donut.svg")


def d6_pie():
    g = dessert_svg(60, 60)
    R = random.Random(23)
    soft_shadow(g, 0, 27.5, 25, 4, 0.26)
    g.path(circ(0, 0, 27), fill="#D99C50")
    for i in range(20):
        a = i / 20 * TAU
        x, y = math.cos(a) * 25, math.sin(a) * 25
        g.path(circ(x, y, 4.6), fill=g.rg(x, y, 4.9, [(0, "#FFE8B6"), (0.6, "#EBB769"), (1, "#C4853A")], fx=x - 1.5, fy=y - 1.8), stroke="#8E5220", w=1.7)
    for i in range(20):
        a = i / 20 * TAU
        x, y = math.cos(a) * 25, math.sin(a) * 25
        g.path(circ(x - 1.3, y - 1.5, 0.9), fill="#FFFFFF", op=0.45)
    g.path(circ(0, 0, 22.6), fill=g.rg(0, 0, 23, [(0, "#F04560"), (0.7, "#B8152F"), (1, "#7A0A20")], fx=-6, fy=-6), stroke="#6E0A1E", w=1.3)
    for i in range(14):
        a = i / 14 * TAU + 0.2
        gloss(g, math.cos(a) * 21.2, math.sin(a) * 21.2, 1.6, 0.9, a, 0.55)
    oc = offs(R, 14, 0.022)
    top = blob(20.2, oc)
    soft_shadow(g, 0.8, 2, 21, 20, 0.22)
    g.path(top, fill=g.rg(0, 0, 22, [(0, "#FFF0C8"), (0.6, "#F0C073"), (1, "#CF9440")], fx=-7, fy=-8))
    c = g.clip(top)

    def inner():
        shade(g, 0, 0, 20.5, ("#8C4B0F", 0.38))
        for _ in range(26):
            a, d = R.random() * TAU, math.sqrt(R.random()) * 18
            g.path(circ(math.cos(a) * d, math.sin(a) * d, 0.35 + R.random() * 0.5), fill="#FFFFFF", op=0.85)
    g.group(inner, clip=c)
    g.path(top, stroke="#9A5A22", w=1.9)
    for k in range(5):
        a = -math.pi / 2 + k * TAU / 5
        tx, ty = math.cos(a) * 14.4, math.sin(a) * 14.4
        g.add(f'<g transform="translate({f(tx)} {f(ty)}) rotate({f(math.degrees(a + math.pi/2))})">')
        g.path("M0 -4.4C2.6 -1 2.2 3.6 0 3.8C-2.2 3.6 -2.6 -1 0 -4.4Z", fill="#A3122C", stroke="#8E5220", w=1.2)
        gloss(g, -0.5, 1, 0.6, 1, 0, 0.5)
        g.add("</g>")
    gloss(g, -9, -10.5, 5.6, 2.4, -0.7, 0.5)
    face(g, 0, 1, 0.95, "cat")
    g.save("d6_pie.svg")


def berry(g, x, y, s):
    g.add(f'<g transform="translate({f(x)} {f(y)}) scale({f(s)})">')
    p = "M0 7C-6.6 3 -6 -4.6 0 -4.6C6 -4.6 6.6 3 0 7Z"
    g.path(p, fill=g.rg(0, 0, 7.5, [(0, "#FF9090"), (0.55, "#E5283F"), (1, "#A40F28")], fx=-2, fy=-1.5), stroke="#8A0B22", w=1.4)
    for a, b in [(-2.6, -0.5), (2.4, -0.8), (0, 2), (-1.6, 3.8), (2, 3.4), (0, -2.4)]:
        g.path(ell(a, b, 0.5, 0.78), fill="#FFE9A6")
    g.path("M-4.6 -4.2L-1.6 -5.4L0 -7.6L1.6 -5.4L4.6 -4.2L1.8 -3.3L0 -2.4L-1.8 -3.3Z", fill="#5DB043", stroke="#2F6E22", w=1)
    gloss(g, -2.4, -1.6, 1.2, 0.8, -0.5, 0.75)
    g.add("</g>")


def d7_cake():
    g = dessert_svg(63, 45)
    soft_shadow(g, 0, 22.3, 29, 3.2, 0.28)
    board = rrect(-31.5, 17.8, 63, 4.7, 2.3)
    g.path(board, fill=g.lg(0, 18, 0, 22.5, [(0, "#FFF0B0"), (0.5, "#EBC055"), (1, "#C88F22")]), stroke="#A06F18", w=1.4)
    body = rrect(-28, -9.5, 56, 28, 5.5)
    g.path(body, fill=g.lg(-28, 0, 28, 0, [(0, "#C2814F"), (0.5, "#96572F"), (1, "#6A3517")]))
    c = g.clip(body)

    def inner():
        g.path(rrect(-30, 7, 60, 13, 0), fill=g.lg(0, 7, 0, 19, [(0, ("#32120", 0)) if False else (0, ("#321202", 0)), (1, ("#321202", 0.4))]))
        g.path(rrect(-30, 9.6, 60, 3.2, 0), fill="#FFDDE7")
        g.path(rrect(-30, 9.6, 60, 1, 0), fill="#FFFFFF", op=0.6)
        for x in range(-26, 27, 5):
            g.path(circ(x + 0.4, 11.2, 1.1), fill="#E5283F", op=0.85)
        R = random.Random(29)
        for _ in range(22):
            g.path(circ(-26 + R.random() * 52, -4 + R.random() * 20, 0.35 + R.random() * 0.45), fill="#3A1808", op=0.35)
    g.group(inner, clip=c)
    gloss(g, -23, 6, 1.7, 7, 0, 0.22)
    g.path(body, stroke="#4E2610", w=2.3)
    drips = [5, 2.5, 7, 3.5, 6, 2, 4.5, 7.5, 3, 5.5]
    d = "M-29.5 -6L-29.5 -10Q-29.5 -13.5 -26 -13.5L26 -13.5Q29.5 -13.5 29.5 -10L29.5 -6"
    for i in range(10):
        x1 = 29.5 - i * 5.9
        l = drips[i]
        d += f"L{f(x1)} {f(-6+l-2.4)}A2.4 2.4 0 0 1 {f(x1-4.8)} {f(-6+l-2.4)}L{f(x1-4.8)} -5A0.55 0.55 0 0 0 {f(x1-5.9)} -5"
    d += "Z"
    soft_shadow(g, 0, -3.5, 28, 4, 0.18)
    g.path(d, fill=g.lg(0, -13, 0, 3, [(0, "#FFFFFF"), (1, "#FFE6EE")]), stroke="#D98AA6", w=1.6)
    g.path(rrect(-24, -11.8, 26, 2.2, 1.1), fill="#FFFFFF")
    for x in [-21.5, -7.2, 7.2, 21.5]:
        g.path(circ(x, -15.6, 4.3), fill=g.rg(x, -15.6, 4.5, [(0, "#FFFFFF"), (1, "#FFD6E2")], fx=x - 1.4, fy=-17.2), stroke="#D98AA6", w=1.2)
        g.path(arc(x, -15.6, 2.1, math.pi * 0.2, math.pi * 1.5), stroke="#D98AA6", w=0.9, op=0.7)
    berry(g, -14.3, -17.2, 0.88)
    berry(g, 0, -18.4, 0.98)
    berry(g, 14.3, -17.2, 0.88)
    face(g, 0, 1.2, 0.95, "happy", "#3A1806")
    g.save("d7_cake.svg")


def d8_wedding():
    g = dessert_svg(48, 60)
    soft_shadow(g, 0, 29.4, 22, 3.2, 0.26)

    def tier(y, w, h):
        p = rrect(-w / 2, y, w, h, 4.5)
        soft_shadow(g, 0, y + h - 0.5, w * 0.48, 2.4, 0.22)
        g.path(p, fill=g.lg(-w / 2, 0, w / 2, 0, [(0, "#FFFFFF"), (0.55, "#FDF3F1"), (1, "#E6CFD1")]))
        c = g.clip(p)

        def inner():
            g.path(rrect(-w / 2, y + h - 9, w, 9, 0), fill=g.lg(0, y + h - 9, 0, y + h, [(0, ("#966E6E", 0)), (1, ("#966E6E", 0.22))]))
            n = round(w / 8.5)
            sw = w / n
            for i in range(n):
                x0 = -w / 2 + i * sw
                g.path(f"M{f(x0)} {f(y+2.2)}Q{f(x0+sw/2)} {f(y+7.8)} {f(x0+sw)} {f(y+2.2)}", stroke="#D7A5B4", w=1.15, op=0.8)
                g.path(circ(x0 + sw, y + 2.4, 0.9), fill="#F1C75B")
            g.path(rrect(-w / 2, y + h - 7.4, w, 3.3, 0), fill="#F7A8C2")
            g.path(rrect(-w / 2, y + h - 7.4, w, 1, 0), fill="#FFFFFF", op=0.5)
        g.group(inner, clip=c)
        x = -w / 2 + 2.6
        while x <= w / 2 - 2.4:
            g.path(circ(x, y + h - 1.9, 1.38), fill=g.rg(x, y + h - 1.9, 1.5, [(0, "#FFEFA8"), (1, "#E3AF3A")], fx=x - 0.5, fy=y + h - 2.4), stroke="#A06E14", w=0.45)
            x += 3.6
        gloss(g, -w / 2 + 3.4, y + h * 0.42, 1.1, h * 0.26, 0, 0.9)
        g.path(p, stroke="#B48C96", w=2.1)
    tier(6, 48, 24)
    tier(-11, 36, 18)
    tier(-25, 25, 15)

    def leaf(x, y, a):
        g.add(f'<g transform="translate({f(x)} {f(y)}) rotate({f(math.degrees(a))})">')
        g.path("M-3.4 0Q0 -2.6 3.4 0Q0 2.6 -3.4 0Z", fill="#7DBF62", stroke="#3F7A2E", w=0.8)
        g.path("M-2.6 0L2.6 0", stroke="#3F7A2E", w=0.5, op=0.6)
        g.add("</g>")

    def rose(x, y, s, dark):
        g.path(circ(x, y, s), fill=g.rg(x, y, s * 1.05, [(0, "#FFD3E1"), (1, "#E14E80" if dark else "#F27DA3")], fx=x - s * 0.35, fy=y - s * 0.4), stroke="#B32F62", w=1)
        g.path(arc(x, y, s * 0.56, math.pi * 0.3, math.pi * 1.7), stroke="#B32F62", w=0.8, op=0.75)
        g.path(arc(x + s * 0.1, y, s * 0.24, 0, TAU * 0.7), stroke="#B32F62", w=0.7, op=0.75)
    for x, y, a in [(9, -14, .6), (17.5, -2, -.5), (20.6, 10, .9), (-21, 21, -.4), (5, -28.5, .2), (-5.6, -28.5, 2.9)]:
        leaf(x, y, a)
    for x, y, s, d in [(11.5, -18, 3.2, 1), (14.6, -10.8, 3.8, 0), (11.6, -6, 2.5, 1), (17, 2.6, 3.3, 1), (21, 6.4, 2.6, 0), (18.6, 12, 3.9, 1), (-19, 16.6, 3.6, 0), (-21.4, 23.2, 2.6, 1), (-15.6, 23.4, 3, 1)]:
        rose(x, y, s, d)
    # heart topper
    g.add('<g transform="translate(0 -28)">')
    g.path("M0 4C-7.6 -0.6 -4.6 -6.8 0 -3C4.6 -6.8 7.6 -0.6 0 4Z", fill=g.rg(0, -1, 6, [(0, "#FFA5BE"), (1, "#E23B6E")], fx=-1.6, fy=-2), stroke="#A81F4E", w=1.2)
    gloss(g, -2, -2.2, 1.05, 0.7, -0.6, 0.9)
    g.add("</g>")
    face(g, 0, 16, 0.98, "lash", "#6B3A4A")
    for sx, sy, ss in [(-19, -17, 3.4), (19, -24, 2.6), (-14, -27, 2.2)]:
        g.path(star4(sx, sy, ss), fill="#FFF3A8", stroke="#E0A000", w=0.5)
    g.save("d8_wedding.svg")


# ---------- icons ----------
def icon_svg():
    return SVG((-36, -36, 72, 72))


def coin():
    g = icon_svg()
    soft_shadow(g, 0, 24, 20, 4, 0.3)
    g.path(circ(0, 0, 24), fill=g.rg(0, 0, 26, [(0, "#FFF7C0"), (0.55, "#FFD23F"), (1, "#E09A08")], fx=-8, fy=-9), stroke="#A86B00", w=2.6)
    g.path(arc(0, 0, 21.6, math.pi * 0.15, math.pi * 0.85), stroke="#B87800", w=2, op=0.5)
    g.path(circ(0, 0, 18), fill=g.rg(0, 0, 19, [(0, "#FFE680"), (1, "#F2B21A")], fx=-5, fy=-6), stroke="#A86B00", w=1.6, extra=' stroke-opacity="0.6"')
    pts = []
    for i in range(10):
        a = -math.pi / 2 + i * math.pi / 5
        r = 5 if i % 2 else 11.5
        pts.append((math.cos(a) * r, math.sin(a) * r + 0.6))
    g.path(poly(pts), fill=g.lg(0, -11, 0, 12, [(0, "#FFFDE8"), (1, "#FFE9A0")]), stroke="#C98500", w=1.5)
    g.path(arc(0, 0, 21, math.pi * 1.1, math.pi * 1.4), stroke="#FFFFFF", w=2.6, op=0.92)
    g.path(star4(15, -15, 4), fill="#FFFFFF", op=0.95)
    g.save("coin.svg")


def perk_pop():
    g = icon_svg()
    soft_shadow(g, 0, 26, 22, 4, 0.26)

    def burst(n, ro, ri, rot):
        return poly([(math.cos(rot + i * math.pi / n) * (ri if i % 2 else ro), math.sin(rot + i * math.pi / n) * (ri if i % 2 else ro)) for i in range(n * 2)])
    b = burst(11, 27, 18.5, -math.pi / 2)
    g.path(b, fill=g.rg(0, 0, 28, [(0, "#FFE4EE"), (0.5, "#FF7FAD"), (1, "#DE3474")], fx=-6, fy=-8), stroke="#A81F58", w=2.5)
    g.path(burst(11, 17.5, 13, -math.pi / 2 + 0.28), fill=g.rg(0, 0, 18, [(0, "#FFFFFF"), (1, "#FFEFF4")]), stroke="#A81F58", w=1.3, extra=' stroke-opacity="0.45"')
    face(g, 0, -1.5, 0.84, "open", "#6E0F38")
    g.path(star4(21, -21, 4.8), fill="#FFF3A8", stroke="#E0A000", w=0.6)
    g.path(star4(-23, 17, 3.6), fill="#FFF3A8", stroke="#E0A000", w=0.6)
    g.save("perk_pop.svg")


def perk_sweep():
    g = icon_svg()
    soft_shadow(g, 2, 26, 22, 4, 0.26)
    g.add('<g transform="rotate(31.5) translate(-2 -2)">')
    g.path(rrect(-2.8, -29, 5.6, 33, 2.8), fill=g.lg(-3, 0, 3, 0, [(0, "#F0C898"), (1, "#B27440")]), stroke="#7A4A24", w=1.8)
    br = "M-8.5 6L8.5 6Q13 16 14.5 25Q0 29 -14.5 25Q-13 16 -8.5 6Z"
    g.path(br, fill=g.lg(0, 6, 0, 27, [(0, "#FFEDA6"), (1, "#EFA624")]))
    c = g.clip(br)

    def inner():
        for i in range(-3, 4):
            g.path(f"M{f(i*2.3)} 7L{f(i*4.1)} 28", stroke="#A86B00", w=1.1, op=0.45)
    g.group(inner, clip=c)
    g.path(br, stroke="#A86B00", w=2.2)
    g.path(rrect(-9.5, 1.5, 19, 6.5, 3), fill=g.lg(0, 1, 0, 8, [(0, "#9ADAF8"), (1, "#3F9FE0")]), stroke="#1F68AC", w=1.8)
    g.path(rrect(-7.5, 2.4, 10, 1.4, 0.7), fill="#FFFFFF", op=0.7)
    face(g, 0, 15, 0.64, "happy", "#7A4A00")
    g.add("</g>")
    for x, y, a, col in [(17, 14, 0.5, "#FF6FA0"), (22, 21, -0.4, "#5CB9EE"), (13, 23, 1.1, "#7ED957")]:
        sprinkle_bit(g, x, y, a, col, 6.8, 3)
    g.path(arc(-2, 6, 27, math.pi * 0.02, math.pi * 0.2), stroke="#FFFFFF", w=2.3, op=0.95)
    g.path(arc(-2, 6, 22, math.pi * 0.06, math.pi * 0.17), stroke="#FFFFFF", w=1.8, op=0.8)
    g.save("perk_sweep.svg")


def perk_upgrade():
    g = icon_svg()
    soft_shadow(g, 0, 26, 18, 4, 0.26)
    p = "M0 -26L21 -3Q23 0 19 0L11 0L11 20Q11 25 6 25L-6 25Q-11 25 -11 20L-11 0L-19 0Q-23 0 -21 -3Z"
    g.path(p, fill=g.lg(0, -26, 0, 25, [(0, "#D2FAB4"), (0.5, "#74D95C"), (1, "#35A034")]))
    c = g.clip(p)
    g.group(lambda: g.path(rrect(-24, -28, 48, 56, 0), fill=g.lg(-22, 0, 22, 0, [(0, ("#FFFFFF", 0.32)), (0.5, ("#FFFFFF", 0)), (1, ("#00461A", 0.26))])), clip=c)
    g.path("M-1 -19L-13 -5.5", stroke="#FFFFFF", w=2.7, op=0.88)
    g.path(p, stroke="#1F7A2A", w=2.5)
    face(g, 0, 9, 0.8, "happy", "#12521C")
    g.path(star4(21, -19, 5.6), fill="#FFF3A8", stroke="#E0A000", w=0.6)
    g.path(star4(-22, -13, 3.6), fill="#FFF3A8", stroke="#E0A000", w=0.6)
    g.path(star4(22, 15, 3.2), fill="#FFFFFF")
    g.save("perk_upgrade.svg")


# ---------- scene ----------
# Jar: inner walls line up with the physics walls (see scripts/game.gd). The glass
# thickness is drawn outside the inner edge, so desserts never overlap it.
L, Rr, TOP, BOT = 42, 598, 50, 889
GT, GB = 11, 20          # wall and base thickness
RI, RO = 26, 40          # inner and outer corner radius
CX, RX, RY = 320, 291, 16
GLASS, GLASS_DK = "#BDECE8", "#2E7F85"


def jar_inner():
    return f"M{L} {TOP}V{BOT-RI}Q{L} {BOT} {L+RI} {BOT}H{Rr-RI}Q{Rr} {BOT} {Rr} {BOT-RI}V{TOP}"


def jar_outer(inset=0.0):
    l, r, b = L - GT + inset, Rr + GT - inset, BOT + GB - inset
    ro = RO - inset
    return f"M{f(l)} {TOP}V{f(b-ro)}Q{f(l)} {f(b)} {f(l+ro)} {f(b)}H{f(r-ro)}Q{f(r)} {f(b)} {f(r)} {f(b-ro)}V{TOP}"


def squash(g, cx, cy, r, ky, stops):
    g.add(f'<g transform="translate({f(cx)} {f(cy)}) scale(1 {f(ky)})">')
    g.path(circ(0, 0, r), fill=g.rg(0, 0, r, stops))
    g.add("</g>")


def jar_back():
    g = SVG((0, 0, 640, 940))
    ob = BOT + GB
    # contact shadow, then light focused through the glass onto the counter
    squash(g, CX + 6, ob + 1, 335, 0.075, [(0, ("#2A1206", 0.6)), (0.72, ("#2A1206", 0.34)), (1, ("#2A1206", 0))])
    squash(g, CX + 70, ob + 9, 230, 0.05, [(0, ("#FFF4D2", 0.75)), (0.5, ("#FFF4D2", 0.3)), (1, ("#FFF4D2", 0))])
    body = jar_inner() + "Z"
    g.path(body, fill=g.lg(0, TOP, 0, BOT, [(0, ("#FFFFFF", 0.1)), (0.7, ("#F2FFFD", 0.2)), (1, ("#E6FFFB", 0.34))]))
    c = g.clip(body)

    def inner():
        box = rrect(L, TOP, Rr - L, BOT - TOP, 0)
        # glass looks darker where you see through more of it: the edges
        g.path(box, fill=g.lg(L, 0, Rr, 0, [(0, ("#3E9A9A", 0.3)), (0.045, ("#3E9A9A", 0.1)), (0.13, ("#3E9A9A", 0)),
                                            (0.87, ("#3E9A9A", 0)), (0.955, ("#3E9A9A", 0.1)), (1, ("#3E9A9A", 0.26))]))
        g.path(box, fill=g.lg(L, 0, Rr, 0, [(0.02, ("#FFFFFF", 0)), (0.06, ("#FFFFFF", 0.3)), (0.16, ("#FFFFFF", 0)),
                                            (0.86, ("#FFFFFF", 0)), (0.945, ("#FFFFFF", 0.22)), (0.98, ("#FFFFFF", 0))]))
        # round floor seen through the front wall
        squash(g, CX, BOT - 18, 262, 0.2, [(0, ("#FFFFFF", 0.38)), (0.7, ("#FFFFFF", 0.12)), (1, ("#FFFFFF", 0))])
        g.path(arc(CX, BOT - 16, 13, math.pi * 1.03, math.pi * 1.97, rx=264), stroke="#FFFFFF", w=2.2, op=0.42)
        g.path(arc(CX, BOT - 13, 13, math.pi * 1.05, math.pi * 1.95, rx=262), stroke=GLASS_DK, w=1.4, op=0.14)
    g.group(inner, clip=c)
    # far half of the rim
    g.path(arc(CX, TOP, RY, math.pi, TAU, rx=RX), stroke=GLASS_DK, w=9, op=0.14)
    g.path(arc(CX, TOP, RY, math.pi, TAU, rx=RX), stroke="#FFFFFF", w=5.5, op=0.72)
    g.path(arc(CX, TOP + 2.5, RY - 5, math.pi * 1.04, math.pi * 1.96, rx=RX - 13), stroke=GLASS_DK, w=1.8, op=0.16)
    g.path(arc(CX, TOP + 1, RY - 4, math.pi * 1.2, math.pi * 1.45, rx=RX - 11), stroke="#FFFFFF", w=2, op=0.7)
    g.save("jar_back.svg")


def jar_front():
    g = SVG((0, 0, 640, 940))
    ob = BOT + GB
    l, r = L - GT, Rr + GT
    wall = jar_outer() + "Z" + jar_inner() + "Z"
    ev = ' fill-rule="evenodd"'
    g.path(wall, fill=g.lg(0, TOP, 0, ob, [(0, ("#F4FFFD", 0.5)), (0.85, ("#E2FAF7", 0.46)), (1, (GLASS, 0.62))]), extra=ev)
    cw = g.clip(jar_outer() + "Z")

    def base():
        # heavy glass foot: tinted, with bright refracted lines
        g.path(rrect(l, BOT - 4, r - l, GB + 6, 0), fill=g.lg(0, BOT - 4, 0, ob, [(0, ("#57B5B2", 0)), (0.45, ("#57B5B2", 0.2)), (1, ("#2E8F8F", 0.4))]))
        g.path(f"M{L+34} {BOT+5.5}H{Rr-34}", stroke="#FFFFFF", w=3, op=0.85)
        g.path(f"M{L+70} {BOT+11.5}H{Rr-150}", stroke="#FFFFFF", w=1.6, op=0.5)
        g.path(f"M{L+20} {ob-3.6}H{Rr-20}", stroke="#FFFFFF", w=1.6, op=0.45)
        for x0, w0 in [(120, 46), (214, 18), (300, 70), (430, 26), (492, 54)]:
            g.path(rrect(x0, BOT + 8.5, w0, 6, 3), fill="#FFFFFF", op=0.38)
        # walls: a light core inside the glass thickness
        for x0 in (l + 3.2, Rr + 3.6):
            g.path(rrect(x0, TOP + 16, 4, BOT - TOP - 70, 2), fill="#FFFFFF", op=0.7)
    g.group(base, clip=cw)
    g.path(jar_outer(), stroke=GLASS_DK, w=2.2, op=0.42)
    g.path(jar_outer(1.6), stroke="#FFFFFF", w=1.3, op=0.75)
    g.path(jar_inner(), stroke=GLASS_DK, w=4.2, op=0.12)
    g.path(jar_inner(), stroke="#FFFFFF", w=2.6, op=0.92)

    ci = g.clip(jar_inner() + "Z")

    def sheen():
        def streak(x, y0, y1, w, a):
            g.path(rrect(x, y0, w, y1 - y0, w / 2), fill=g.lg(x, 0, x + w, 0, [(0, ("#FFFFFF", 0)), (0.35, ("#FFFFFF", a)), (0.65, ("#FFFFFF", a)), (1, ("#FFFFFF", 0))]))
        # broad soft sheen down the left, tighter glints next to it
        g.path(rrect(L, TOP, 150, BOT - TOP, 0), fill=g.lg(L, 0, L + 150, 0, [(0, ("#FFFFFF", 0.2)), (0.5, ("#FFFFFF", 0.07)), (1, ("#FFFFFF", 0))]))
        g.path(rrect(Rr - 90, TOP, 90, BOT - TOP, 0), fill=g.lg(Rr - 90, 0, Rr, 0, [(0, ("#FFFFFF", 0)), (1, ("#FFFFFF", 0.14))]))
        streak(L + 12, TOP + 300, BOT - 110, 22, 0.46)
        streak(L + 40, TOP + 360, BOT - 300, 7, 0.34)
        streak(Rr - 34, TOP + 110, TOP + 470, 13, 0.3)
        streak(Rr - 16, TOP + 200, TOP + 330, 5, 0.34)
        # the bakery window, mirrored in the glass
        wx, wy = L + 22, TOP + 62
        for cx_ in range(2):
            for cy_ in range(2):
                x0, y0 = wx + cx_ * 31, wy + cy_ * 62 + cx_ * 7
                pw, ph, sk = 26, 56, 6
                d = poly([(x0, y0 + 4), (x0 + pw, y0 + sk + 2), (x0 + pw, y0 + ph + sk), (x0, y0 + ph - 3)])
                g.path(d, fill=g.lg(0, wy, 0, wy + 130, [(0, ("#FFFFFF", 0.5)), (1, ("#FFFFFF", 0.2))]), stroke="#FFFFFF", w=5, extra=' stroke-opacity="0.16"')
        # corner glints where the wall turns into the floor
        g.path(f"M{L+11} {BOT-96}Q{L+13} {BOT-17} {L+92} {BOT-13}", stroke="#FFFFFF", w=5, op=0.55)
        g.path(f"M{Rr-11} {BOT-78}Q{Rr-13} {BOT-18} {Rr-64} {BOT-14}", stroke="#FFFFFF", w=2.8, op=0.36)
    g.group(sheen, clip=ci)

    # near half of the rolled rim
    g.path(arc(CX, TOP, RY, 0, math.pi, rx=RX), stroke=GLASS_DK, w=15, op=0.16)
    g.path(arc(CX, TOP, RY, 0, math.pi, rx=RX), stroke="#FFFFFF", w=10.5, op=0.97)
    g.path(arc(CX, TOP + 2.6, RY - 0.5, math.pi * 0.06, math.pi * 0.94, rx=RX - 1), stroke="#8FD2CE", w=3, op=0.75)
    g.path(arc(CX, TOP - 2.2, RY, math.pi * 0.08, math.pi * 0.92, rx=RX - 1), stroke="#FFFFFF", w=2.6, op=1)
    g.path(arc(CX, TOP + 5.6, RY, math.pi * 0.3, math.pi * 0.44, rx=RX), stroke="#FFFFFF", w=1.6, op=0.8)
    g.path(star4(L + 34, TOP + 9, 13), fill="#FFFFFF", op=0.95)
    g.path(star4(L + 52, TOP + 24, 5), fill="#FFFFFF", op=0.85)
    g.save("jar_front.svg")


def bg_wall():
    W, H = 720, 1480
    g = SVG((0, 0, W, H))
    g.path(f"M0 0H{W}V{H}H0Z", fill=g.lg(0, 0, 0, H, [(0, "#CDEFE7"), (0.45, "#AEE0D8"), (1, "#8ACCC4")]))
    R = random.Random(41)
    tw, th, gr = 120, 60, 3.5

    def motif(cx, cy, kind):
        if kind == 0:   # four-petal flower
            for a in range(4):
                g.path(ell(cx + math.cos(a * TAU / 4) * 7, cy + math.sin(a * TAU / 4) * 7, 6, 3.4, a * TAU / 4), fill="#FFFFFF", op=0.2)
            g.path(circ(cx, cy, 2.4), fill="#FFFFFF", op=0.3)
        else:           # heart
            g.path(f"M{cx} {cy+8}C{cx-15} {cy-1} {cx-9} {cy-13} {cx} {cy-5}C{cx+9} {cy-13} {cx+15} {cy-1} {cx} {cy+8}Z", fill="#FFFFFF", op=0.2)

    for row in range(H // th + 1):
        y = row * th
        x = -tw / 2 if row % 2 else 0
        while x < W:
            v = R.random()
            tx, ty, w_, h_ = x + gr / 2, y + gr / 2, tw - gr, th - gr
            if v < 0.3:
                g.path(rrect(tx, ty, w_, h_, 7), fill="#1F7F7A", op=0.02 + v * 0.1)
            else:
                g.path(rrect(tx, ty, w_, h_, 7), fill="#FFFFFF", op=0.03 + (v - 0.3) * 0.1)
            g.path(rrect(tx + 4, ty + 3, w_ - 8, 5, 2.5), fill="#FFFFFF", op=0.15)          # glazed top edge
            g.path(rrect(tx + 3, ty + h_ - 6, w_ - 6, 3.5, 1.75), fill="#1F6E6A", op=0.08)   # bottom bevel
            if R.random() < 0.3:
                g.path(rrect(tx + 10 + R.random() * 50, ty + 13, 16 + R.random() * 22, 3, 1.5), fill="#FFFFFF", op=0.1)
            if R.random() < 0.085:
                motif(x + tw / 2, y + th / 2, int(R.random() * 2))
            x += tw
    for row in range(H // th + 2):
        y = row * th
        g.path(f"M0 {y}H{W}", stroke="#F2FCFA", w=gr, op=0.42)
        x = -tw / 2 if row % 2 else 0
        while x < W + tw:
            g.path(f"M{f(x)} {y}V{y+th}", stroke="#F2FCFA", w=gr, op=0.42)
            x += tw

    # warm daylight from a window up and to the left
    squash(g, 120, 160, 760, 0.8, [(0, ("#FFF4D0", 0.5)), (0.4, ("#FFF4D0", 0.18)), (1, ("#FFF4D0", 0))])
    # the window's shape thrown across the wall: 2 x 3 panes with soft edges
    ox, oy = 250, 318
    u, v_ = (158, 44), (-78, 214)
    for cy_ in range(3):
        for cx_ in range(2):
            a_row = (1.0, 0.82, 0.6)[cy_]
            cxp = ox + u[0] * (cx_ + 0.5) + v_[0] * (cy_ + 0.5)
            cyp = oy + u[1] * (cx_ + 0.5) + v_[1] * (cy_ + 0.5)
            for grow, a in [(1.1, 0.05), (1.0, 0.07), (0.9, 0.16)]:
                hu, hv = 0.5 * 0.9 * grow, 0.5 * 0.92 * grow
                pts = [(cxp + sx * hu * u[0] + sy * hv * v_[0], cyp + sx * hu * u[1] + sy * hv * v_[1]) for sx, sy in [(-1, -1), (1, -1), (1, 1), (-1, 1)]]
                g.path(poly(pts), fill="#FFF7DA", op=a * a_row, stroke="#FFF7DA", w=10, extra=f' stroke-opacity="{f(a * a_row * 0.5)}"')
    # a leafy branch on the sill, shadowed into the light
    RL = random.Random(9)
    for k in range(9):
        t = k / 8
        sx, sy = 96 + t * 190, 1010 - t * 250 + math.sin(t * 3) * 20
        for side in (-1, 1):
            a = -0.9 + side * 1.0 + RL.random() * 0.3
            ln = 46 - t * 14 + RL.random() * 10
            lx, ly = sx + math.cos(a) * ln * 0.6, sy + math.sin(a) * ln * 0.6
            lf = f"M{f(-ln/2)} 0Q0 {f(-ln*0.36)} {f(ln/2)} 0Q0 {f(ln*0.36)} {f(-ln/2)} 0Z"
            for grow, al in [(1.2, 0.035), (1.0, 0.06)]:
                g.add(f'<g transform="translate({f(lx)} {f(ly)}) rotate({f(math.degrees(a))}) scale({grow})">')
                g.path(lf, fill="#1D6F6C", op=al)
                g.add("</g>")
    g.path("M96 1010Q170 900 286 760", stroke="#1D6F6C", w=5, op=0.06)
    # corners fall off into shade
    g.add(f'<g transform="translate({W/2} 760) scale(1 1.6)">')
    g.path(circ(0, 0, 660), fill=g.rg(0, 0, 660, [(0, ("#0A3C41", 0)), (0.6, ("#0A3C41", 0)), (1, ("#0A3C41", 0.34))]))
    g.add("</g>")
    g.save("bg_wall.svg")


# Counter sprite layout (design px from the top of the SVG). game.gd places the
# sprite so that COUNTER_TOP lines up 40 px above the jar floor.
COUNTER_PAD, COUNTER_SURF, COUNTER_NOSE, COUNTER_H = 30, 68, 14, 310
COUNTER_BASE = "#6A3D21"   # colour at the very bottom; game.gd fills below with the same


def counter():
    W = 720
    g = SVG((0, 0, W, COUNTER_H))
    R = random.Random(53)
    s0, s1 = COUNTER_PAD, COUNTER_PAD + COUNTER_SURF
    n1 = s1 + COUNTER_NOSE
    # shade where the wall meets the worktop
    g.path(f"M0 0H{W}V{s0}H0Z", fill=g.lg(0, 0, 0, s0, [(0, ("#0F3F3E", 0)), (0.6, ("#0F3F3E", 0.1)), (1, ("#0F3F3E", 0.3))]))
    # front: walnut boards
    g.path(f"M0 {n1}H{W}V{COUNTER_H}H0Z", fill="#8F5A33")
    x, k = 0, 0
    widths = [104, 122, 96, 128, 110, 118, 100]
    cols = ["#A26A3F", "#98603A", "#AB7245", "#9C6439"]
    while x < W:
        w = widths[k % len(widths)]
        col = cols[k % len(cols)]
        g.path(rrect(x, n1, w, COUNTER_H - n1, 0), fill=g.lg(x, 0, x + w, 0, [(0, mix(col, "#FFFFFF", 0.08)), (0.5, col), (1, mix(col, "#3A1A08", 0.16))]))
        for j in range(5):
            gx = x + 10 + R.random() * (w - 20)
            amp = 2 + R.random() * 4
            d = f"M{f(gx)} {n1}"
            yy = n1
            while yy < COUNTER_H:
                d += f"Q{f(gx + amp * (1 if (yy // 30) % 2 else -1))} {yy+15} {f(gx)} {yy+30}"
                yy += 30
            g.path(d, stroke="#5E3417", w=0.9 + R.random() * 0.9, op=0.16 + R.random() * 0.1)
        if R.random() < 0.55:
            kx, ky = x + 22 + R.random() * (w - 44), n1 + 60 + R.random() * 110
            g.path(ell(kx, ky, 5, 3), fill="#5E3417", op=0.4)
            g.path(ell(kx, ky, 9, 6), stroke="#5E3417", w=1, op=0.22)
            g.path(ell(kx, ky, 14, 9.5), stroke="#5E3417", w=0.8, op=0.12)
        g.path(f"M{x} {n1}V{COUNTER_H}", stroke="#4E2A12", w=3, op=0.6)
        g.path(f"M{x+2.6} {n1}V{COUNTER_H}", stroke="#E0A878", w=1.2, op=0.3)
        x += w
        k += 1
    g.path(f"M0 {n1}H{W}V{COUNTER_H}H0Z", fill=g.lg(0, n1, 0, COUNTER_H, [(0, ("#1E0C04", 0.6)), (0.1, ("#1E0C04", 0.2)), (0.24, ("#1E0C04", 0.03)),
                                                                           (0.7, (COUNTER_BASE, 0)), (1, (COUNTER_BASE, 1))]))
    # worktop: pale butcher block, staves running left to right
    g.path(f"M0 {s0}H{W}V{s1}H0Z", fill=g.lg(0, s0, 0, s1, [(0, "#F1D2A6"), (0.5, "#F0C894"), (1, "#E3B079")]))
    rows = [9, 11, 13, 16, 19]
    y = s0
    for ri, rh in enumerate(rows):
        x = -R.random() * 160
        while x < W:
            w = 150 + R.random() * 170
            tint = R.random()
            g.path(rrect(x, y, w, rh, 0), fill="#FFFFFF" if tint > 0.5 else "#B9793F", op=abs(tint - 0.5) * 0.3)
            g.path(f"M{f(x)} {f(y)}V{f(y+rh)}", stroke="#9A6534", w=1.2, op=0.4)
            for j in range(2):
                gy = y + 2 + R.random() * (rh - 4)
                g.path(f"M{f(x+6)} {f(gy)}C{f(x+w*0.3)} {f(gy+R.random()*2-1)} {f(x+w*0.7)} {f(gy+R.random()*2-1)} {f(x+w-6)} {f(gy)}", stroke="#B07A45", w=0.8, op=0.3)
            x += w
        if ri:
            g.path(f"M0 {f(y)}H{W}", stroke="#9A6534", w=1.1, op=0.38)
            g.path(f"M0 {f(y+1.1)}H{W}", stroke="#FFFFFF", w=0.8, op=0.3)
        y += rh
    # window light sliding across the worktop
    g.path(poly([(40, s0), (300, s0), (420, s1), (110, s1)]), fill=g.lg(40, 0, 420, 0, [(0, ("#FFFFFF", 0)), (0.25, ("#FFFBE8", 0.4)), (0.7, ("#FFFBE8", 0.2)), (1, ("#FFFFFF", 0))]))
    g.path(f"M0 {s0}H{W}V{s0+16}H0Z", fill=g.lg(0, s0, 0, s0 + 16, [(0, ("#7A4A20", 0.34)), (1, ("#7A4A20", 0))]))
    # rounded front edge
    g.path(f"M0 {s1}H{W}V{n1}H0Z", fill=g.lg(0, s1, 0, n1, [(0, "#FBE6C2"), (0.3, "#E5B57D"), (0.75, "#B67B45"), (1, "#8A5428")]))
    g.path(f"M0 {s1+1.6}H{W}", stroke="#FFFFFF", w=2.4, op=0.7)
    g.path(f"M0 {n1}H{W}", stroke="#3E1F0C", w=2, op=0.55)
    g.save("counter.svg")


def shelf():
    """700 x 64. Desserts stand on the top face (y 2..12)."""
    g = SVG((0, 0, 700, 64))
    R = random.Random(61)
    # shadow the plank throws on the wall
    g.path(poly([(10, 24), (694, 24), (700, 54), (22, 54)]), fill=g.lg(0, 24, 0, 54, [(0, ("#0F3F3E", 0.26)), (1, ("#0F3F3E", 0))]))
    for bx in (78, 622):
        b = f"M{bx-8} 22H{bx+8}V40Q{bx+8} 60 {bx-8} 60Z"
        g.path(b, fill=g.lg(bx - 8, 0, bx + 8, 0, [(0, "#B57A45"), (0.5, "#9A6234"), (1, "#74441F")]), stroke="#4E2A12", w=1.6)
        g.path(f"M{bx-4.5} 26V50", stroke="#F0C596", w=1.6, op=0.5)
    top = "M10 2H690L698 12H2Z"
    g.path(top, fill=g.lg(0, 2, 0, 12, [(0, "#E9C08C"), (1, "#F6D7A8")]))
    front = rrect(2, 12, 696, 14, 3)
    g.path(front, fill=g.lg(0, 12, 0, 26, [(0, "#D9A46C"), (0.5, "#C08A54"), (1, "#96602F")]))
    c = g.clip(front)

    def grain():
        x = -R.random() * 100
        while x < 700:
            w = 140 + R.random() * 160
            g.path(rrect(x, 12, w, 14, 0), fill="#FFFFFF" if R.random() > 0.5 else "#6E3F1A", op=0.07)
            g.path(f"M{f(x)} 12V26", stroke="#6E3F1A", w=1, op=0.3)
            x += w
        for j in range(4):
            y = 14.5 + j * 3
            g.path(f"M4 {f(y)}C230 {f(y+R.random()*2-1)} 470 {f(y+R.random()*2-1)} 696 {f(y)}", stroke="#6E3F1A", w=0.8, op=0.24)
    g.group(grain, clip=c)
    g.path(top + front, stroke="#6E3F1A", w=1.5, op=0.75)
    g.path("M4 12.6H696", stroke="#FFFFFF", w=1.6, op=0.65)
    g.path("M12 3.2H688", stroke="#FFFFFF", w=1, op=0.5)
    g.save("shelf.svg")


def plate():
    g = SVG((-40, -40, 80, 80))
    soft_shadow(g, 0, 4, 40, 37, 0.34)
    # paper doily
    n = 22
    for i in range(n):
        a = i / n * TAU
        g.path(circ(math.cos(a) * 34.4, math.sin(a) * 34.4, 5), fill="#FFFDF8", stroke="#E7D5C3", w=0.7)
    g.path(circ(0, 0, 34.6), fill="#FFFDF8")
    for i in range(n):
        a = (i + 0.5) / n * TAU
        g.path(circ(math.cos(a) * 33.4, math.sin(a) * 33.4, 1.25), fill="#8F5A33", op=0.4)
        a = i / n * TAU
        g.path(circ(math.cos(a) * 36.2, math.sin(a) * 36.2, 0.95), fill="#8F5A33", op=0.34)
    soft_shadow(g, 0.6, 2.6, 31.5, 30.5, 0.3)
    g.path(circ(0, 0, 29.6), fill=g.rg(0, 0, 30.4, [(0, "#FFFFFF"), (0.8, "#FBF6F0"), (1, "#E2D5C8")], fx=-7, fy=-9), stroke="#CDB9A6", w=1.3)
    g.path(circ(0, 0, 20.6), fill=g.rg(0, 0, 21, [(0, "#FFFFFF"), (0.85, "#F8F2EB"), (1, "#E6D9CB")], fx=4, fy=6))
    g.path(arc(0, 0, 20.6, math.pi * 0.95, math.pi * 1.6), stroke="#D5C6B8", w=1.3, op=0.85)
    g.path(arc(0, 0, 20.6, math.pi * 0.05, math.pi * 0.6), stroke="#FFFFFF", w=1.3)
    g.path(circ(0, 0, 27.2), stroke="#F58DB2", w=1.5, op=0.85)
    g.path(circ(0, 0, 24.9), stroke="#F7B9CE", w=0.7, op=0.8)
    g.path(arc(0, 0, 25.4, math.pi * 1.1, math.pi * 1.42), stroke="#FFFFFF", w=3, op=0.95)
    g.path(arc(0, 0, 25.4, math.pi * 1.46, math.pi * 1.5), stroke="#FFFFFF", w=3, op=0.95)
    g.save("plate.svg")


def panel():
    g = SVG((0, 0, 120, 120))
    g.path(rrect(0, 6, 120, 114, 28), fill="#4A2618", op=0.2)
    g.path(rrect(0, 0, 120, 114, 28), fill="#FFF9F2")
    g.path(rrect(0, 0, 120, 114, 28), stroke="#F1DCCB", w=1.5)
    g.save("panel.svg")


# ---------- props that sit on the counter beside the jar ----------
def prop_plant():
    """140 x 230, pot base centred at (70, 222)."""
    g = SVG((0, 0, 140, 230))
    R = random.Random(71)
    soft_shadow(g, 76, 222, 48, 6, 0.4)
    leaf = "M0 0C-15 -12 -14 -40 0 -56C14 -40 15 -12 0 0Z"
    for k, (ang, ln, sc, col) in enumerate([(-74, 44, 0.8, "#5FA98A"), (70, 48, 0.85, "#5FA98A"), (-46, 70, 1.0, "#6DB796"), (44, 74, 1.0, "#79C2A0"),
                                            (-18, 92, 1.1, "#86CBA8"), (20, 98, 1.05, "#6DB796"), (2, 62, 0.9, "#93D4B2")]):
        a = math.radians(ang - 90)
        bx, by = 70 + math.cos(a) * ln, 146 + math.sin(a) * ln
        g.path(f"M70 148Q{f(70 + math.cos(a) * ln * 0.3)} {f(146 + math.sin(a) * ln * 0.75)} {f(bx)} {f(by)}", stroke="#3F8F74", w=2.6)
        g.add(f'<g transform="translate({f(bx)} {f(by)}) rotate({f(ang + (R.random() - 0.5) * 16)}) scale({f(sc)})">')
        g.path(leaf, fill=g.lg(-14, 0, 14, 0, [(0, mix(col, "#FFFFFF", 0.22)), (1, mix(col, "#1F5F54", 0.25))]), stroke="#2F7A62", w=1.5, extra=' stroke-opacity="0.6"')
        g.path("M0 -3L0 -48", stroke="#2F7A62", w=1, op=0.4)
        for t in (-14, -26, -38):
            g.path(f"M0 {t}L-7 {t-6}M0 {t}L7 {t-6}", stroke="#2F7A62", w=0.8, op=0.28)
        g.add("</g>")
    pot = "M36 152H104L95 215Q94 222 87 222H53Q46 222 45 215Z"
    g.path(pot, fill=g.lg(36, 0, 104, 0, [(0, "#F6B9B0"), (0.45, "#E99A95"), (1, "#C4706F")]), stroke="#9A4E52", w=2)
    c = g.clip(pot)
    g.group(lambda: (g.path(rrect(30, 182, 80, 9, 0), fill="#FFF3EA", op=0.75),
                     g.path(rrect(30, 150, 80, 12, 0), fill=g.lg(0, 150, 0, 162, [(0, ("#7A2F3A", 0.4)), (1, ("#7A2F3A", 0))])),
                     g.path(rrect(43, 160, 6, 52, 3), fill="#FFFFFF", op=0.4)), clip=c)
    g.path(rrect(31, 141, 78, 14, 6), fill=g.lg(31, 0, 109, 0, [(0, "#FBC9C0"), (0.5, "#EDA29C"), (1, "#C97878")]), stroke="#9A4E52", w=2)
    g.path(rrect(38, 144, 30, 3, 1.5), fill="#FFFFFF", op=0.55)
    g.save("prop_plant.svg")


def prop_crock():
    """140 x 250, crock base centred at (70, 242)."""
    g = SVG((0, 0, 140, 250))
    soft_shadow(g, 76, 242, 50, 6, 0.4)
    # whisk
    g.add('<g transform="translate(86 176) rotate(14)">')
    for rx in (15, 9, 3):
        g.path(ell(0, -122, rx, 36), stroke="#9FB3B8", w=2.2)
        g.path(ell(-0.8, -122, rx, 36), stroke="#FFFFFF", w=0.8, op=0.7)
    g.path(rrect(-4.5, -90, 9, 94, 4.5), fill=g.lg(-4.5, 0, 4.5, 0, [(0, "#FFB3CB"), (1, "#E0628F")]), stroke="#A83763", w=1.6)
    g.path(rrect(-5.5, -92, 11, 8, 3), fill="#C9D6DA", stroke="#7F969C", w=1.2)
    g.add("</g>")
    # wooden spoon
    g.add('<g transform="translate(56 176) rotate(-13)">')
    g.path(rrect(-3.6, -112, 7.2, 116, 3.6), fill=g.lg(-4, 0, 4, 0, [(0, "#F2CB98"), (1, "#BC8248")]), stroke="#7A4A24", w=1.6)
    g.path(ell(0, -128, 14, 21), fill=g.rg(0, -128, 22, [(0, "#C9925A"), (0.6, "#E9BD88"), (1, "#F2CB98")], fx=2, fy=-124), stroke="#7A4A24", w=1.6)
    g.path(arc(0, -128, 14, math.pi * 1.1, math.pi * 1.6, rx=9), stroke="#FFFFFF", w=1.6, op=0.5)
    g.add("</g>")
    crock = rrect(32, 166, 76, 76, 12)
    g.path(crock, fill=g.lg(32, 0, 108, 0, [(0, "#FFFDF8"), (0.5, "#F6EADC"), (1, "#D8C2AE")]), stroke="#A48A76", w=2)
    c = g.clip(crock)
    g.group(lambda: (g.path(rrect(30, 194, 80, 20, 0), fill="#F79FBE"),
                     g.path(rrect(30, 194, 80, 20, 0), fill=g.lg(32, 0, 108, 0, [(0, ("#FFFFFF", 0.35)), (0.5, ("#FFFFFF", 0)), (1, ("#7A1F45", 0.3))])),
                     g.path(rrect(30, 197.5, 80, 1.6, 0), fill="#FFFFFF", op=0.7),
                     g.path(rrect(30, 209, 80, 1.6, 0), fill="#FFFFFF", op=0.7),
                     g.path(rrect(30, 164, 80, 12, 0), fill=g.lg(0, 164, 0, 176, [(0, ("#5E4636", 0.36)), (1, ("#5E4636", 0))])),
                     g.path(rrect(40, 176, 7, 58, 3.5), fill="#FFFFFF", op=0.7)), clip=c)
    g.path(rrect(28, 160, 84, 12, 6), fill=g.lg(28, 0, 112, 0, [(0, "#FFFFFF"), (0.5, "#F6EADC"), (1, "#D2BBA6")]), stroke="#A48A76", w=2)
    g.save("prop_crock.svg")


# ---------- UI art ----------
def rays():
    """Sunburst that spins behind the trophy dessert."""
    g = SVG((-100, -100, 200, 200))
    n = 12
    fill = g.rg(0, 0, 100, [(0, ("#FFFFFF", 0)), (0.3, ("#FFFFFF", 0.95)), (1, ("#FFFFFF", 0))])
    for i in range(n):
        a0, a1 = (i - 0.27) / n * TAU, (i + 0.27) / n * TAU
        g.path(poly([(0, 0), (math.cos(a0) * 100, math.sin(a0) * 100), (math.cos(a1) * 100, math.sin(a1) * 100)]), fill=fill)
    g.save("rays.svg")


def icing():
    """540 x 150 frosting that drips down from the top of a card (corner radius 44)."""
    W, base = 540, 86
    g = SVG((0, 0, W, 150))
    drips = [34, 12, 26, 44, 16, 30, 10, 38, 20, 28]
    step, dw, cr = 54, 30, 12

    def shape(dy=0.0):
        d = f"M0 44Q0 0 44 0H{W-44}Q{W} 0 {W} 44"
        for i, ln in enumerate(drips):
            x1 = W - i * step
            yb = base + ln + dy
            d += f"V{f(yb-dw/2)}A{dw/2} {dw/2} 0 0 1 {x1-dw} {f(yb-dw/2)}V{base+cr+dy}A{cr} {cr} 0 0 0 {x1-step} {base+cr+dy}"
        return d + "Z"
    g.path(shape(6), fill="#7C1440", op=0.16)
    s = shape()
    g.path(s, fill=g.lg(0, 0, 0, 130, [(0, "#FF9CC0"), (0.5, "#F2609A"), (1, "#E8427F")]))
    c = g.clip(s)

    def inner():
        g.path(rrect(0, 0, W, 40, 0), fill=g.lg(0, 0, 0, 40, [(0, ("#FFFFFF", 0.4)), (1, ("#FFFFFF", 0))]))
        R = random.Random(83)
        cols = ["#FFFFFF", "#FFE27A", "#8FE0F2", "#B9F28F", "#D5B3FF"]
        for k in range(26):
            sprinkle_bit(g, 30 + R.random() * (W - 60), 12 + R.random() * 62, R.random() * math.pi, cols[k % 5], 11, 4, edge=False)
    g.group(inner, clip=c)
    for i, ln in enumerate(drips):
        x1 = W - i * step
        g.path(rrect(x1 - dw + 6, base - 4, 5, max(8, ln - 6), 2.5), fill="#FFFFFF", op=0.5)
    g.path(rrect(40, 9, W - 80, 6, 3), fill="#FFFFFF", op=0.5)
    g.save("icing.svg")


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    fns = [d0_sprinkle, d1_chip, d2_cookie, d3_macaron, d4_cupcake, d5_donut, d6_pie, d7_cake, d8_wedding,
           coin, perk_pop, perk_sweep, perk_upgrade, jar_back, jar_front, bg_wall, counter, shelf, plate, panel,
           prop_plant, prop_crock, rays, icing]
    for fn in fns:
        fn()
    print("ok", len(fns))
