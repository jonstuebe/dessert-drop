class_name Fx
extends Node2D
## Juice: flashes, puffs, crumbs, rings, confetti, stars, glows, floating text and coin flights.

const CONFETTI := [Color("#FF6B8A"), Color("#5BC0EB"), Color("#FDE74C"), Color("#9BC53D"), Color("#C084FC"), Color("#FFFFFF")]
const PUFF_SVG := "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 64 64'><defs><radialGradient id='g'><stop offset='0' stop-color='#fff'/><stop offset='.5' stop-color='#fff' stop-opacity='.6'/><stop offset='1' stop-color='#fff' stop-opacity='0'/></radialGradient></defs><circle cx='32' cy='32' r='32' fill='url(#g)'/></svg>"
const SPRINKLE_SVG := "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 12 30'><rect x='1' y='1' width='10' height='28' rx='5' fill='#fff'/></svg>"
const STAR_SVG := "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 40 40'><path d='M20 0Q20 20 40 20Q20 20 20 40Q20 20 0 20Q20 20 20 0Z' fill='#fff'/></svg>"
const CRUMB_SVG := "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'><path d='M4 9L10 2L18 4L22 12L17 21L8 22L2 16Z' fill='#fff'/><path d='M4 9L10 2L18 4L12 10Z' fill='#fff'/><path d='M8 22L17 21L22 12L13 15Z' fill='#000' opacity='.18'/></svg>"
const SHARD_SVG := "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'><path d='M3 20L9 3L21 9L15 22Z' fill='#fff'/><path d='M15 22L21 9L13 13Z' fill='#000' opacity='.22'/></svg>"
const DROP_SVG := "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'><circle cx='12' cy='12' r='10' fill='#fff'/><path d='M12 22A10 10 0 0 0 22 12A12 12 0 0 1 12 22Z' fill='#000' opacity='.2'/><ellipse cx='8.5' cy='8' rx='3' ry='2' fill='#fff'/></svg>"
const PETAL_SVG := "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 30'><path d='M12 1C22 9 22 22 12 29C2 22 2 9 12 1Z' fill='#fff'/><path d='M12 29C22 22 22 9 12 1C16 10 16 20 12 29Z' fill='#000' opacity='.14'/></svg>"

## What flies out when each dessert is baked: [particle shape, colors].
const BITS := [
	["sprinkle", ["#FF8FB1", "#FFFFFF", "#FFC9DB", "#FFD23F"]],
	["shard", ["#96572F", "#6A3517", "#C9895A"]],
	["crumb", ["#EBB467", "#FCE2AA", "#CF8C3C", "#5A2A12"]],
	["crumb", ["#CBB5F7", "#F3EBFF", "#FBEBCB", "#9E7EE2"]],
	["sprinkle", ["#FF5C8A", "#3FB6E8", "#FFD23F", "#7ED957", "#FFE6EF"]],
	["sprinkle", ["#FFFFFF", "#3FB6E8", "#FFD23F", "#7ED957", "#FF8FB6"]],
	["drop", ["#E12643", "#F0C073", "#B8152F", "#FFE8B6"]],
	["crumb", ["#96572F", "#FFE6EE", "#E5283F", "#C2814F", "#FFFFFF"]],
	["petal", ["#FFFFFF", "#F7A8C2", "#FFD3E1", "#F1C75B"]],
]

var font: Font
var _add: CanvasItemMaterial

func _ready() -> void:
	add_to_group("fx")
	font = Ui.font(700)
	_add = CanvasItemMaterial.new()
	_add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_motes()

func _tex(name: String) -> Texture2D:
	match name:
		"puff": return Art.shape("puff", PUFF_SVG, 1.0)
		"sprinkle": return Art.shape("sprinkle", SPRINKLE_SVG, 1.2)
		"crumb": return Art.shape("crumb", CRUMB_SVG, 1.0)
		"shard": return Art.shape("shard", SHARD_SVG, 1.0)
		"drop": return Art.shape("drop", DROP_SVG, 1.0)
		"petal": return Art.shape("petal", PETAL_SVG, 1.0)
		_: return Art.shape("star", STAR_SVG, 1.0)

func _burst(pos: Vector2, tex: String, amount: int, life: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = _tex(tex)
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = maxi(amount, 1)
	p.lifetime = life
	p.position = pos
	p.gravity = Vector2.ZERO
	p.spread = 180.0
	p.finished.connect(p.queue_free)
	add_child(p)
	return p

## Slow specks of flour drifting through the window light.
func _motes() -> void:
	var p := CPUParticles2D.new()
	p.texture = _tex("puff")
	p.amount = 16
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(330, 520)
	p.position = Vector2(340, 700)
	p.direction = Vector2(0.5, -1)
	p.spread = 40.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 5.0
	p.initial_velocity_max = 16.0
	p.scale_amount_min = 0.07
	p.scale_amount_max = 0.2
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.25, 0.75, 1.0])
	g.colors = PackedColorArray([Color(1, 0.98, 0.88, 0), Color(1, 0.98, 0.88, 0.7), Color(1, 0.98, 0.88, 0.7), Color(1, 0.98, 0.88, 0)])
	p.color_ramp = g
	p.z_index = -1
	add_child(p)

