extends Node2D
## Dessert Drop: aim, drop, merge twins into the next dessert, don't overflow the jar.
## Everything gameplay-related lives in the 720x1480 "stage", centered in the window.

const STAGE := Vector2(720, 1480)
const JAR_L := 82.0
const JAR_R := 638.0
const JAR_TOP := 425.0
const JAR_BOTTOM := 1264.0
const LOSE_Y := 480.0
const DROP_Y := 340.0
const DROP_COOLDOWN := 0.42
const GRACE := 1.5          # seconds a new dessert may sit above the line
const OVERFLOW_TIME := 2.2  # seconds above the line before the game ends
const PX := 96.0            # prototype velocity unit (px per step) -> px/s in game space

@onready var hud: Hud = $Hud

var stage: Node2D
var desserts: Node2D
var fx: Fx
var preview: Sprite2D
var guide: Node2D
var danger_line: Node2D
var _wall: TextureRect
var _counter: Sprite2D
var _counter_fill: ColorRect

var score := 0
var top_tier := -1
var current := 0
var next := 0
var can_drop := true
var over := false
var new_best := false
var mode := ""             # "", "pop" or "upgrade" while targeting with a perk
var aim_x := 360.0
var danger := 0.0
var _merge_queue: Array = []
var _pressing := false
var _hint: Control
var _preview_bob: Tween
var _shake := 0.0

func _ready() -> void:
	randomize()
	_fit_window()
	_build_world()
	hud.perk_pressed.connect(_start_perk)
	hud.cancel_pressed.connect(_cancel_perk)
	hud.again_pressed.connect(func() -> void: get_tree().reload_current_scene())
	hud.share_pressed.connect(_share)
	hud.sheet_toggled.connect(func(open: bool) -> void:
		if open:
			_cancel_perk()
		get_tree().paused = open and not over)
	get_viewport().size_changed.connect(_layout)
	_layout()

	current = Tiers.random_drop()
	next = Tiers.random_drop()
	hud.set_next(next)
	hud.set_ladder(-1)
	_show_preview(false)
	_aim(360.0)
	if Save.first_run:
		Save.first_run = false
		get_tree().create_timer(0.9).timeout.connect(func() -> void:
			hud.toast(Art.icon("coin", 72), "A welcome gift: 3 coins", "Tap a perk below to spend them"))

## On desktop, open the window as tall as the screen allows (keeping the phone
## shape) instead of the small default size, and center it.
func _fit_window() -> void:
	if not OS.has_feature("pc") or DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		return
	var screen := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var h := int(usable.size.y * 0.9)
	var sz := Vector2i(int(h * STAGE.x / STAGE.y), h)
	DisplayServer.window_set_size(sz)
	DisplayServer.window_set_position(usable.position + (usable.size - sz) / 2)

