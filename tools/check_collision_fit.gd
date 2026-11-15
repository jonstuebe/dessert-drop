# Checks that every dessert's collision shape matches its drawn art, so resting
# desserts visibly touch instead of floating apart.
#
#   godot --headless --path . --fixed-fps 120 res://tools/check_collision_fit.tscn
#
# (A scene rather than --script so the Save/Sfx autoloads exist.)
#
# 1. Static fit: for each tier, compares the support distance (how far the shape
#    reaches in a direction) of the real collision shapes built by Dessert.setup()
#    with that of the visible art silhouette (SVG rasterised on its own here at
#    8x, alpha >= 0.5, so soft drop shadows don't count) in 72 directions.
# 2. Settle test: spawns pairs of desserts side by side in a V-shaped trough and
#    stacked in a narrow well, runs the physics until they rest, then measures
#    the distance between their visible outlines in game pixels.
# Exits 1 if any settled pair shows a visible gap or overlap beyond tolerance.
extends Node

const K := 8.0                 # silhouette raster scale (px per design unit)
const ALPHA := 0.5             # alpha threshold for "visible"
# game px allowed between visible outlines. Round-ish tiers (cookie) keep a
# circle so they roll; their art is ~±1.5 px out of round at SCALE 2.0, so a
# contact can show up to ~2 px at some angles.
const MAX_GAP := 2.0
const MAX_OVERLAP := 2.0       # game px of visible overlap allowed
const SETTLE_FRAMES := 480     # 4 s at 120 Hz

var _art: Dictionary = {}      # tier -> PackedVector2Array outline, design units
var _fail := false


func _ready() -> void:
	Engine.physics_ticks_per_second = 120
	_run.call_deferred()


func _run() -> void:
	print("== Static fit (game px; + means shape reaches past the art, - means short of it)")
	print("tier  name              R      L(shape/art)   R(shape/art)   T(shape/art)   B(shape/art)   worst dir   shapes")
	for t in Tiers.count():
		_static_fit(t)

	print("\n== Settle test (gap between visible outlines, game px; negative = overlap)")
	var side_pairs := [[1, 1], [2, 2], [3, 3], [4, 4], [6, 6], [7, 7], [1, 8], [3, 4], [4, 7], [0, 5], [2, 8], [1, 3], [0, 4]]
	for p in side_pairs:
		await _settle_side(p[0], p[1])
	var stack_pairs := [[3, 3], [7, 7], [4, 3], [0, 3], [1, 7], [3, 7], [2, 4]]
	for p in stack_pairs:
		await _settle_stack(p[0], p[1])

	if _fail:
		print("\nFAIL: visible gaps/overlaps beyond tolerance")
		get_tree().quit(1)
	else:
		print("\nPASS: all settled pairs touch visually (|gap| <= %.1f px)" % MAX_GAP)
		get_tree().quit(0)


# ---------------------------------------------------------------- silhouettes

## Visible outline of the tier's art in design units (ART_R = 30), centred like the sprite.
func _art_outline(t: int) -> PackedVector2Array:
	if _art.has(t):
		return _art[t]
	var text := FileAccess.get_file_as_string("res://assets/art/%s.svg" % Tiers.info(t)["file"])
	var img := Image.new()
	img.load_svg_from_string(text, K)
	img.convert(Image.FORMAT_RGBA8)
	var bm := BitMap.new()
	bm.create_from_image_alpha(img, ALPHA)
	var best := PackedVector2Array()
	var best_a := 0.0
	for poly: PackedVector2Array in bm.opaque_to_polygons(Rect2i(Vector2i.ZERO, img.get_size()), 0.5):
		var a := absf(_area(poly))
		if a > best_a:
			best_a = a
			best = poly
	var half := Vector2(img.get_size()) / 2.0
	var out := PackedVector2Array()
	for p in best:
		out.append((p - half) / K)
	_art[t] = out
	return out


## Art outline in game px, local to the body.
func _art_local(t: int) -> PackedVector2Array:
	var s := Tiers.radius(t) / Tiers.ART_R
	var out := PackedVector2Array()
	for p in _art_outline(t):
		out.append(p * s)
	return out


func _area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		a += poly[i].cross(poly[(i + 1) % poly.size()])
	return a / 2.0


func _support_pts(pts: PackedVector2Array, dir: Vector2) -> float:
	var m := -INF
	for p in pts:
		m = maxf(m, p.dot(dir))
	return m


## Support distance of all the body's collision shapes in a direction (body-local).
func _support_body(body: Node2D, dir: Vector2) -> float:
	var m := -INF
	for c in body.get_children():
		var cs := c as CollisionShape2D
		if cs == null:
			continue
		var xf := cs.transform
		var ld := xf.basis_xform_inv(dir).normalized()
		if cs.shape is CircleShape2D:
			m = maxf(m, xf.origin.dot(dir) + (cs.shape as CircleShape2D).radius)
		elif cs.shape is ConvexPolygonShape2D:
			m = maxf(m, xf.origin.dot(dir) + _support_pts((cs.shape as ConvexPolygonShape2D).points, ld))
		elif cs.shape is RectangleShape2D:
			var h := (cs.shape as RectangleShape2D).size / 2.0
			m = maxf(m, xf.origin.dot(dir) + absf(ld.x) * h.x + absf(ld.y) * h.y)
	return m


