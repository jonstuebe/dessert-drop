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

## Visible outline of a dessert in game pixels, centred on the body: the largest
## opaque region (alpha >= 0.5) of the very texture `dessert()` draws, so physics
## can follow the art. Soft drop shadows stay under 0.3 alpha and don't count.
static func dessert_outline(tier: int, px_radius: float) -> PackedVector2Array:
	var key := "outline:%d@%.3f" % [tier, px_radius]
	if _cache.has(key):
		return _cache[key]
	var img := dessert(tier, px_radius).get_image()
	img.clear_mipmaps()
	var bm := BitMap.new()
	bm.create_from_image_alpha(img, 0.5)
	var best := PackedVector2Array()
	var best_area := 0.0
	# epsilon of 1 texture px = 1/SS game px
	for poly: PackedVector2Array in bm.opaque_to_polygons(Rect2i(Vector2i.ZERO, img.get_size()), 1.0):
		var a := absf(polygon_area(poly))
		if a > best_area:
			best_area = a
			best = poly
	var half := Vector2(img.get_size()) / 2.0
	var out := PackedVector2Array()
	for p in best:
		out.append((p - half) / SS)
	_cache[key] = out
	return out

static func polygon_area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		a += poly[i].cross(poly[(i + 1) % poly.size()])
	return a / 2.0

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