# ---------- world ----------
func _build_world() -> void:
	var bg := CanvasLayer.new()
	bg.layer = -10
	add_child(bg)
	_wall = TextureRect.new()
	_wall.texture = Art.svg("bg_wall", Art.SS)
	_wall.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_wall.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_wall.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_child(_wall)

	stage = Node2D.new()
	add_child(stage)
	_counter_fill = ColorRect.new()
	_counter_fill.color = Color("#6A3D21")   # COUNTER_BASE in tools/gen_art.py
	stage.add_child(_counter_fill)
	_counter = Sprite2D.new()
	_counter.texture = Art.svg("counter", Art.SS)
	_counter.centered = false
	# the worktop starts 40 px above the jar floor; the SVG has 30 px of wall shade above that
	_counter.position = Vector2(0, JAR_BOTTOM - 70)
	stage.add_child(_counter)
	# props standing on the worktop, behind the glass
	stage.add_child(_sprite("prop_plant", Vector2(30 - 70, JAR_BOTTOM - 4 - 222)))
	stage.add_child(_sprite("prop_crock", Vector2(692 - 70, JAR_BOTTOM - 4 - 242)))

	stage.add_child(_sprite("jar_back", Vector2(JAR_L - 42, JAR_TOP - 50)))
	danger_line = DangerLine.new()
	danger_line.position = Vector2(0, LOSE_Y)
	(danger_line as DangerLine).x0 = JAR_L + 14
	(danger_line as DangerLine).x1 = JAR_R - 14
	stage.add_child(danger_line)
	guide = Guide.new()
	stage.add_child(guide)
	desserts = Node2D.new()
	stage.add_child(desserts)
	stage.add_child(_sprite("jar_front", Vector2(JAR_L - 42, JAR_TOP - 50)))

	preview = Sprite2D.new()
	preview.position = Vector2(360, DROP_Y)
	stage.add_child(preview)
	fx = Fx.new()
	fx.z_index = 10
	stage.add_child(fx)
	Dessert.floor_y = JAR_BOTTOM

	var walls := StaticBody2D.new()
	var wm := PhysicsMaterial.new()
	wm.friction = 0.25
	wm.bounce = 0.05
	walls.physics_material_override = wm
	var h := JAR_BOTTOM - 200.0
	_wall_shape(walls, Vector2(JAR_L - 40, 200 + h / 2), Vector2(80, h + 80))
	_wall_shape(walls, Vector2(JAR_R + 40, 200 + h / 2), Vector2(80, h + 80))
	_wall_shape(walls, Vector2(360, JAR_BOTTOM + 40), Vector2(JAR_R - JAR_L + 200, 80))
	stage.add_child(walls)

	# first-drop hint: a soft card, so it stays readable over any dessert
	var hint := PanelContainer.new()
	var hs := Ui.card(Color(1.0, 0.98, 0.95, 0.92), 30, 5)
	hs.content_margin_left = 30
	hs.content_margin_right = 30
	hs.content_margin_top = 16
	hs.content_margin_bottom = 20
	hint.add_theme_stylebox_override("panel", hs)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hl := Ui.label("Drop two of the same dessert\ntogether to bake the next one", 30, Ui.INK, 650)
	hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_child(hl)
	hint.z_index = 9
	stage.add_child(hint)
	hint.reset_size()
	hint.position = Vector2(360 - hint.size.x / 2, (JAR_TOP + JAR_BOTTOM) / 2 - 60)
	_hint = hint

func _sprite(file: String, pos: Vector2) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = Art.svg(file, Art.SS)
	s.scale = Vector2.ONE / Art.SS
	s.centered = false
	s.position = pos
	return s

func _wall_shape(body: StaticBody2D, pos: Vector2, sz: Vector2) -> void:
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = sz
	cs.shape = r
	cs.position = pos
	body.add_child(cs)

func _layout() -> void:
	var vs := get_viewport_rect().size
	var off := ((vs - STAGE) / 2.0).floor()
	stage.position = off
	hud.place(off)
	# stretch the counter across the full width and down to the bottom edge
	_counter.position.x = -off.x
	_counter.scale = Vector2(vs.x / STAGE.x, 1.0) / Art.SS
	_counter_fill.position = Vector2(-off.x, JAR_BOTTOM + 230)
	_counter_fill.size = Vector2(vs.x, maxf(0.0, vs.y - off.y - JAR_BOTTOM - 230) + 4)

# ---------- input ----------
func _unhandled_input(event: InputEvent) -> void:
	if over or get_tree().paused:
		return
	var mb := event as InputEventMouseButton
	if mb and mb.button_index == MOUSE_BUTTON_LEFT:
		var p := mb.position - stage.position
		if mb.pressed:
			if p.y < 250 or p.y > JAR_BOTTOM + 20:
				return
			_pressing = true
			if mode == "":
				_aim(p.x)
		elif _pressing:
			_pressing = false
			if mode != "":
				_use_perk_on(p)
			else:
				_aim(p.x)
				_drop()
		return
	var mm := event as InputEventMouseMotion
	if mm and mode == "":
		var p := mm.position - stage.position
		if _pressing or p.y > 250 and p.y < JAR_BOTTOM:
			_aim(p.x)
	if event.is_action_pressed("ui_cancel"):
		_cancel_perk()

func _aim(x: float) -> void:
	var half := Tiers.size(current).x / 2.0
	aim_x = clampf(x, JAR_L + half + 4, JAR_R - half - 4)
	preview.position.x = aim_x
	var g := guide as Guide
	g.visible = can_drop and not over and mode == ""
	g.x = aim_x
	g.y0 = DROP_Y + Tiers.size(current).y / 2.0 + 16
	g.y1 = JAR_BOTTOM - 10
	g.queue_redraw()