func puff(pos: Vector2, color: Color, amount: int) -> void:
	var p := _burst(pos, "puff", amount, 0.55)
	p.initial_velocity_min = 40.0
	p.initial_velocity_max = 190.0
	p.damping_min = 120.0
	p.damping_max = 200.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	p.scale_amount_curve = _curve(1.0, 0.0)
	p.color = color
	p.color_ramp = _fade()
	p.emitting = true

## Everything a normal merge needs, matched to the dessert that was just baked.
func merge(pos: Vector2, tier: int) -> void:
	var r := Tiers.radius(tier)
	var tone := Tiers.tone(tier)
	flash(pos, r * 1.25)
	puff(pos, tone.lightened(0.25), 6 + tier * 2)
	crumbs(pos, tier, 8 + tier * 2)
	ring(pos, tone.lightened(0.45), r)
	sugar(pos, r, 5 + tier)

## A quick bright pop with a spinning burst of rays behind it.
func flash(pos: Vector2, radius: float) -> void:
	var s := Sprite2D.new()
	s.texture = _tex("puff")
	s.material = _add
	s.position = pos
	s.modulate = Color(1.0, 0.97, 0.86, 0.85)
	s.scale = Vector2.ONE * radius * 0.7 / 32.0
	add_child(s)
	var tw := s.create_tween().set_parallel()
	tw.tween_property(s, "scale", Vector2.ONE * radius * 2.1 / 32.0, 0.24).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(s, "modulate:a", 0.0, 0.24).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(s.queue_free)
	var rays := Sprite2D.new()
	rays.texture = Art.svg("rays", 2.0)
	rays.position = pos
	rays.rotation = randf() * TAU
	rays.modulate = Color(1.0, 0.98, 0.9, 0.75)
	rays.scale = Vector2.ONE * radius * 1.2 / 200.0
	add_child(rays)
	var tr := rays.create_tween().set_parallel()
	tr.tween_property(rays, "scale", Vector2.ONE * radius * 3.4 / 200.0, 0.42).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tr.tween_property(rays, "rotation", rays.rotation + 0.7, 0.42)
	tr.tween_property(rays, "modulate:a", 0.0, 0.42).set_ease(Tween.EASE_IN)
	tr.chain().tween_callback(rays.queue_free)

## Crumbs, sprinkles, glaze drops or petals: whatever the dessert is made of.
func crumbs(pos: Vector2, tier: int, amount: int) -> void:
	var bits: Array = BITS[clampi(tier, 0, BITS.size() - 1)]
	var p := _burst(pos, bits[0], amount, 0.95)
	var r := Tiers.radius(tier)
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = r * 0.45
	p.direction = Vector2.UP
	p.spread = 150.0
	p.gravity = Vector2(0, 1300)
	p.initial_velocity_min = 160.0 + r
	p.initial_velocity_max = 380.0 + r * 2.0
	p.angular_velocity_min = -620.0
	p.angular_velocity_max = 620.0
	p.angle_min = 0.0
	p.angle_max = 360.0
	var k := 0.3 + tier * 0.035
	p.scale_amount_min = k * 0.7
	p.scale_amount_max = k * 1.5
	var cols: Array = bits[1]
	var g := Gradient.new()
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	var offs := PackedFloat32Array()
	var colors := PackedColorArray()
	for i in cols.size():
		offs.append(float(i) / cols.size())
		colors.append(Color(cols[i] as String))
	g.offsets = offs
	g.colors = colors
	p.color_initial_ramp = g
	p.color_ramp = _fade(0.75)
	p.emitting = true

## Fine sugar glints that twinkle outward.
func sugar(pos: Vector2, radius: float, amount: int) -> void:
	var p := _burst(pos, "star", amount, 0.6)
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius * 0.8
	p.initial_velocity_min = 30.0
	p.initial_velocity_max = 150.0
	p.damping_min = 80.0
	p.damping_max = 160.0
	p.scale_amount_min = 0.22
	p.scale_amount_max = 0.55
	p.scale_amount_curve = _bell()
	p.color = Color(1, 1, 1, 0.95)
	p.emitting = true

## A little cloud of flour where something lands hard.
func dust(pos: Vector2, strength: float) -> void:
	var p := _burst(pos, "puff", 3 + int(strength * 5.0), 0.4)
	p.direction = Vector2.UP
	p.spread = 85.0
	p.initial_velocity_min = 40.0
	p.initial_velocity_max = 110.0 + strength * 90.0
	p.damping_min = 160.0
	p.damping_max = 260.0
	p.scale_amount_min = 0.22
	p.scale_amount_max = 0.5 + strength * 0.25
	p.scale_amount_curve = _curve(0.6, 1.3)
	p.color = Color(1, 1, 1, 0.55)
	p.color_ramp = _fade(0.1)
	p.emitting = true