func _make(t: int) -> Dessert:
	var d := Dessert.new()
	d.setup(t)
	return d


func _static_fit(t: int) -> void:
	var d := _make(t)
	var art := _art_local(t)
	var cols := []
	for dir in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		cols.append("%6.1f/%6.1f" % [_support_body(d, dir), _support_pts(art, dir)])
	var worst := 0.0
	var worst_deg := 0
	for k in 72:
		var dir := Vector2.from_angle(k * TAU / 72.0)
		var diff := _support_body(d, dir) - _support_pts(art, dir)
		if absf(diff) > absf(worst):
			worst = diff
			worst_deg = k * 5
	var kinds := {}
	for c in d.get_children():
		if c is CollisionShape2D:
			var n: String = (c as CollisionShape2D).shape.get_class().trim_suffix("Shape2D")
			kinds[n] = kinds.get(n, 0) + 1
	print("%d     %-16s %5.1f   %s   %s   %s   %s   %+5.1f @%3d°   %s" % [t, Tiers.info(t)["key"], Tiers.radius(t), cols[0], cols[1], cols[2], cols[3], worst, worst_deg, kinds])
	d.free()


# ---------------------------------------------------------------- settle test

func _static_body(segments: Array) -> StaticBody2D:
	var sb := StaticBody2D.new()
	for seg in segments:
		var cs := CollisionShape2D.new()
		var s := SegmentShape2D.new()
		s.a = seg[0]
		s.b = seg[1]
		cs.shape = s
		sb.add_child(cs)
	var mat := PhysicsMaterial.new()
	mat.friction = 0.2
	sb.physics_material_override = mat
	return sb


func _wait(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _gap(a: Dessert, b: Dessert) -> float:
	var pa := a.global_transform * _art_local(a.tier)
	var pb := b.global_transform * _art_local(b.tier)
	var overlap := Geometry2D.intersect_polygons(pa, pb)
	if not overlap.is_empty():
		# Overlap depth: every vertex of an overlap region lies on one outline;
		# its distance to the other outline is how deep it sits inside it.
		# (Avoids is_point_in_polygon, which misfires on these dense outlines.)
		var depth := 0.0
		for region: PackedVector2Array in overlap:
			for v in region:
				depth = maxf(depth, maxf(_dist_to_poly(v, pa), _dist_to_poly(v, pb)))
		return -depth
	var m := INF
	for v in pa:
		m = minf(m, _dist_to_poly(v, pb))
	for v in pb:
		m = minf(m, _dist_to_poly(v, pa))
	return m


func _dist_to_poly(v: Vector2, poly: PackedVector2Array) -> float:
	var m := INF
	for i in poly.size():
		var c := Geometry2D.get_closest_point_to_segment(v, poly[i], poly[(i + 1) % poly.size()])
		m = minf(m, v.distance_to(c))
	return m


func _report(kind: String, a: Dessert, b: Dessert) -> void:
	var g := _gap(a, b)
	var moving := a.linear_velocity.length() > 5.0 or b.linear_velocity.length() > 5.0
	var ok := g <= MAX_GAP and g >= -MAX_OVERLAP
	if not ok:
		_fail = true
	print("%-5s %-9s + %-9s gap %+6.2f px   rot %+5.1f°/%+5.1f°%s  %s" % [kind,
		Tiers.info(a.tier)["key"], Tiers.info(b.tier)["key"], g,
		rad_to_deg(wrapf(a.rotation, -PI, PI)), rad_to_deg(wrapf(b.rotation, -PI, PI)),
		"  (still moving)" if moving else "", "ok" if ok else "FAIL"])


func _settle_side(ta: int, tb: int) -> void:
	var world := Node2D.new()
	get_tree().root.add_child(world)
	# shallow V trough: both desserts slide to the middle and press together
	var slope := tan(deg_to_rad(14.0))
	world.add_child(_static_body([[Vector2(-600, -600 * slope), Vector2(0, 0)], [Vector2(0, 0), Vector2(600, -600 * slope)]]))
	var a := _make(ta)
	var b := _make(tb)
	a.position = Vector2(-Tiers.size(ta).x / 2 - 30, -Tiers.size(ta).y / 2 - 40)
	b.position = Vector2(Tiers.size(tb).x / 2 + 30, -Tiers.size(tb).y / 2 - 40)
	world.add_child(a)
	world.add_child(b)
	await _wait(SETTLE_FRAMES)
	_report("side", a, b)
	world.queue_free()
	await _wait(2)


func _settle_stack(top: int, bottom: int) -> void:
	var world := Node2D.new()
	get_tree().root.add_child(world)
	var w := maxf(Tiers.size(top).x, Tiers.size(bottom).x) / 2.0 + 6.0
	world.add_child(_static_body([[Vector2(-w, -800), Vector2(-w, 0)], [Vector2(-w, 0), Vector2(w, 0)], [Vector2(w, 0), Vector2(w, -800)]]))
	var b := _make(bottom)
	b.position = Vector2(0, -Tiers.size(bottom).y / 2 - 4)
	world.add_child(b)
	var a := _make(top)
	a.position = Vector2(0, -Tiers.size(bottom).y - Tiers.size(top).y / 2 - 30)
	world.add_child(a)
	await _wait(SETTLE_FRAMES)
	_report("stack", a, b)
	world.queue_free()
	await _wait(2)
