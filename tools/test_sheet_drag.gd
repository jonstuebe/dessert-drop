extends SceneTree
## Headless test for the perks sheet's drag-to-dismiss.
## godot --headless --path . --script res://tools/test_sheet_drag.gd

var _fails := 0
var _hud: Node # untyped: hud.gd needs autoloads that do not exist when this script compiles

func _initialize() -> void:
	_run.call_deferred()
	# safety net: never hang CI
	create_timer(30.0, true).timeout.connect(func() -> void:
		print("FAIL  timed out")
		quit(2))

func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_fails += 1

func _wait(sec: float) -> void:
	await create_timer(sec, true).timeout

func _push(ev: InputEvent) -> void:
	root.push_input(ev, true)

func _mouse_motion(pos: Vector2, held: bool) -> void:
	var m := InputEventMouseMotion.new()
	m.position = pos
	m.global_position = pos
	m.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	_push(m)

func _mouse_button(pos: Vector2, pressed: bool) -> void:
	var b := InputEventMouseButton.new()
	b.button_index = MOUSE_BUTTON_LEFT
	b.position = pos
	b.global_position = pos
	b.pressed = pressed
	b.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	_push(b)

func _touch(pos: Vector2, pressed: bool) -> void:
	var t := InputEventScreenTouch.new()
	t.index = 0
	t.position = pos
	t.pressed = pressed
	_push(t)

func _touch_drag(pos: Vector2) -> void:
	var d := InputEventScreenDrag.new()
	d.index = 0
	d.position = pos
	_push(d)

## Mouse drag from `from` by `dy` in steps, one frame per step, optional pause before release.
func _mouse_drag(from: Vector2, dy: float, steps: int, pause: float) -> void:
	_mouse_motion(from, false)
	_mouse_button(from, true)
	await process_frame
	for i: int in steps:
		_mouse_motion(from + Vector2(0, dy * float(i + 1) / steps), true)
		await process_frame
	if pause > 0.0:
		await _wait(pause)
	_mouse_button(from + Vector2(0, dy), false)

func _rest() -> float:
	return float(_hud.call("_sheet_rest_y"))

func _rect() -> Rect2:
	return _hud.call("_sheet_panel_rect") as Rect2

func _panel() -> PanelContainer:
	return _hud.get("_sheet_panel") as PanelContainer

func _is_open() -> bool:
	return bool(_hud.call("sheet_open")) and not bool(_hud.get("_sheet_closing"))

func _open() -> void:
	_hud.call("open_sheet")
	await _wait(0.6)

func _grab_point() -> Vector2:
	# just under the grab-handle pill, away from any button
	var r := _rect()
	return Vector2(r.position.x + r.size.x * 0.5, r.position.y + 24.0)

func _find_ok(n: Node) -> Button:
	for c: Node in n.get_children():
		if c is Button and (c as Button).text == "Got it":
			return c as Button
		var f := _find_ok(c)
		if f:
			return f
	return null

