class_name Ui
## Shared fonts, colors and styles for the HUD.

const INK := Color("#4A2618")
const MUTED := Color("#7A5648")
const ACCENT := Color("#E8427F")
const ACCENT_DARK := Color("#A81F58")
const SURFACE := Color("#FFF9F2")
const LINE := Color("#F1DCCB")
const EDGE := Color("#E6CBB4")
const ON_WOOD := Color("#FFF3E2")
const GOLD_INK := Color("#A86B00")

static var _fonts: Dictionary = {}

## Fredoka at a given weight (variable font).
static func font(weight: int = 600) -> Font:
	if _fonts.has(weight):
		return _fonts[weight]
	var f := FontVariation.new()
	f.base_font = load("res://assets/fonts/Fredoka.ttf")
	f.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	_fonts[weight] = f
	return f

static func title_font() -> Font:
	return load("res://assets/fonts/LilitaOne.ttf")

static func card(bg: Color = SURFACE, radius: int = 28, lip: int = 6) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	# a thin warm edge with a thicker bottom lip, like the chunky buttons
	s.border_color = EDGE
	s.set_border_width_all(2)
	s.border_width_bottom = 2 + lip
	s.shadow_color = Color(0.2, 0.08, 0.04, 0.2)
	s.shadow_size = 12
	s.shadow_offset = Vector2(0, 5)
	s.anti_aliasing = true
	return s

static func label(text: String, size: int, color: Color = INK, weight: int = 600) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

static func pill_button(text: String, bg: Color, fg: Color, lip_color: Color, size: int = 30) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", font(700))
	b.add_theme_font_size_override("font_size", size)
	for st: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(st, fg)
	var normal := StyleBoxFlat.new()
	normal.bg_color = bg
	normal.set_corner_radius_all(999)
	normal.border_width_bottom = 8
	normal.border_color = lip_color
	normal.content_margin_left = 44
	normal.content_margin_right = 44
	normal.content_margin_top = 14
	normal.content_margin_bottom = 20
	normal.anti_aliasing = true
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.border_width_bottom = 3
	pressed.content_margin_top = 19
	pressed.content_margin_bottom = 15
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = bg.lightened(0.08)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(func() -> void: Sfx.play("tap"))
	return b
