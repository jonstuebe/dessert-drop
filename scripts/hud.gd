class_name Hud
extends CanvasLayer
## All on-screen UI: header, dessert ladder, footer perks, toasts and dialogs.
## Layout is in the 720x1480 stage space; `place()` keeps it lined up with the stage.

signal perk_pressed(kind: String)
signal cancel_pressed
signal again_pressed
signal share_pressed
signal sheet_toggled(open: bool)

const PERKS := {
	"pop": {"cost": 1, "name": "Pop", "ring": Color("#E8427F"), "lip": Color("#A81F58"),
		"text": "Tap Pop, then tap any dessert to remove it from the jar."},
	"sweep": {"cost": 2, "name": "Sweep", "ring": Color("#3F9FE0"), "lip": Color("#1F68AC"),
		"text": "Clears every dessert of the smallest kind in the jar, all at once."},
	"upgrade": {"cost": 3, "name": "Upgrade", "ring": Color("#4CBF45"), "lip": Color("#1F7A2A"),
		"text": "Tap Upgrade, then tap a dessert to turn it into the next one up. It can't be used on a wedding cake, and a dessert made this way doesn't pay coins."},
}

## iOS-style share glyph: an open box with an arrow leaving the top.
const SHARE_ICON := """<svg xmlns="http://www.w3.org/2000/svg" width="40" height="48" viewBox="0 0 40 48">
<g fill="none" stroke="#4A2618" stroke-width="4.5" stroke-linecap="round" stroke-linejoin="round">
<path d="M13 19H8a3 3 0 0 0-3 3v20a3 3 0 0 0 3 3h24a3 3 0 0 0 3-3V22a3 3 0 0 0-3-3h-5"/>
<path d="M20 30V4M11 12l9-9 9 9"/></g></svg>"""

var stage_ui: Control
var full_ui: Control
var danger: ColorRect

var _score_label: Label
var _best_label: Label
var _shown_score := 0
var _score_tween: Tween
var _ladder: Array[TextureRect] = []
var _ladder_glow: TextureRect
var _next_tex: TextureRect
var _coins_btn: Button
var _coins_label: Label
var _perk_btns: Dictionary = {}
var _target: PanelContainer
var _target_label: Label
var _toast: PanelContainer
var _toast_icon: TextureRect
var _toast_title: Label
var _toast_sub: Label
var _toast_tween: Tween
var _over: Control
var _over_img: TextureRect
var _over_rays: TextureRect
var _over_top: Label
var _over_score: Label
var _over_best: Label
var _over_share: Button
var _sheet: Control
var _sheet_panel: PanelContainer
var _sheet_coins: Label

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	full_ui = Control.new()
	full_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	full_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(full_ui)

	danger = ColorRect.new()
	danger.set_anchors_preset(Control.PRESET_FULL_RECT)
	danger.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	sm.shader = load("res://scripts/vignette.gdshader")
	danger.material = sm
	danger.modulate.a = 0.0
	full_ui.add_child(danger)

	stage_ui = Control.new()
	stage_ui.size = Vector2(720, 1480)
	stage_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	full_ui.add_child(stage_ui)

	_build_header()
	_build_ladder()
	_build_footer()
	_build_target()
	_build_toast()
	_build_over()
	_build_sheet()

func place(offset: Vector2) -> void:
	stage_ui.position = offset