func confetti(pos: Vector2, amount: int) -> void:
	var p := _burst(pos, "sprinkle", amount, 1.2)
	p.direction = Vector2.UP
	p.spread = 75.0
	p.gravity = Vector2(0, 900)
	p.initial_velocity_min = 260.0
	p.initial_velocity_max = 560.0
	p.angular_velocity_min = -540.0
	p.angular_velocity_max = 540.0
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 0.8
	var g := Gradient.new()
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	var offs := PackedFloat32Array()
	for i in CONFETTI.size():
		offs.append(float(i) / CONFETTI.size())
	g.offsets = offs
	g.colors = PackedColorArray(CONFETTI)
	p.color_initial_ramp = g
	p.color_ramp = _fade(0.7)
	p.emitting = true

func stars(pos: Vector2, amount: int) -> void:
	var p := _burst(pos, "star", amount, 0.8)
	p.initial_velocity_min = 90.0
	p.initial_velocity_max = 300.0
	p.damping_min = 150.0
	p.damping_max = 250.0
	p.angular_velocity_min = -120.0
	p.angular_velocity_max = 120.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	p.scale_amount_curve = _curve(1.0, 0.0)
	p.color = Color("#FFF1B0")
	p.emitting = true

func glow(pos: Vector2, size: float) -> void:
	var s := Sprite2D.new()
	s.texture = _tex("puff")
	s.position = pos
	s.modulate = Color("#FFE7A0", 0.9)
	s.scale = Vector2.ONE * size / 32.0
	add_child(s)
	var tw := s.create_tween().set_parallel()
	tw.tween_property(s, "scale", Vector2.ONE * size * 2.2 / 32.0, 0.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(s, "modulate:a", 0.0, 0.7)
	tw.chain().tween_callback(s.queue_free)

## A shockwave: a thick ring that thins as it spreads, with a fainter echo behind it.
func ring(pos: Vector2, color: Color, radius: float) -> void:
	for k in 2:
		var r := Ring.new()
		r.position = pos
		r.color = color if k == 0 else Color(1, 1, 1, 0.7)
		r.radius = radius * (0.9 if k == 0 else 0.6)
		r.width = 10.0 if k == 0 else 5.0
		add_child(r)
		var t := 0.42 + k * 0.14
		var tw := r.create_tween().set_parallel()
		tw.tween_property(r, "radius", radius * (1.9 if k == 0 else 1.55), t).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(r, "width", 1.0, t).set_ease(Tween.EASE_OUT)
		tw.tween_property(r, "modulate:a", 0.0, t).set_ease(Tween.EASE_IN)
		tw.chain().tween_callback(r.queue_free)

func float_text(pos: Vector2, text: String, size: int, outline: Color = Color("#C2365A")) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", outline)
	l.add_theme_constant_override("outline_size", maxi(8, size / 3))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.25))
	l.add_theme_constant_override("shadow_offset_y", 4)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(l)
	l.reset_size()
	l.pivot_offset = l.size / 2
	# keep it on screen even when the merge happens against a wall
	pos.x = clampf(pos.x, l.size.x / 2 + 12, 708 - l.size.x / 2)
	l.position = pos - l.size / 2
	l.scale = Vector2.ONE * 0.4
	l.rotation = randf_range(-0.07, 0.07)
	l.z_index = 20
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector2.ONE * 1.12, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "scale", Vector2.ONE, 0.12)
	tw.parallel().tween_property(l, "position:y", l.position.y - 90, 1.1).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.5).set_delay(0.6)
	tw.tween_callback(l.queue_free)

## Coins pop out of a dessert and fly to `target`.
func coins(pos: Vector2, n: int, target: Vector2, on_arrive: Callable) -> void:
	for k in n:
		var c := Sprite2D.new()
		c.texture = Art.icon("coin", 48)
		c.position = pos
		c.scale = Vector2.ONE * 0.1
		c.z_index = 25
		add_child(c)
		var spread := (k - (n - 1) / 2.0) * 40.0
		var tw := c.create_tween()
		tw.tween_interval(k * 0.07)
		tw.tween_property(c, "position", pos + Vector2(spread, -54), 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(c, "scale", Vector2.ONE / Art.SS, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_interval(0.3)
		tw.tween_property(c, "position", target, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(c, "scale", Vector2.ONE * 0.7 / Art.SS, 0.5)
		tw.tween_callback(func() -> void:
			Sfx.play("coin", 1.0 + k * 0.06, -6.0)
			sugar(target, 18.0, 4)
			on_arrive.call()
			c.queue_free())

func _curve(a: float, b: float) -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0, a))
	c.add_point(Vector2(1, b))
	return c

func _bell() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0, 0.2))
	c.add_point(Vector2(0.35, 1.0))
	c.add_point(Vector2(1, 0.0))
	return c

func _fade(hold: float = 0.3) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, hold, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)])
	return g


class Ring extends Node2D:
	var color := Color.WHITE
	var width := 8.0
	var radius := 40.0:
		set(v):
			radius = v
			queue_redraw()

	func _draw() -> void:
		draw_arc(Vector2.ZERO, radius, 0, TAU, 64, color, width, true)
