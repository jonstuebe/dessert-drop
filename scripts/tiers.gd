class_name Tiers
## The dessert ladder: sizes, physics shapes and scoring for each tier.
## Art is drawn at a base radius of 30 design units (see assets/art/d*.svg).

const SCALE := 1.6          # prototype pixels -> game pixels
const ART_R := 30.0         # radius the SVG art is drawn at
const GROWTH: Array[float] = [1.10, 1.13, 1.16, 1.19, 1.22, 1.25, 1.28, 1.31]
const DROP_WEIGHTS: Array[float] = [0.34, 0.30, 0.22, 0.14]
const COIN_REWARD := {7: 2, 8: 5}   # strawberry cake, wedding cake

const DATA := [
	{"key": "sprinkle", "file": "d0_sprinkle", "name": "Sprinkle", "shape": "rect", "bw": 2.6, "bh": 1.1, "ch": 0.55, "bounce": 0.45, "tone": Color("#FF8FB1")},
	{"key": "chip", "file": "d1_chip", "name": "Chocolate chip", "shape": "circle", "bounce": 0.38, "tone": Color("#96572F")},
	{"key": "cookie", "file": "d2_cookie", "name": "Cookie", "shape": "circle", "tone": Color("#E8B063")},
	{"key": "macaron", "file": "d3_macaron", "name": "Macaron", "shape": "rect", "bw": 2.1, "bh": 1.5, "ch": 0.55, "tone": Color("#CBB5F7")},
	{"key": "cupcake", "file": "d4_cupcake", "name": "Cupcake", "shape": "rect", "bw": 1.65, "bh": 1.95, "ch": 0.45, "tone": Color("#8ED4F7")},
	{"key": "donut", "file": "d5_donut", "name": "Donut", "shape": "circle", "friction": 0.05, "tone": Color("#FF8FB6")},
	{"key": "pie", "file": "d6_pie", "name": "Cherry pie", "shape": "circle", "tone": Color("#F0C073")},
	{"key": "cake", "file": "d7_cake", "name": "Strawberry cake", "shape": "rect", "bw": 2.1, "bh": 1.5, "ch": 0.35, "tone": Color("#B97748")},
	{"key": "wedding", "file": "d8_wedding", "name": "Wedding cake", "shape": "rect", "bw": 1.6, "bh": 2.0, "ch": 0.3, "tone": Color("#FFFFFF")},
]
const TOP := 8

static var _radii: Array[float] = []

static func count() -> int:
	return DATA.size()

## Body radius in game pixels.
static func radius(i: int) -> float:
	if _radii.is_empty():
		var r := 26.0
		for k in DATA.size():
			if k > 0:
				r *= GROWTH[k - 1]
			_radii.append(r * SCALE)
	return _radii[i]

static func info(i: int) -> Dictionary:
	return DATA[i]

static func display_name(i: int) -> String:
	return DATA[i]["name"]

static func is_circle(i: int) -> bool:
	return DATA[i]["shape"] == "circle"

## Body size in game pixels.
static func size(i: int) -> Vector2:
	var r := radius(i)
	if is_circle(i):
		return Vector2(2 * r, 2 * r)
	return Vector2(DATA[i]["bw"] * r, DATA[i]["bh"] * r)

static func points(i: int) -> int:
	return (i + 1) * (i + 2) / 2

static func tone(i: int) -> Color:
	return DATA[i]["tone"]

static func random_drop() -> int:
	var x := randf()
	for i in DROP_WEIGHTS.size():
		x -= DROP_WEIGHTS[i]
		if x < 0.0:
			return i
	return 0

## A rounded rectangle polygon for rect-shaped desserts.
static func rounded_rect(sz: Vector2, corner: float, segments: int = 5) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var hw := sz.x / 2.0
	var hh := sz.y / 2.0
	corner = minf(corner, minf(hw, hh) - 0.5)
	var centers := [Vector2(hw - corner, hh - corner), Vector2(-hw + corner, hh - corner),
		Vector2(-hw + corner, -hh + corner), Vector2(hw - corner, -hh + corner)]
	for c in 4:
		for s in segments + 1:
			var a := (c + float(s) / segments) * PI / 2.0
			pts.append(centers[c] + Vector2(cos(a), sin(a)) * corner)
	return pts