# ---------- header ----------
func _build_header() -> void:
	var logo := Control.new()
	logo.position = Vector2(30, 14)
	logo.rotation = deg_to_rad(-4.0)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage_ui.add_child(logo)
	# sticker-style lettering: dark outline, pink inner outline, then a soft colour fade
	var words := [["Dessert", 60, Vector2(0, 6), Color("#FFFFFF"), Color("#FFC4D9")],
		["Drop", 94, Vector2(36, 50), Color("#FFF6AE"), Color("#FFA83D")]]
	for layer in 3:
		for w: Array in words:
			var l := Label.new()
			l.text = w[0]
			l.add_theme_font_override("font", Ui.title_font())
			l.add_theme_font_size_override("font_size", w[1])
			l.position = w[2]
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var size: float = w[1]
			if layer == 0:
				l.add_theme_color_override("font_color", Color("#7C1440"))
				l.add_theme_color_override("font_outline_color", Color("#7C1440"))
				l.add_theme_constant_override("outline_size", 26)
				l.add_theme_color_override("font_shadow_color", Color("#4E0A28"))
				l.add_theme_constant_override("shadow_offset_y", 7)
				l.add_theme_constant_override("shadow_outline_size", 26)
			elif layer == 1:
				l.add_theme_color_override("font_color", Ui.ACCENT)
				l.add_theme_color_override("font_outline_color", Ui.ACCENT)
				l.add_theme_constant_override("outline_size", 11)
			else:
				var sm := ShaderMaterial.new()
				sm.shader = load("res://scripts/text_gradient.gdshader")
				sm.set_shader_parameter("top", w[3])
				sm.set_shader_parameter("bottom", w[4])
				sm.set_shader_parameter("y0", size * 0.45)
				sm.set_shader_parameter("y1", size * 1.0)
				l.material = sm
			logo.add_child(l)
	var k := 0
	for sp: Array in [[Vector2(226, 26), 34.0], [Vector2(6, 128), 22.0], [Vector2(214, 136), 18.0]]:
		var star := TextureRect.new()
		star.texture = Art.shape("star", Fx.STAR_SVG, 1.0)
		star.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		star.size = Vector2.ONE * (sp[1] as float)
		star.position = (sp[0] as Vector2) - star.size / 2
		star.pivot_offset = star.size / 2
		star.mouse_filter = Control.MOUSE_FILTER_IGNORE
		logo.add_child(star)
		var tw := star.create_tween().set_loops()
		tw.tween_interval(0.5 * k)
		tw.tween_property(star, "scale", Vector2.ONE * 0.45, 0.7).set_trans(Tween.TRANS_SINE)
		tw.tween_property(star, "scale", Vector2.ONE, 0.7).set_trans(Tween.TRANS_SINE)
		tw.tween_interval(1.2 - 0.5 * k)
		k += 1
	_score_label = _score_card("Score", Vector2(452, 30))
	_best_label = _score_card("Best", Vector2(588, 30))
	set_best(Save.best)

func _score_card(caption: String, pos: Vector2) -> Label:
	var p := PanelContainer.new()
	var st := Ui.card(Ui.SURFACE, 24, 5)
	st.content_margin_top = 6
	st.content_margin_bottom = 4
	p.add_theme_stylebox_override("panel", st)
	p.position = pos
	p.custom_minimum_size = Vector2(112, 0)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -8)
	var cap := Ui.label(caption, 20, Ui.MUTED, 600)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var num := Ui.label("0", 40, Ui.INK, 700)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(cap)
	v.add_child(num)
	p.add_child(v)
	stage_ui.add_child(p)
	return num

func set_score(n: int) -> void:
	if _score_tween:
		_score_tween.kill()
	_score_tween = create_tween()
	_score_tween.tween_method(func(v: int) -> void:
		_shown_score = v
		_score_label.text = str(v), _shown_score, n, 0.35)
	_bump(_score_label.get_parent().get_parent() as Control, 1.08)

func set_best(n: int) -> void:
	_best_label.text = str(n)

# ---------- ladder ----------
func _build_ladder() -> void:
	var shelf := TextureRect.new()
	shelf.texture = Art.svg("shelf", Art.SS)
	shelf.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shelf.size = Vector2(700, 64)
	shelf.position = Vector2(10, 220)
	shelf.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage_ui.add_child(shelf)   # desserts stand on its top face, so it goes underneath
	_ladder_glow = TextureRect.new()
	_ladder_glow.texture = Art.shape("puff", Fx.PUFF_SVG, 1.0)
	_ladder_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_ladder_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ladder_glow.modulate = Color(1, 1, 0.92, 0.0)
	stage_ui.add_child(_ladder_glow)
	var max_h := Tiers.size(Tiers.TOP).y
	var widths: Array[float] = []
	var heights: Array[float] = []
	var total := 0.0
	for i in Tiers.count():
		var sz := Tiers.size(i)
		# true to the jar: heights keep the same ratios as the bodies themselves
		var h := 90.0 * sz.y / max_h
		var w := h * sz.x / sz.y
		heights.append(h)
		widths.append(w)
		total += w
	var gap := 10.0
	var fit := minf(1.0, (660.0 - gap * 8) / total)
	var x := 360.0 - (total * fit + gap * 8) / 2.0
	for i in Tiers.count():
		var w := widths[i] * fit
		var h := heights[i] * fit
		var tr := TextureRect.new()
		# the art has a 10-unit pad around the body; size the rect to include it
		var info := Tiers.info(i)
		var body := Tiers.size(i) / Tiers.radius(i) * Tiers.ART_R
		var pad := Vector2(w, h) * Vector2(20, 20) / body
		tr.texture = Art.dessert(i, h / 2.0 / (body.y / Tiers.ART_R / 2.0) * 1.0)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.size = Vector2(w, h) + pad
		tr.position = Vector2(x - pad.x / 2, 228 - h - pad.y / 2)
		tr.pivot_offset = Vector2(tr.size.x / 2, tr.size.y - pad.y / 2)
		tr.tooltip_text = info["name"]
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stage_ui.add_child(tr)
		_ladder.append(tr)
		x += w + gap
	set_ladder(-1)