func _show_preview(animate: bool) -> void:
	preview.texture = Art.dessert(current, Tiers.radius(current))
	preview.visible = true
	var base := Vector2.ONE / Art.SS
	if _preview_bob:
		_preview_bob.kill()
	preview.position.y = DROP_Y
	if animate:
		preview.scale = base * 0.4
		create_tween().tween_property(preview, "scale", base, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		preview.scale = base
	_preview_bob = create_tween().set_loops()
	_preview_bob.tween_property(preview, "position:y", DROP_Y + 6, 0.9).set_trans(Tween.TRANS_SINE)
	_preview_bob.tween_property(preview, "position:y", DROP_Y, 0.9).set_trans(Tween.TRANS_SINE)

# ---------- dropping and merging ----------
func _drop() -> void:
	if not can_drop or over or mode != "":
		return
	var d := _spawn(current, Vector2(aim_x, DROP_Y), Vector2(randf_range(-0.3, 0.3) * PX, 2.5 * PX))
	d.angular_velocity = randf_range(-2.0, 2.0)
	Sfx.play("drop", randf_range(0.9, 1.1) * (1.15 - current * 0.08), -4.0)
	can_drop = false
	preview.visible = false
	guide.visible = false
	current = next
	next = Tiers.random_drop()
	hud.set_next(next)
	get_tree().create_timer(DROP_COOLDOWN, false).timeout.connect(func() -> void:
		if over:
			return
		can_drop = true
		if mode == "":
			_show_preview(true)
		_aim(aim_x))

func _spawn(tier: int, pos: Vector2, vel: Vector2 = Vector2.ZERO) -> Dessert:
	var d := Dessert.new()
	d.setup(tier)
	var half := Tiers.size(tier).x / 2.0
	pos.x = clampf(pos.x, JAR_L + half + 2, JAR_R - half - 2)
	d.position = pos
	d.linear_velocity = vel
	d.twin_touched.connect(func(a: Dessert, b: Dessert) -> void: _merge_queue.append([a, b]))
	desserts.add_child(d)
	if tier > top_tier:
		top_tier = tier
		hud.set_ladder(tier)
	return d

func _physics_process(delta: float) -> void:
	if over:
		return
	var q := _merge_queue
	_merge_queue = []
	for pair: Array in q:
		_merge(pair[0], pair[1])
	_check_overflow(delta)

func _merge(a: Dessert, b: Dessert) -> void:
	if not is_instance_valid(a) or not is_instance_valid(b) or a.is_queued_for_deletion() or b.is_queued_for_deletion():
		return
	var pos := (a.position + b.position) / 2.0
	var vel := (a.linear_velocity + b.linear_velocity) / 2.0
	var i := a.tier
	a.queue_free()
	b.queue_free()
	_wake_all()
	_clear_hint()

	if i == Tiers.TOP:
		_add_score(100)
		_celebrate(pos, Tiers.TOP, "Two wedding cakes!  +100")
		return
	var n := i + 1
	var pts := Tiers.points(n)
	_add_score(pts)
	var born := _spawn(n, pos, Vector2(vel.x * 0.5, minf(vel.y * 0.3, 0.0) - (2.5 + n * 0.25) * PX))
	born.angular_velocity = randf_range(-3.0, 3.0)
	born.appear()
	_bump(pos, Tiers.radius(n), born)
	hud.ladder_pop(n)
	Sfx.play("merge", 1.45 - n * 0.09)
	if Tiers.COIN_REWARD.has(n):
		_award_coins(Tiers.COIN_REWARD[n], pos - Vector2(0, Tiers.size(n).y / 2 + 30))
	if n >= 5:
		_celebrate(pos, n, "%s!  +%d" % [Tiers.display_name(n), pts])
	else:
		fx.merge(pos, n)
		fx.float_text(pos - Vector2(0, Tiers.size(n).y / 2), "+%d" % pts, 30 + n * 4)
	if n > Save.reached:
		Save.reached = n
		Save.write()
		hud.set_ladder(top_tier)
		hud.toast(hud.dessert_icon(n), "New dessert: " + Tiers.display_name(n),
			"You reached the top of the ladder!" if n == Tiers.TOP else "Next up: " + Tiers.display_name(n + 1))
		Sfx.play("fanfare", 1.0, -3.0)

## Push nearby desserts away from a merge so the new one has room.
func _bump(pos: Vector2, r: float, skip: Dessert) -> void:
	var reach := r * 2.4
	for d: Dessert in desserts.get_children():
		if d == skip or d.is_queued_for_deletion():
			continue
		var delta := d.position - pos
		var dist := delta.length()
		if dist > 0.0 and dist < reach:
			var f := 1.0 - dist / reach
			d.linear_velocity += delta / dist * f * 3.2 * PX + Vector2(0, -1.2 * f * PX)
			d.sleeping = false

## Freeing a body does not wake the sleeping desserts resting on it: they keep
## hovering until something else touches them (usually the next drop). Call this
## after removing or resizing a dessert. It wakes everything now and again on the
## next physics frame, once the queue_free()d bodies are really gone.
func _wake_all() -> void:
	_wake_now()
	if not get_tree().physics_frame.is_connected(_wake_now):
		get_tree().physics_frame.connect(_wake_now, CONNECT_ONE_SHOT)

func _wake_now() -> void:
	for d: Dessert in desserts.get_children():
		if not d.is_queued_for_deletion() and not d.freeze:
			d.sleeping = false

func _add_score(n: int) -> void:
	score += n
	hud.set_score(score)

func _celebrate(pos: Vector2, tier: int, text: String) -> void:
	fx.glow(pos, Tiers.radius(tier) * 1.4)
	fx.flash(pos, Tiers.radius(tier) * 1.5)
	fx.crumbs(pos, tier, 12 + tier * 2)
	fx.confetti(pos, 18 + tier * 4)
	fx.stars(pos, 10)
	fx.ring(pos, Color.WHITE, Tiers.radius(tier))
	fx.float_text(pos - Vector2(0, Tiers.size(tier).y / 2 + 10), text, 40)
	Sfx.play("chime", 1.2 - (tier - 5) * 0.08, -4.0)
	if tier >= 6:
		_shake = 10.0 + (tier - 6) * 4.0

func _clear_hint() -> void:
	if _hint:
		var h := _hint
		_hint = null
		var tw := h.create_tween()
		tw.tween_property(h, "modulate:a", 0.0, 0.4)
		tw.tween_callback(h.queue_free)

# ---------- coins and perks ----------
func _award_coins(n: int, pos: Vector2) -> void:
	Save.coins += n
	Save.write()
	var landed := [0]
	fx.coins(pos, n, hud.coin_target(), func() -> void:
		landed[0] += 1
		if landed[0] == 1:
			hud.set_coins(true))
	fx.float_text(pos - Vector2(0, 40), "+%d coins" % n, 34, Color("#A86B00"))
	if not Save.earned_once:
		Save.earned_once = true
		Save.write()
		hud.toast(Art.icon("coin", 72), "You earned coins!", "Spend them on the perks below")

func _spend(kind: String) -> void:
	Save.coins -= int(Hud.PERKS[kind]["cost"])
	Save.write()
	hud.set_coins(true)

func _live() -> Array[Dessert]:
	var out: Array[Dessert] = []
	for d: Dessert in desserts.get_children():
		if not d.merging and not d.is_queued_for_deletion():
			out.append(d)
	return out

func _start_perk(kind: String) -> void:
	if over:
		return
	if mode == kind:
		_cancel_perk()
		return
	_cancel_perk()
	if Save.coins < int(Hud.PERKS[kind]["cost"]):
		hud.nope(kind)
		return
	if kind == "sweep":
		_sweep()
		return
	var any := false
	for d in _live():
		if kind == "pop" or d.tier < Tiers.TOP:
			any = true
	if not any:
		hud.toast(Art.icon("perk_" + kind, 72), "Nothing to %s yet" % kind, "Drop some desserts first")
		return
	mode = kind
	preview.visible = false
	guide.visible = false
	hud.target(kind)
	queue_redraw()

func _cancel_perk() -> void:
	if mode == "":
		return
	mode = ""
	hud.target("")
	queue_redraw()
	if not over and can_drop:
		_show_preview(false)
		_aim(aim_x)

func _pick(p: Vector2) -> Dessert:
	var best: Dessert = null
	var bd := INF
	for d in _live():
		if mode == "upgrade" and d.tier == Tiers.TOP:
			continue
		var sz := Tiers.size(d.tier)
		var dist := d.position.distance_to(p)
		if dist < maxf(sz.x, sz.y) / 2.0 + 10.0 and dist < bd:
			bd = dist
			best = d
	return best

func _use_perk_on(p: Vector2) -> void:
	var kind := mode
	var d := _pick(p)
	if d == null:
		return
	var i := d.tier
	var pos := d.position
	d.queue_free()
	_spend(kind)
	_wake_all()
	_clear_hint()
	if kind == "pop":
		fx.puff(pos, Tiers.tone(i), 14)
		fx.flash(pos, Tiers.radius(i) * 1.2)
		fx.crumbs(pos, i, 14 + i * 2)
		fx.ring(pos, Color.WHITE, Tiers.radius(i))
		fx.float_text(pos - Vector2(0, Tiers.size(i).y / 2), "Pop!", 40)
		Sfx.play("pop")
	else:
		var n := i + 1
		var born := _spawn(n, pos, Vector2(0, -2 * PX))
		born.no_coins = true
		born.angular_velocity = randf_range(-2.0, 2.0)
		born.appear()
		_bump(pos, Tiers.radius(n), born)
		_celebrate(pos, n, Tiers.display_name(n) + "!")
		hud.ladder_pop(n)
		Sfx.play("upgrade")
		if n > Save.reached:
			Save.reached = n
			Save.write()
			hud.set_ladder(top_tier)
	_cancel_perk()
	can_drop = false
	preview.visible = false
	guide.visible = false
	get_tree().create_timer(0.35, false).timeout.connect(func() -> void:
		if over or mode != "":
			return
		can_drop = true
		_show_preview(false)
		_aim(aim_x))

func _sweep() -> void:
	var live := _live()
	if live.is_empty():
		hud.toast(Art.icon("perk_sweep", 72), "Nothing to sweep yet", "Drop some desserts first")
		return
	var low := Tiers.TOP
	for d in live:
		low = mini(low, d.tier)
	var list := live.filter(func(d: Dessert) -> bool: return d.tier == low)
	_spend("sweep")
	_clear_hint()
	Sfx.play("sweep")
	for k in list.size():
		var d: Dessert = list[k]
		d.merging = true
		get_tree().create_timer(k * 0.06, false).timeout.connect(func() -> void:
			if not is_instance_valid(d):
				return
			fx.puff(d.position, Tiers.tone(low), 8)
			fx.crumbs(d.position, low, 8)
			fx.ring(d.position, Color.WHITE, Tiers.radius(low))
			Sfx.play("merge", 1.6 + k * 0.03, -8.0)
			d.queue_free()
			_wake_all())
	var nm := Tiers.display_name(low).to_lower()
	fx.float_text(Vector2(360, JAR_TOP + 120), "Swept %d %s%s" % [list.size(), nm, "s" if list.size() > 1 else ""], 38, Color("#1F68AC"))

# ---------- overflow ----------
func _check_overflow(delta: float) -> void:
	var in_danger := false
	for d: Dessert in desserts.get_children():
		if d.is_queued_for_deletion():
			continue
		if d.position.y > STAGE.y + 200 or d.position.x < -200 or d.position.x > STAGE.x + 200:
			d.queue_free()
			continue
		if d.age() < GRACE or mode != "":
			d.over_time = 0.0
			continue
		var sz := Tiers.size(d.tier)
		var top := d.position.y - (absf(sz.x / 2 * sin(d.rotation)) + absf(sz.y / 2 * cos(d.rotation)))
		if Tiers.is_circle(d.tier):
			top = d.position.y - sz.y / 2
		if top < LOSE_Y and absf(d.linear_velocity.y) < 140.0:
			d.over_time += delta
			in_danger = true
			if d.over_time > OVERFLOW_TIME:
				_game_over()
				return
		else:
			d.over_time = 0.0
	danger = move_toward(danger, 1.0 if in_danger else 0.0, delta * 3.0)

func _process(delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	(danger_line as DangerLine).pulse = danger * (0.5 + 0.5 * sin(t * 11.0))
	hud.danger.modulate.a = danger * (0.55 + 0.45 * sin(t * 7.0))
	danger_line.queue_redraw()
	if _shake > 0.0:
		_shake = move_toward(_shake, 0.0, delta * 40.0)
		stage.position = ((get_viewport_rect().size - STAGE) / 2.0).floor() + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake
	if mode != "":
		queue_redraw()

## Pulsing target rings while a perk is waiting for a tap.
func _draw() -> void:
	if mode == "":
		return
	var t := Time.get_ticks_msec() / 1000.0
	var a := 0.6 + 0.35 * sin(t * 7.0)
	for d in _live():
		if mode == "upgrade" and d.tier == Tiers.TOP:
			continue
		var sz := Tiers.size(d.tier)
		draw_arc(stage.position + d.position, maxf(sz.x, sz.y) / 2.0 + 6.0, 0, TAU, 48, Color(1, 1, 1, a), 5.0, true)

func _game_over() -> void:
	over = true
	_cancel_perk()
	preview.visible = false
	guide.visible = false
	danger = 0.0
	hud.danger.modulate.a = 0.0
	for d: Dessert in desserts.get_children():
		d.freeze = true
	new_best = score > Save.best
	if new_best:
		Save.best = score
		Save.write()
		hud.set_best(score)
	Sfx.play("gameover")
	hud.show_game_over(score, new_best, maxi(top_tier, 0))

# ---------- sharing ----------
const SHARE_URL := "https://dessert-drop.jonstuebe.com/"
const SHARE_EMOJI: Array[String] = ["✨", "🍫", "🍪", "🟣", "🧁", "🍩", "🥧", "🍰", "🎂"]

func share_text() -> String:
	var top := maxi(top_tier, 0)
	var e := SHARE_EMOJI[top]
	var dessert := Tiers.display_name(top)
	if new_best:
		return "%s New high score in Dessert Drop: %s! I baked all the way up to a %s. Think you can beat it?" % [e, _commas(score), dessert]
	return "%s I scored %s in Dessert Drop and baked a %s. Think you can beat it?" % [e, _commas(score), dessert]

## Opens the share sheet where the browser has one; otherwise copies the message.
func _share() -> void:
	var text := share_text()
	if OS.has_feature("web"):
		var js := "(function(t,u){if(navigator.share){navigator.share({text:t,url:u}).catch(function(){});return true}return false})(%s,%s)" % [JSON.stringify(text), JSON.stringify(SHARE_URL)]
		if JavaScriptBridge.eval(js, true):
			return
	DisplayServer.clipboard_set(text + "\n" + SHARE_URL)
	hud.share_copied()

static func _commas(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out


class DangerLine extends Node2D:
	var x0 := 0.0
	var x1 := 0.0
	var pulse := 0.0

	func _draw() -> void:
		var col := Color("#E8427F").lerp(Color("#FF2050"), pulse)
		col.a = 0.5 + 0.5 * pulse
		var x := x0
		while x < x1:
			var e := minf(x + 18, x1)
			# pale underlay keeps the dashes readable over dark desserts
			draw_line(Vector2(x, 2.5), Vector2(e, 2.5), Color(1, 1, 1, 0.3 + 0.3 * pulse), 9.0, true)
			draw_line(Vector2(x, 0), Vector2(e, 0), col, 7.0, true)
			draw_circle(Vector2(x, 0), 3.5, col)
			draw_circle(Vector2(e, 0), 3.5, col)
			x += 32.0


class Guide extends Node2D:
	var x := 0.0
	var y0 := 0.0
	var y1 := 0.0

	func _draw() -> void:
		var y := y0
		var k := 0
		while y < y1:
			draw_circle(Vector2(x, y), 3.2, Color(1, 1, 1, 0.75 - 0.4 * (y - y0) / maxf(1.0, y1 - y0)))
			y += 24.0
			k += 1
