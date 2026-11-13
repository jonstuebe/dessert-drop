# Renders every assets/art/*.svg through Godot's own SVG rasterizer (ThorVG) to PNG,
# plus a contact sheet of the desserts and icons, so the art can be checked as Godot sees it.
# godot --headless --path . --script res://tools/render_svgs.gd -- [out_dir]
extends SceneTree

const DEFAULT_OUT := "/private/tmp/claude-501/-Users-jonstuebe-orca-dessert-drop/5b00bb4a-3b2f-46e5-951b-c974127d2abc/scratchpad/renders"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else DEFAULT_OUT
	DirAccess.make_dir_recursive_absolute(out_dir)
	var art_dir := ProjectSettings.globalize_path("res://assets/art")
	var sheet_items: Array[Image] = []
	var failed := 0
	for file in DirAccess.get_files_at(art_dir):
		if not file.ends_with(".svg"):
			continue
		var text := FileAccess.get_file_as_string(art_dir.path_join(file))
		var small := file.begins_with("d") or file.begins_with("coin") or file.begins_with("perk") or file.begins_with("plate") or file.begins_with("panel")
		var scale := 6.0 if small else 1.0
		var img := Image.new()
		var err := img.load_svg_from_string(text, scale)
		if err != OK:
			push_error("FAILED %s (%s)" % [file, err])
			failed += 1
			continue
		img.save_png(out_dir.path_join(file.get_basename() + ".png"))
		print("%s %dx%d" % [file, img.get_width(), img.get_height()])
		if small and not file.begins_with("panel"):
			sheet_items.append(img)
	# contact sheet on the wall colour
	var cell := 600
	var cols := 5
	var rows := int(ceil(sheet_items.size() / float(cols)))
	var sheet := Image.create(cell * cols, cell * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("#A9DDD6"))
	for i in sheet_items.size():
		var im := sheet_items[i]
		im.convert(Image.FORMAT_RGBA8)
		var pos := Vector2i((i % cols) * cell + (cell - im.get_width()) / 2, (i / cols) * cell + (cell - im.get_height()) / 2)
		sheet.blend_rect(im, Rect2i(Vector2i.ZERO, im.get_size()), pos)
	sheet.save_png(out_dir.path_join("_sheet.png"))
	quit(1 if failed > 0 else 0)
