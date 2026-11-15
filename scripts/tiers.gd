class_name Tiers
## The dessert ladder: sizes, physics shapes and scoring for each tier.
## Art is drawn at a base radius of 30 design units (see assets/art/d*.svg).

const SCALE := 2.0          # prototype pixels -> game pixels (25% up from 1.6)
const ART_R := 30.0         # radius the SVG art is drawn at
const GROWTH: Array[float] = [1.10, 1.13, 1.16, 1.19, 1.22, 1.25, 1.28, 1.31]
const DROP_WEIGHTS: Array[float] = [0.34, 0.30, 0.22, 0.14]
const COIN_REWARD := {7: 2, 8: 5}   # strawberry cake, wedding cake

const DATA := [
	{"key": "sprinkle", "file": "d0_sprinkle", "name": "Sprinkle", "shape": "rect", "bw": 2.6, "bh": 1.1, "bounce": 0.45, "tone": Color("#FF8FB1")},
	{"key": "chip", "file": "d1_chip", "name": "Chocolate chip", "shape": "circle", "bounce": 0.38, "tone": Color("#96572F")},
	{"key": "cookie", "file": "d2_cookie", "name": "Cookie", "shape": "circle", "tone": Color("#E8B063")},
	{"key": "macaron", "file": "d3_macaron", "name": "Macaron", "shape": "rect", "bw": 2.1, "bh": 1.5, "tone": Color("#CBB5F7")},
	{"key": "cupcake", "file": "d4_cupcake", "name": "Cupcake", "shape": "rect", "bw": 1.65, "bh": 1.95, "tone": Color("#8ED4F7")},
	{"key": "donut", "file": "d5_donut", "name": "Donut", "shape": "circle", "friction": 0.05, "tone": Color("#FF8FB6")},
	{"key": "pie", "file": "d6_pie", "name": "Cherry pie", "shape": "circle", "tone": Color("#F0C073")},
	{"key": "cake", "file": "d7_cake", "name": "Strawberry cake", "shape": "rect", "bw": 2.1, "bh": 1.5, "tone": Color("#B97748")},
	{"key": "wedding", "file": "d8_wedding", "name": "Wedding cake", "shape": "rect", "bw": 1.6, "bh": 2.0, "tone": Color("#FFFFFF")},
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

## Collision shapes (body-local, game pixels) that follow the drawn art, so
## resting desserts visibly touch. Built once per tier from the sprite's own
## silhouette (Art.dessert_outline):
## - round art (circle tiers whose outline stays within CIRCLE_TOL of round)
##   gets a CircleShape2D of the art's mean radius, so it still rolls;
## - anything else is cut into horizontal bands, each replaced by its convex
##   hull. A band grows downwards while the art's left/right edge stays within
##   BAND_DEV px of the hull, so a convex dessert is one hull and a layered one
##   (cupcake frosting over its liner, the stepped wedding cake) gets one hull
##   per layer instead of a hull that bridges the notches between layers.
const CIRCLE_TOL := 1.08     # max/min reach of the outline
const BAND_DEV := 0.75       # px the art's edge may sit inside a band's hull
const BAND_STEP := 2         # rows added per growth step (1 row = 1 px)
const MAX_BANDS := 24

static var _shapes: Dictionary = {}

static func shapes(i: int) -> Array[Shape2D]:
	if _shapes.has(i):
		return _shapes[i]
	var out: Array[Shape2D] = []
	var outline := Art.dessert_outline(i, radius(i))
	var reach := PackedFloat32Array()
	for k in 72:
		reach.append(_reach(outline, Vector2.from_angle(k * TAU / 72.0)))
	var lo: float = Array(reach).min()
	var hi: float = Array(reach).max()
	if is_circle(i) and hi / lo <= CIRCLE_TOL:
		var c := CircleShape2D.new()
		var sum := 0.0
		for m in reach:
			sum += m
		c.radius = sum / reach.size()
		out.append(c)
	else:
		for hull in _bands(outline):
			var poly := ConvexPolygonShape2D.new()
			poly.points = hull
			out.append(poly)
	_shapes[i] = out
	return out

static func _reach(pts: PackedVector2Array, dir: Vector2) -> float:
	var m := -INF
	for p in pts:
		m = maxf(m, p.dot(dir))
	return m

## Convex hulls of horizontal slices of `outline`, top to bottom.
static func _bands(outline: PackedVector2Array) -> Array[PackedVector2Array]:
	# left/right edge of the art on every pixel row
	var spans: Array[PackedVector2Array] = []
	var y := -_reach(outline, Vector2.UP) + 0.5
	var bottom := _reach(outline, Vector2.DOWN)
	while y < bottom:
		var xl := INF
		var xr := -INF
		var line := PackedVector2Array([Vector2(-1e5, y), Vector2(1e5, y)])
		for seg in Geometry2D.intersect_polyline_with_polygon(line, outline):
			for p in seg:
				xl = minf(xl, p.x)
				xr = maxf(xr, p.x)
		if xl < xr:
			spans.append(PackedVector2Array([Vector2(xl, y), Vector2(xr, y)]))
		y += 1.0
	# the very top and bottom of the art fall between rows; keep them in the end bands
	var last := spans.size() - 1
	var caps := PackedVector2Array()
	for p in outline:
		if p.y < spans[0][0].y or p.y > spans[last][0].y:
			caps.append(p)
	spans[0].append_array(_filter_y(caps, -INF, spans[0][0].y))
	spans[last].append_array(_filter_y(caps, spans[last][0].y, INF))
	var bands: Array[PackedVector2Array] = []
	var i0 := 0
	while i0 < spans.size() - 1:
		var i1 := mini(i0 + BAND_STEP, spans.size() - 1)
		var hull := _span_hull(spans, i0, i1)
		while i1 < spans.size() - 1 and bands.size() < MAX_BANDS - 1:
			var i2 := mini(i1 + BAND_STEP, spans.size() - 1)
			var next := _span_hull(spans, i0, i2)
			if _span_dev(spans, i0, i2, next) > BAND_DEV:
				break
			hull = next
			i1 = i2
		if bands.size() == MAX_BANDS - 1:
			i1 = spans.size() - 1
			hull = _span_hull(spans, i0, i1)
		bands.append(hull)
		i0 = i1   # neighbouring bands share a row, so no slit between them
	return bands

static func _filter_y(pts: PackedVector2Array, lo: float, hi: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		if p.y >= lo and p.y <= hi:
			out.append(p)
	return out

static func _span_hull(spans: Array[PackedVector2Array], i0: int, i1: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in range(i0, i1 + 1):
		pts.append_array(spans[k])
	var hull := Geometry2D.convex_hull(pts)
	hull.remove_at(hull.size() - 1)   # convex_hull repeats the first point
	return hull

## How far the art's edge sits inside the hull, worst row.
static func _span_dev(spans: Array[PackedVector2Array], i0: int, i1: int, hull: PackedVector2Array) -> float:
	var worst := 0.0
	for k in range(i0, i1 + 1):
		for p in spans[k]:
			var d := INF
			for e in hull.size():
				var c := Geometry2D.get_closest_point_to_segment(p, hull[e], hull[(e + 1) % hull.size()])
				d = minf(d, p.distance_to(c))
			worst = maxf(worst, d)
	return worst
