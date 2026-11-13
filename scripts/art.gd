class_name Art
## Rasterizes the SVG art at runtime at exactly the size it is shown, so it stays
## crisp on every screen. Results are cached.

const DIR := "res://assets/art/"
## Supersampling: textures are drawn this much bigger than game pixels so they
## stay sharp when the 720-wide viewport is stretched onto a high-DPI phone.
const SS := 2.0

static var _cache: Dictionary = {}
static var _svg_text: Dictionary = {}

static func svg(file: String, scale: float) -> Texture2D:
	var key := "%s@%.3f" % [file, scale]
	if _cache.has(key):
		return _cache[key]
	if not _svg_text.has(file):
		var f := FileAccess.open(DIR + file + ".svg", FileAccess.READ)
		if f == null:
			push_error("Missing art: " + file)
			return null
		_svg_text[file] = f.get_as_text()
	var img := Image.new()
	var err := img.load_svg_from_string(_svg_text[file], scale)
	if err != OK:
		push_error("Could not render " + file)
		return null
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex

## Texture for a dessert drawn so that `px_radius` game pixels = its body radius.
## Show it with scale 1/SS.
static func dessert(tier: int, px_radius: float) -> Texture2D:
	return svg(Tiers.info(tier)["file"], px_radius / Tiers.ART_R * SS)

## Texture for an icon (72-unit viewBox) shown `px` game pixels wide. Show at scale 1/SS.
static func icon(file: String, px: float) -> Texture2D:
	return svg(file, px / 72.0 * SS)

## Small inline SVG shapes used for particles.
static func shape(name: String, svg_text: String, scale: float = 1.0) -> Texture2D:
	var key := "shape:" + name
	if _cache.has(key):
		return _cache[key]
	var img := Image.new()
	img.load_svg_from_string(svg_text, scale)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex
