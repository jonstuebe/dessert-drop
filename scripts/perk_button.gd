class_name PerkButton
extends Button
## Round perk button: colored ring, icon, and a gold cost badge.

var ring_color := Color.WHITE
var lip_color := Color.GRAY
var icon_tex: Texture2D
var cost := 1
var active := false:
	set(v):
		active = v
		queue_redraw()
var cant := false:
	set(v):
		cant = v
		queue_redraw()

var _font: Font

func _ready() -> void:
	flat = true
	focus_mode = Control.FOCUS_NONE
	_font = Ui.font(700)
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)

func _draw() -> void:
	var r := size.x / 2.0 - 4.0
	var c := Vector2(size.x / 2.0, size.y / 2.0 - 3.0)
	var down := is_pressed() and not active
	if active:
		c.y -= 6.0
		draw_circle(c, r + 12.0, Color(1, 1, 1, 0.35))
		draw_circle(c, r + 6.0, Color.WHITE)
	if not down:
		draw_circle(c + Vector2(0, 6), r, lip_color.darkened(0.1) if not cant else Color(0.4, 0.38, 0.36))
	else:
		c.y += 4.0
	var ring := ring_color if not cant else Color(0.62, 0.6, 0.58)
	draw_circle(c, r, ring)
	draw_circle(c, r - 5.0, Color("#FFF6EA") if not cant else Color("#E2DCD6"))
	draw_circle(c + Vector2(-r * 0.2, -r * 0.25), r * 0.45, Color(1, 1, 1, 0.5))
	if icon_tex:
		var isz := Vector2.ONE * r * 1.55
		var mod := Color.WHITE if not cant else Color(0.75, 0.72, 0.7, 0.75)
		draw_texture_rect(icon_tex, Rect2(c - isz / 2, isz), false, mod)
	# cost badge
	var b := c + Vector2(r * 0.72, r * 0.72)
	draw_circle(b, 17.0, Color("#A86B00"))
	draw_circle(b, 14.0, Color("#FFD23F") if not cant else Color("#D8CDB0"))
	var t := str(cost)
	var ts := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_CENTER, -1, 20)
	draw_string(_font, b + Vector2(-ts.x / 2, 7), t, HORIZONTAL_ALIGNMENT_CENTER, -1, 20, Color("#6B4300"))
