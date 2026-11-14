extends SceneTree
## Rasterize the same vector art for Godot's pre-scene boot splash.
func _initialize() -> void:
	var result: Error = _render("splash", 0)
	if result == OK:
		result = _render("pp-icon", 1024)
	if result != OK:
		push_error("Brand export failed: %s" % error_string(result))
	quit(0 if result == OK else 1)

func _render(asset: String, edge: int) -> Error:
	var source: String = FileAccess.get_file_as_string("res://assets/branding/%s.svg" % asset)
	var picture: Image = Image.new()
	var result: Error = picture.load_svg_from_string(source)
	if result == OK:
		if edge > 0:
			picture.resize(edge, edge, Image.INTERPOLATE_LANCZOS)
		result = picture.save_png("res://assets/branding/%s.png" % asset)
	return result