func set_ladder(top: int) -> void:
	for i in _ladder.size():
		var locked := i > Save.reached
		_ladder[i].modulate = Color(0.2, 0.12, 0.1, 0.28) if locked else Color.WHITE
	if top >= 0:
		var t := _ladder[top]
		_ladder_glow.size = t.size * 1.5
		_ladder_glow.position = t.position + t.size / 2 - _ladder_glow.size / 2
		_ladder_glow.modulate.a = 0.95
	else:
		_ladder_glow.modulate.a = 0.0

func ladder_pop(i: int) -> void:
	var t := _ladder[i]
	var tw := t.create_tween()
	tw.tween_property(t, "scale", Vector2(1.3, 1.3), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(t, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

## Center of a ladder slot in stage space (for effects).
func ladder_pos(i: int) -> Vector2:
	return _ladder[i].position + _ladder[i].size / 2

# ---------- footer ----------
func _build_footer() -> void:
	var plate := TextureRect.new()
	plate.texture = Art.svg("plate", 120.0 / 80.0 * Art.SS)
	plate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	plate.size = Vector2(120, 120)
	plate.position = Vector2(84 - 60, 1374 - 60)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage_ui.add_child(plate)
	_next_tex = TextureRect.new()
	_next_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_next_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_next_tex.size = Vector2(92, 92)
	_next_tex.position = Vector2(84 - 46, 1370 - 46)
	_next_tex.pivot_offset = Vector2(46, 46)
	_next_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage_ui.add_child(_next_tex)
	var up := Ui.label("Up next", 22, Ui.ON_WOOD, 600)
	up.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	up.add_theme_constant_override("shadow_offset_y", 2)
	up.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	up.size = Vector2(140, 30)
	up.position = Vector2(84 - 70, 1436)
	stage_ui.add_child(up)

	_coins_btn = Button.new()
	var pill := StyleBoxFlat.new()
	pill.bg_color = Color(0.16, 0.07, 0.02, 0.55)
	pill.set_corner_radius_all(999)
	pill.anti_aliasing = true
	for st: String in ["normal", "hover", "pressed"]:
		_coins_btn.add_theme_stylebox_override(st, pill)
	_coins_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_coins_btn.position = Vector2(170, 1347)
	_coins_btn.size = Vector2(120, 56)
	_coins_btn.pivot_offset = Vector2(60, 28)
	var coin_img := TextureRect.new()
	coin_img.texture = Art.icon("coin", 50)
	coin_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin_img.size = Vector2(50, 50)
	coin_img.position = Vector2(3, 3)
	coin_img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coins_btn.add_child(coin_img)
	_coins_label = Ui.label("0", 32, Color("#FFE9A6"), 700)
	_coins_label.position = Vector2(58, 4)
	_coins_label.size = Vector2(56, 46)
	_coins_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_coins_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_coins_btn.add_child(_coins_label)
	_coins_btn.pressed.connect(open_sheet)
	stage_ui.add_child(_coins_btn)

	var x := 306.0
	for kind: String in PERKS:
		var p: Dictionary = PERKS[kind]
		var b := PerkButton.new()
		b.ring_color = p["ring"]
		b.lip_color = p["lip"]
		b.cost = p["cost"]
		b.icon_tex = Art.icon("perk_" + kind, 60)
		b.size = Vector2(92, 92)
		b.position = Vector2(x, 1328)
		b.pivot_offset = Vector2(46, 46)
		b.tooltip_text = p["name"]
		b.pressed.connect(func() -> void:
			Sfx.play("tap")
			perk_pressed.emit(kind))
		stage_ui.add_child(b)
		_perk_btns[kind] = b
		x += 104.0
	var info := Ui.pill_button("?", Color(0.16, 0.07, 0.02, 0.55), Color("#FFE9A6"), Color(0, 0, 0, 0), 26)
	for st: String in ["normal", "hover", "pressed"]:
		var sb := (info.get_theme_stylebox(st) as StyleBoxFlat).duplicate() as StyleBoxFlat
		sb.content_margin_left = 16
		sb.content_margin_right = 16
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		sb.border_width_bottom = 0
		info.add_theme_stylebox_override(st, sb)
	info.position = Vector2(624, 1350)
	info.pressed.connect(open_sheet)
	stage_ui.add_child(info)
	set_coins(false)

func set_next(i: int) -> void:
	_next_tex.texture = Art.dessert(i, 46.0 * Tiers.radius(i) / maxf(Tiers.size(i).x, Tiers.size(i).y) * 2.0)
	_next_tex.scale = Vector2(0.4, 0.4)
	var tw := _next_tex.create_tween()
	tw.tween_property(_next_tex, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func set_coins(bump: bool) -> void:
	_coins_label.text = str(Save.coins)
	if _sheet_coins:
		_sheet_coins.text = "Coins carry over between games. You have %d." % Save.coins
	for kind: String in _perk_btns:
		(_perk_btns[kind] as PerkButton).cant = Save.coins < int(PERKS[kind]["cost"])
	if bump:
		_bump(_coins_btn, 1.25)

## Where flying coins should land, in stage space.
func coin_target() -> Vector2:
	return _coins_btn.position + Vector2(30, 29)

func _bump(c: Control, amount: float) -> void:
	c.pivot_offset = c.size / 2
	var tw := c.create_tween()
	tw.tween_property(c, "scale", Vector2.ONE * amount, 0.1)
	tw.tween_property(c, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

# ---------- perk targeting ----------
func _build_target() -> void:
	_target = PanelContainer.new()
	var st := Ui.card(Ui.SURFACE, 999, 6)
	st.content_margin_left = 26
	st.content_margin_right = 8
	st.content_margin_top = 8
	st.content_margin_bottom = 8
	_target.add_theme_stylebox_override("panel", st)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	_target_label = Ui.label("", 26, Ui.INK, 600)
	_target_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var cancel := Ui.pill_button("Cancel", Ui.LINE, Ui.INK, Color("#D9BFA9"), 24)
	cancel.pressed.connect(func() -> void: cancel_pressed.emit())
	h.add_child(_target_label)
	h.add_child(cancel)
	_target.add_child(h)
	_target.visible = false
	stage_ui.add_child(_target)

func target(kind: String) -> void:
	for k: String in _perk_btns:
		(_perk_btns[k] as PerkButton).active = k == kind
	_target.visible = kind != ""
	if kind != "":
		_target_label.text = "Tap a dessert to pop it" if kind == "pop" else "Tap a dessert to upgrade it"
		_target.reset_size()
		_target.position = Vector2(360 - _target.size.x / 2, 268)

func nope(kind: String) -> void:
	var b: PerkButton = _perk_btns[kind]
	var x := b.position.x
	var tw := b.create_tween()
	for d: float in [-8.0, 8.0, -5.0, 0.0]:
		tw.tween_property(b, "position:x", x + d, 0.06)
	var cost: int = PERKS[kind]["cost"]
	toast(Art.icon("perk_" + kind, 72), "%s costs %d coin%s" % [PERKS[kind]["name"], cost, "s" if cost > 1 else ""],
		"You need %d more. A strawberry cake pays 2." % (cost - Save.coins))
	Sfx.play("nope")

# ---------- toast ----------
func _build_toast() -> void:
	_toast = PanelContainer.new()
	var st := Ui.card(Ui.SURFACE, 30, 6)
	st.content_margin_left = 14
	st.content_margin_right = 28
	st.content_margin_top = 10
	st.content_margin_bottom = 10
	_toast.add_theme_stylebox_override("panel", st)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	_toast_icon = TextureRect.new()
	_toast_icon.custom_minimum_size = Vector2(76, 76)
	_toast_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_toast_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", -2)
	_toast_title = Ui.label("", 28, Ui.INK, 700)
	_toast_sub = Ui.label("", 21, Ui.MUTED, 500)
	# no autowrap: a wrapping label reports a huge minimum height to reset_size()
	v.add_child(_toast_title)
	v.add_child(_toast_sub)
	h.add_child(_toast_icon)
	h.add_child(v)
	_toast.add_child(h)
	_toast.modulate.a = 0.0
	stage_ui.add_child(_toast)

func toast(tex: Texture2D, title: String, sub: String) -> void:
	_toast_icon.texture = tex
	_toast_title.text = title
	_toast_sub.text = sub
	_toast.reset_size()
	_toast.size.x = minf(_toast.size.x, 660)
	_toast.position = Vector2(360 - _toast.size.x / 2, 112)
	if _toast_tween:
		_toast_tween.kill()
	_toast.modulate.a = 0.0
	_toast.position.y = 92
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast, "modulate:a", 1.0, 0.25)
	_toast_tween.parallel().tween_property(_toast, "position:y", 124.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_toast_tween.tween_interval(2.6)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.3)

func dessert_icon(i: int) -> Texture2D:
	return Art.dessert(i, 38.0 * Tiers.radius(i) / maxf(Tiers.size(i).x, Tiers.size(i).y) * 2.0)

# ---------- dialogs ----------
func _dim() -> ColorRect:
	var d := ColorRect.new()
	d.color = Color(0.04, 0.14, 0.16, 0.55)
	d.set_anchors_preset(Control.PRESET_FULL_RECT)
	d.visible = false
	full_ui.add_child(d)
	return d

func _build_over() -> void:
	_over = _dim()
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_over.add_child(center)
	var panel := PanelContainer.new()
	var st := Ui.card(Ui.SURFACE, 44, 10)
	st.content_margin_left = 40
	st.content_margin_right = 40
	st.content_margin_top = 0
	st.content_margin_bottom = 44
	panel.add_theme_stylebox_override("panel", st)
	panel.custom_minimum_size = Vector2(540, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	panel.add_child(v)

	# pink icing running down from the top of the card, with the title on it
	var head := Control.new()
	head.custom_minimum_size = Vector2(0, 136)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(head)
	var icing := TextureRect.new()
	icing.texture = Art.svg("icing", Art.SS)
	icing.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icing.size = Vector2(540, 150)
	icing.position = Vector2(-40, 0)
	icing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(icing)
	var title := Label.new()
	title.text = "The jar is full!"
	title.add_theme_font_override("font", Ui.title_font())
	title.add_theme_font_size_override("font_size", 50)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.add_theme_color_override("font_outline_color", Ui.ACCENT_DARK)
	title.add_theme_constant_override("outline_size", 12)
	title.add_theme_color_override("font_shadow_color", Color("#7C1440"))
	title.add_theme_constant_override("shadow_offset_y", 4)
	title.add_theme_constant_override("shadow_outline_size", 12)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(460, 70)
	title.position = Vector2(0, 14)
	head.add_child(title)

	# the biggest dessert, presented on a plate with a slow sunburst behind it
	var trophy := Control.new()
	trophy.custom_minimum_size = Vector2(0, 196)
	trophy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(trophy)
	_over_rays = TextureRect.new()
	_over_rays.texture = Art.svg("rays", 3.0)
	_over_rays.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_over_rays.size = Vector2(330, 330)
	_over_rays.position = Vector2(230 - 165, 98 - 165)
	_over_rays.pivot_offset = Vector2(165, 165)
	_over_rays.modulate = Color("#FFD98A", 0.75)
	_over_rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	trophy.add_child(_over_rays)
	var plate := TextureRect.new()
	plate.texture = Art.svg("plate", 210.0 / 80.0 * Art.SS)
	plate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	plate.size = Vector2(210, 210)
	plate.position = Vector2(230 - 105, 104 - 105)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	trophy.add_child(plate)
	_over_img = TextureRect.new()
	_over_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_over_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_over_img.size = Vector2(150, 150)
	_over_img.position = Vector2(230 - 75, 98 - 75)
	_over_img.pivot_offset = Vector2(75, 75)
	_over_img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	trophy.add_child(_over_img)

	var chip := PanelContainer.new()
	var cst := StyleBoxFlat.new()
	cst.bg_color = Ui.LINE
	cst.set_corner_radius_all(999)
	cst.content_margin_left = 22
	cst.content_margin_right = 22
	cst.content_margin_top = 4
	cst.content_margin_bottom = 6
	cst.anti_aliasing = true
	chip.add_theme_stylebox_override("panel", cst)
	chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_over_top = Ui.label("", 24, Ui.MUTED, 600)
	chip.add_child(_over_top)
	v.add_child(chip)

	_over_score = Ui.label("0", 108, Ui.INK, 700)
	_over_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_over_score.add_theme_color_override("font_shadow_color", Color("#E6CBB4"))
	_over_score.add_theme_constant_override("shadow_offset_y", 5)
	v.add_child(_over_score)
	var cap := Ui.label("points", 22, Ui.MUTED, 600)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var cap_wrap := MarginContainer.new()
	cap_wrap.add_theme_constant_override("margin_top", -22)
	cap_wrap.add_child(cap)
	v.add_child(cap_wrap)
	_over_best = Ui.label("", 26, Ui.MUTED, 600)
	_over_best.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_over_best)
	var again := Ui.pill_button("Play again", Ui.ACCENT, Color.WHITE, Ui.ACCENT_DARK, 30)
	again.pressed.connect(func() -> void: again_pressed.emit())
	# a white secondary pill, so Play again stays the main action
	_over_share = Ui.pill_button("Share", Color.WHITE, Ui.INK, Ui.EDGE, 30)
	_over_share.icon = Art.shape("share", SHARE_ICON, 0.62)
	_over_share.add_theme_constant_override("h_separation", 12)
	_over_share.add_theme_constant_override("icon_max_width", 26)
	_over_share.custom_minimum_size.x = 236  # fits "Copied!" too, so the card never jumps
	for k: String in ["normal", "hover", "pressed"]:
		var b := (_over_share.get_theme_stylebox(k) as StyleBoxFlat).duplicate() as StyleBoxFlat
		b.border_width_left = 2
		b.border_width_right = 2
		b.border_width_top = 2
		_over_share.add_theme_stylebox_override(k, b)
	_over_share.pressed.connect(func() -> void: share_pressed.emit())
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 14)
	v.add_child(spacer)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	buttons.add_child(_over_share)
	buttons.add_child(again)
	v.add_child(buttons)

## Brief "Copied!" on the Share button, for browsers with no share sheet.
func share_copied() -> void:
	_over_share.text = "Copied!"
	get_tree().create_timer(1.8).timeout.connect(func() -> void: _over_share.text = "Share")

func show_game_over(score: int, new_best: bool, top: int) -> void:
	_over_img.texture = Art.dessert(top, 75.0 * Tiers.radius(top) / maxf(Tiers.size(top).x, Tiers.size(top).y) * 2.0)
	_over_top.text = "Biggest dessert: " + Tiers.display_name(top)
	_over_best.text = "★  New best score!  ★" if new_best else "Best: %d" % Save.best
	_over_best.add_theme_color_override("font_color", Ui.ACCENT if new_best else Ui.MUTED)
	_over.visible = true
	_over.modulate.a = 0.0
	var panel := _over.get_child(0).get_child(0) as Control
	panel.pivot_offset = panel.size / 2
	panel.scale = Vector2(0.7, 0.7)
	var tw := create_tween().set_parallel()
	tw.tween_property(_over, "modulate:a", 1.0, 0.25)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(n: int) -> void: _over_score.text = str(n), 0, score, 0.9).set_delay(0.2)
	_over_img.scale = Vector2.ZERO
	tw.tween_property(_over_img, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.25)
	var spin := _over_rays.create_tween().set_loops()
	spin.tween_property(_over_rays, "rotation", TAU, 24.0).from(0.0)
	var bob := _over_img.create_tween().set_loops()
	bob.tween_interval(0.8)
	bob.tween_property(_over_img, "position:y", 98.0 - 75.0 - 7.0, 1.0).set_trans(Tween.TRANS_SINE)
	bob.tween_property(_over_img, "position:y", 98.0 - 75.0, 1.0).set_trans(Tween.TRANS_SINE)

func _build_sheet() -> void:
	_sheet = _dim()
	_sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	_sheet.gui_input.connect(func(e: InputEvent) -> void:
		var mb := e as InputEventMouseButton
		if mb and mb.pressed and not _sheet_panel.get_global_rect().has_point(mb.global_position):
			close_sheet())
	_sheet_panel = PanelContainer.new()
	var st := Ui.card(Ui.SURFACE, 48, 0)
	st.corner_radius_bottom_left = 0
	st.corner_radius_bottom_right = 0
	st.content_margin_left = 36
	st.content_margin_right = 36
	st.content_margin_top = 34
	st.content_margin_bottom = 40
	# paint below the rect so a rubber-banded upward drag never shows a gap
	st.expand_margin_bottom = SHEET_RUBBER_MAX + 16.0
	_sheet_panel.add_theme_stylebox_override("panel", st)
	_sheet_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_sheet_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_sheet.add_child(_sheet_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_sheet_panel.add_child(v)
	var grab := Panel.new()
	var gst := StyleBoxFlat.new()
	gst.bg_color = Ui.EDGE
	gst.set_corner_radius_all(4)
	grab.add_theme_stylebox_override("panel", gst)
	grab.custom_minimum_size = Vector2(72, 7)
	grab.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(grab)
	var title := Label.new()
	title.text = "Perks"
	title.add_theme_font_override("font", Ui.title_font())
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", Ui.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var lead := Ui.label("Spend coins for a little help when the jar gets crowded.", 24, Ui.MUTED, 500)
	lead.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lead.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(lead)

	var earn := PanelContainer.new()
	var est := Ui.card(Ui.LINE, 28, 0)
	est.shadow_size = 0
	est.content_margin_left = 24
	est.content_margin_right = 24
	est.content_margin_top = 16
	est.content_margin_bottom = 16
	earn.add_theme_stylebox_override("panel", est)
	var ev := VBoxContainer.new()
	ev.add_child(Ui.label("How to earn coins", 26, Ui.INK, 700))
	for row: Array in [[7, "Bake a strawberry cake", 2], [8, "Bake a wedding cake", 5]]:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 14)
		var img := TextureRect.new()
		img.texture = dessert_icon(row[0])
		img.custom_minimum_size = Vector2(64, 64)
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var l := Ui.label(row[1], 26, Ui.INK, 600)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var amt := Ui.label("+%d" % row[2], 28, Ui.INK, 700)
		amt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var c := TextureRect.new()
		c.texture = Art.icon("coin", 36)
		c.custom_minimum_size = Vector2(36, 36)
		c.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(img); h.add_child(l); h.add_child(amt); h.add_child(c)
		ev.add_child(h)
	_sheet_coins = Ui.label("", 21, Ui.MUTED, 500)
	ev.add_child(_sheet_coins)
	earn.add_child(ev)
	v.add_child(earn)

	for kind: String in PERKS:
		var p: Dictionary = PERKS[kind]
		var row := PanelContainer.new()
		var rst := Ui.card(Color.WHITE, 28, 3)
		rst.shadow_size = 0
		rst.content_margin_left = 16
		rst.content_margin_right = 20
		rst.content_margin_top = 14
		rst.content_margin_bottom = 16
		row.add_theme_stylebox_override("panel", rst)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 16)
		row.add_child(h)
		# the same ringed badge as the button in the footer
		var badge := PerkButton.new()
		badge.ring_color = p["ring"]
		badge.lip_color = p["lip"]
		badge.cost = p["cost"]
		badge.icon_tex = Art.icon("perk_" + kind, 60)
		badge.custom_minimum_size = Vector2(92, 98)
		badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tv := VBoxContainer.new()
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.add_theme_constant_override("separation", 0)
		var name_row := HBoxContainer.new()
		name_row.add_theme_constant_override("separation", 8)
		var nm := Ui.label(p["name"], 28, p["lip"], 700)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_row.add_child(nm)
		var cost := Ui.label("%d" % p["cost"], 26, Ui.GOLD_INK, 700)
		name_row.add_child(cost)
		var cimg := TextureRect.new()
		cimg.texture = Art.icon("coin", 32)
		cimg.custom_minimum_size = Vector2(32, 32)
		cimg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		cimg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		name_row.add_child(cimg)
		tv.add_child(name_row)
		var d := Ui.label(p["text"], 22, Ui.MUTED, 500)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tv.add_child(d)
		h.add_child(badge)
		h.add_child(tv)
		v.add_child(row)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	v.add_child(gap)
	var ok := Ui.pill_button("Got it", Ui.ACCENT, Color.WHITE, Ui.ACCENT_DARK, 32)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok.pressed.connect(close_sheet)
	v.add_child(ok)