func _run() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	_hud = main.get_node("Hud")
	await _wait(0.3)

	var toggles: Array[bool] = []
	_hud.connect("sheet_toggled", func(o: bool) -> void: toggles.append(o))

	# --- open ---
	await _open()
	_check(_is_open(), "sheet opens")
	var rest := _rest()
	_check(absf(_panel().position.y - rest) < 1.0, "panel at rest after open (y=%.1f rest=%.1f h=%.1f)" % [_panel().position.y, rest, _panel().size.y])

	# --- small drag springs back ---
	var g := _grab_point()
	_mouse_motion(g, false)
	_mouse_button(g, true)
	await process_frame
	for i: int in 4:
		_mouse_motion(g + Vector2(0, 15.0 * (i + 1)), true)
		await process_frame
	_check(absf(_panel().position.y - (rest + 45.0)) < 1.5, "panel follows finger 1:1 from drag start (offset %.1f, expected 45 = 60 moved - 15 activation step)" % (_panel().position.y - rest))
	await _wait(0.25)
	_mouse_button(g + Vector2(0, 60), false)
	await _wait(0.4)
	_check(_is_open(), "small drag: still open")
	_check(absf(_panel().position.y - rest) < 1.0, "small drag: sprang back to rest (y=%.1f)" % _panel().position.y)

	# --- upward drag rubber-bands and returns ---
	g = _grab_point()
	_mouse_motion(g, false)
	_mouse_button(g, true)
	await process_frame
	for i: int in 5:
		_mouse_motion(g - Vector2(0, 40.0 * (i + 1)), true)
		await process_frame
	var up := rest - _panel().position.y
	_check(up > 0.0 and up <= 48.0 + 0.5, "upward drag resists (lifted %.1f px for 200 px of finger)" % up)
	_mouse_button(g - Vector2(0, 200), false)
	await _wait(0.4)
	_check(_is_open() and absf(_panel().position.y - rest) < 1.0, "upward drag: back to rest")

	# --- tiny jitter on OK still clicks the button ---
	var ok := _find_ok(_panel())
	_check(ok != null, "found OK button")
	var c := ok.get_global_rect().get_center()
	_mouse_motion(c, false)
	_mouse_button(c, true)
	await process_frame
	_mouse_motion(c + Vector2(0, 5), true)
	await process_frame
	_check(absf(_panel().position.y - rest) < 0.5, "5px jitter does not move the panel")
	_mouse_button(c + Vector2(0, 5), false)
	await _wait(0.5)
	_check(not bool(_hud.call("sheet_open")), "tap on OK closes via button")
	_check(toggles.size() >= 2 and toggles[-1] == false, "sheet_toggled(false) emitted after close")

	# --- reopen: rest unchanged, no accumulated offset ---
	await _open()
	_check(_is_open() and absf(_panel().position.y - rest) < 1.0, "reopen after close lands at rest (y=%.1f)" % _panel().position.y)

	# --- drag that starts on OK does not click it ---
	c = ok.get_global_rect().get_center()
	await _mouse_drag(c, 60.0, 6, 0.25)
	await _wait(0.4)
	_check(_is_open(), "drag starting on OK button does not click it")
	_check(absf(_panel().position.y - rest) < 1.0, "...and springs back")

	# --- large slow drag closes ---
	var h := _panel().size.y
	await _mouse_drag(_grab_point(), h * 0.4, 12, 0.25)
	await process_frame
	_check(bool(_hud.get("_sheet_closing")) or not bool(_hud.call("sheet_open")), "large drag (40% of height) starts closing")
	await _wait(0.5)
	_check(not bool(_hud.call("sheet_open")), "large drag: sheet hidden")

	# --- reopen after drag-close ---
	await _open()
	_check(_is_open() and absf(_panel().position.y - rest) < 1.0, "reopen after drag-close lands at rest (y=%.1f)" % _panel().position.y)

	# --- fast short flick (touch) closes ---
	g = _grab_point()
	_touch(g, true)
	_touch_drag(g + Vector2(0, 30))
	_touch_drag(g + Vector2(0, 80))
	_touch_drag(g + Vector2(0, 120))
	var flick_off := _panel().position.y - rest
	_touch(g + Vector2(0, 120), false)
	await process_frame
	_check(flick_off < h * 0.25, "flick distance below the 25%% threshold (%.1f of %.1f)" % [flick_off, h])
	_check(bool(_hud.get("_sheet_closing")) or not bool(_hud.call("sheet_open")), "fast flick starts closing")
	await _wait(0.5)
	_check(not bool(_hud.call("sheet_open")), "fast flick: sheet hidden")

	# --- slow short touch drag does not close ---
	await _open()
	g = _grab_point()
	_touch(g, true)
	for i: int in 6:
		_touch_drag(g + Vector2(0, 20.0 * (i + 1)))
		await process_frame
	await _wait(0.25)
	_touch(g + Vector2(0, 120), false)
	await _wait(0.4)
	_check(_is_open() and absf(_panel().position.y - rest) < 1.0, "slow short touch drag springs back")

	# --- tap on the dim closes ---
	_mouse_motion(Vector2(360, 40), false)
	_mouse_button(Vector2(360, 40), true)
	_mouse_button(Vector2(360, 40), false)
	await _wait(0.5)
	_check(not bool(_hud.call("sheet_open")), "tap on dim closes")

	# --- double close / open-close-open races ---
	await _open()
	_hud.call("close_sheet")
	_hud.call("close_sheet")
	await process_frame
	_hud.call("open_sheet")
	await _wait(0.6)
	_check(_is_open() and absf(_panel().position.y - rest) < 1.0, "reopen mid-close returns to rest")
	_hud.call("close_sheet")
	await _wait(0.5)
	_check(not bool(_hud.call("sheet_open")) and not paused, "closed again and game unpaused")

	print("%d failure(s)" % _fails)
	quit(1 if _fails > 0 else 0)