# ---------- sheet: open / close / drag-to-dismiss ----------
const SHEET_DRAG_THRESHOLD := 10.0 # px of movement before a press becomes a drag
const SHEET_CLOSE_FRACTION := 0.25 # of panel height
const SHEET_FLICK_SPEED := 900.0 # px/s downward
const SHEET_RUBBER := 0.3 # upward resistance past rest
const SHEET_RUBBER_MAX := 48.0
const SHEET_VELOCITY_WINDOW := 0.1 # s of motion samples used for flick speed

var _sheet_tween: Tween
var _sheet_closing := false
var _drag_kind := 0 # 0 none, 1 mouse, 2 touch (first source wins; emulated twins are ignored)
var _drag_active := false
var _drag_start_y := 0.0
var _drag_start := Vector2.ZERO
var _drag_base := 0.0 # panel offset from rest when the drag began
var _drag_samples: Array[Vector2] = [] # (y, seconds)

func _sheet_rest_y() -> float:
	return _sheet.size.y - _sheet_panel.size.y

func _sheet_panel_rect() -> Rect2:
	return _sheet_panel.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, _sheet_panel.size)

func _now() -> float:
	return Time.get_ticks_usec() / 1000000.0

func _input(event: InputEvent) -> void:
	if _sheet == null or not _sheet.visible or _sheet_closing:
		return
	var kind := 0
	var pos := Vector2.ZERO
	var is_press_event := false
	var pressed := false
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.index != 0:
			return
		kind = 2
		pos = t.position
		is_press_event = true
		pressed = t.pressed
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if sd.index != 0:
			return
		kind = 2
		pos = sd.position
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		kind = 1
		pos = mb.position
		is_press_event = true
		pressed = mb.pressed
	elif event is InputEventMouseMotion:
		kind = 1
		pos = (event as InputEventMouseMotion).position
	else:
		return
	if is_press_event:
		if pressed:
			if _drag_kind == 0 and _sheet_panel_rect().has_point(pos):
				_drag_kind = kind
				_drag_active = false
				_drag_start = pos
				_drag_samples.clear()
		elif kind == _drag_kind:
			_drag_release(pos)
	elif kind == _drag_kind:
		_drag_move(pos)

func _drag_move(pos: Vector2) -> void:
	if not _drag_active:
		var delta := pos - _drag_start
		if delta.length() < SHEET_DRAG_THRESHOLD:
			return
		if absf(delta.x) > absf(delta.y):
			_drag_kind = 0 # sideways gesture: not ours
			return
		_drag_active = true
		_drag_start_y = pos.y
		if _sheet_tween:
			_sheet_tween.kill()
		_sheet.modulate.a = 1.0
		_drag_base = _sheet_panel.position.y - _sheet_rest_y()
		_cancel_sheet_presses(_sheet_panel)
	var t := _now()
	_drag_samples.append(Vector2(pos.y, t))
	while _drag_samples.size() > 2 and t - _drag_samples[0].y > SHEET_VELOCITY_WINDOW:
		_drag_samples.remove_at(0)
	var off := _drag_base + pos.y - _drag_start_y
	if off < 0.0:
		off = maxf(off * SHEET_RUBBER, -SHEET_RUBBER_MAX)
	_set_sheet_offset(off)

func _drag_release(pos: Vector2) -> void:
	var was_active := _drag_active
	_reset_drag_state()
	if not was_active:
		return # a tap: leave it to the buttons / dim
	var t := _now()
	var v := 0.0
	# samples older than the window mean the finger paused: no flick
	for s: Vector2 in _drag_samples:
		if t - s.y <= SHEET_VELOCITY_WINDOW:
			v = (pos.y - s.x) / maxf(t - s.y, 0.016)
			break
	_drag_samples.clear()
	var off := _sheet_panel.position.y - _sheet_rest_y()
	if off > _sheet_panel.size.y * SHEET_CLOSE_FRACTION or v > SHEET_FLICK_SPEED:
		_animate_sheet_out(v)
	else:
		if _sheet_tween:
			_sheet_tween.kill()
		_sheet_tween = create_tween().set_parallel()
		_sheet_tween.tween_property(_sheet_panel, "position:y", _sheet_rest_y(), 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_sheet_tween.tween_property(_sheet, "self_modulate:a", 1.0, 0.22)

func _reset_drag_state() -> void:
	_drag_kind = 0
	_drag_active = false

func _set_sheet_offset(off: float) -> void:
	_sheet_panel.position.y = _sheet_rest_y() + off
	var h := maxf(_sheet_panel.size.y, 1.0)
	_sheet.self_modulate.a = 1.0 - clampf(off / h, 0.0, 1.0) * 0.8

# toggling disabled clears a button's press, so lifting the finger after a drag never clicks
func _cancel_sheet_presses(n: Node) -> void:
	for c: Node in n.get_children():
		var b := c as BaseButton
		if b and not b.disabled:
			b.disabled = true
			b.disabled = false
		_cancel_sheet_presses(c)

func open_sheet() -> void:
	if _sheet.visible and not _sheet_closing:
		return
	Sfx.play("tap")
	set_coins(false)
	var was_closing := _sheet_closing
	_sheet_closing = false
	_reset_drag_state()
	if _sheet_tween:
		_sheet_tween.kill()
	_sheet.visible = true
	_sheet.self_modulate.a = 1.0
	if was_closing:
		# reopened mid-close: sheet_toggled(false) never fired, so just slide back
		_sheet_tween = create_tween().set_parallel()
		_sheet_tween.tween_property(_sheet, "modulate:a", 1.0, 0.2)
		_sheet_tween.tween_property(_sheet_panel, "position:y", _sheet_rest_y(), 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		return
	_sheet.modulate.a = 0.0
	sheet_toggled.emit(true)
	await get_tree().process_frame
	if not _sheet.visible or _sheet_closing or _drag_active:
		return
	# rest is derived from layout, never from the panel's current (possibly animated) position
	var y := _sheet_rest_y()
	_sheet_panel.position.y = y + 200
	_sheet_tween = create_tween().set_parallel()
	_sheet_tween.tween_property(_sheet, "modulate:a", 1.0, 0.2)
	_sheet_tween.tween_property(_sheet_panel, "position:y", y, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func close_sheet() -> void:
	if not _sheet.visible or _sheet_closing:
		return
	_animate_sheet_out(0.0)

# slide the panel off-screen and fade the dim, then hide; speed > 0 carries a flick's momentum
func _animate_sheet_out(speed: float) -> void:
	_sheet_closing = true
	_reset_drag_state()
	if _sheet_tween:
		_sheet_tween.kill()
	var target := _sheet.size.y + 24.0
	var dist := maxf(target - _sheet_panel.position.y, 0.0)
	var dur := 0.26
	var ease_kind := Tween.EASE_IN
	if speed > 0.0:
		dur = clampf(dist / speed, 0.12, 0.26)
		ease_kind = Tween.EASE_OUT
	_sheet_tween = create_tween().set_parallel()
	_sheet_tween.tween_property(_sheet_panel, "position:y", target, dur).set_trans(Tween.TRANS_CUBIC).set_ease(ease_kind)
	_sheet_tween.tween_property(_sheet, "self_modulate:a", 0.0, dur)
	_sheet_tween.chain().tween_callback(_finish_close_sheet)

func _finish_close_sheet() -> void:
	_sheet_closing = false
	_sheet.visible = false
	_sheet.self_modulate.a = 1.0
	sheet_toggled.emit(false)

func sheet_open() -> bool:
	return _sheet.visible
