class_name DinamitArtwork
extends Control

const PAPER: Color = Color("#fff0db")
const FUSE: Array[Vector2] = [
	Vector2(60, -18), Vector2(63, -24), Vector2(57, -32),
	Vector2(59, -43), Vector2(77, -47), Vector2(91, -39), Vector2(103, -46),
]

var accent: Color = Color("#d4b9f3")
var countdown: int = 0
var fuse_lit: bool = false
var fuse_fraction: float = 0.0
var danger: float = 0.0
var show_swipe: bool = false
var exploded: bool = false
var reduced_motion: bool = false

var _clock: float = 0.0
var _offset: Vector2 = Vector2.ZERO
var _spin: float = 0.0
var _zoom: float = 1.0
var _opacity: float = 1.0
var _burst: float = 1.0
var _motion: Tween

func _process(delta: float) -> void:
	if fuse_lit and not reduced_motion:
		_clock = fmod(_clock + delta, 120.0)
		queue_redraw()

func reset_motion() -> void:
	if _motion != null:
		_motion.kill()
		_motion = null
	_offset = Vector2.ZERO
	_spin = 0.0
	_zoom = 1.0
	_opacity = 1.0
	_burst = 1.0
	queue_redraw()

func play_pass(received: bool) -> void:
	reset_motion()
	if reduced_motion:
		return
	_motion = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if received:
		_offset = Vector2(42.0, -size.y * 0.32)
		_spin = 0.42
		_zoom = 0.66
		_opacity = 0.25
		_motion.tween_property(self, "_offset", Vector2.ZERO, 0.26)
		_motion.tween_property(self, "_spin", 0.0, 0.26)
		_motion.tween_property(self, "_zoom", 1.0, 0.26)
		_motion.tween_property(self, "_opacity", 1.0, 0.18)
	else:
		_motion.tween_property(self, "_offset", Vector2(42.0, -size.y * 0.55), 0.24)
		_motion.tween_property(self, "_spin", 0.58, 0.24)
		_motion.tween_property(self, "_zoom", 0.52, 0.24)
		_motion.tween_property(self, "_opacity", 0.0, 0.24)
		_motion.chain().tween_callback(_settle_pass)

func _settle_pass() -> void:
	_offset = Vector2.ZERO
	_spin = 0.0
	_zoom = 0.9
	_motion = create_tween().set_parallel().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_motion.tween_property(self, "_opacity", 1.0, 0.2)
	_motion.tween_property(self, "_zoom", 1.0, 0.2)

func play_explosion() -> void:
	reset_motion()
	if reduced_motion:
		return
	_burst = 0.42
	_motion = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_motion.tween_method(_set_burst, 0.42, 1.0, 0.35)

func _set_burst(value: float) -> void:
	_burst = value
	queue_redraw()

func _draw() -> void:
	var center: Vector2 = size * Vector2(0.5, 0.48)
	var fit: float = minf(size.x / 325.0, size.y / 214.0)
	var glow: float = 0.0 if reduced_motion else sin(_clock * (5.0 + danger * 10.0))
	var detail: Color = accent.lerp(Color("#ff6379"), danger)
	_draw_stage(center, fit, detail, glow)

	if countdown > 0:
		_draw_word(str(countdown), center, roundi(116.0 * fit), PAPER)
	elif exploded:
		_draw_burst(center, fit)
	else:
		var shake: Vector2 = Vector2(glow, sin(_clock * 29.0)) * danger * danger * 3.0
		if reduced_motion:
			shake = Vector2.ZERO
		var zoom: float = _zoom * fit * (1.0 + glow * danger * 0.035)
		draw_set_transform(center + _offset + shake, -0.38 + _spin, Vector2.ONE * zoom)
		_draw_bundle(detail)
		draw_set_transform(Vector2.ZERO)
		if show_swipe:
			_draw_swipe()

func _draw_stage(center: Vector2, fit: float, color: Color, glow: float) -> void:
	draw_circle(center, 93.0 * fit, Color(color, 0.06 + danger * 0.035), true, -1.0, true)
	draw_arc(center, 93.0 * fit, 0.0, TAU, 64, Color(color, 0.20), 1.0, true)
	draw_arc(center, 117.0 * fit, -1.31, 1.31, 38, Color(color, 0.18), 1.0, true)
	draw_arc(center, 117.0 * fit, 1.83, 4.45, 38, Color(color, 0.18), 1.0, true)
	if fuse_lit:
		draw_arc(center, 93.0 * fit, -PI * 0.5, -PI * 0.5 + TAU * fuse_fraction, 64, Color(color, 0.48 + glow * danger * 0.14), 2.0, true)
	for index: int in range(12):
		var ray: Vector2 = Vector2.from_angle(float(index) * TAU / 12.0)
		draw_line(center + ray * 107.0 * fit, center + ray * 112.0 * fit, Color(color, 0.32), 1.0, true)

func _draw_bundle(detail: Color) -> void:
	var line: PackedVector2Array = PackedVector2Array(FUSE)
	if fuse_lit:
		# The visible cord shortens from its tip toward the bundle.
		var end: float = fuse_fraction * float(FUSE.size() - 1)
		var segment: int = mini(floori(end), FUSE.size() - 2)
		var ember: Vector2 = FUSE[segment].lerp(FUSE[segment + 1], end - float(segment))
		line.resize(segment + 2)
		line[segment + 1] = ember
		draw_polyline(line, Color("#f3b372", _opacity), 5.0, true)
		_draw_ember(ember, detail)
	else:
		draw_polyline(line, Color(0.66, 0.50, 0.55, _opacity), 5.0, true)

	_draw_stick(-31.0, Color("#df4f73"))
	_draw_stick(30.0, Color("#a92451"))
	_draw_stick(0.0, Color("#f56a7b"))
	var strap: Rect2 = Rect2(-28.0, -47.0, 49.0, 94.0)
	draw_rect(strap, Color(0.13, 0.09, 0.19, _opacity))
	draw_line(Vector2(-25, -43), Vector2(-25, 43), Color(1.0, 0.7, 0.71, 0.42 * _opacity), 2.0, true)
	var bolt: PackedVector2Array = PackedVector2Array([
		Vector2(1, -23), Vector2(-16, 3), Vector2(-4, 3),
		Vector2(-9, 23), Vector2(12, -5), Vector2(0, -5),
	])
	draw_colored_polygon(bolt, Color(PAPER, _opacity))

func _draw_stick(row: float, color: Color) -> void:
	var left: Vector2 = Vector2(-54.0, row)
	var right: Vector2 = Vector2(57.0 + row * 0.13, row)
	var shade: Color = color.darkened(0.45)
	draw_line(left, right, Color(shade, _opacity), 40.0, true)
	draw_circle(left, 20.0, Color(shade, _opacity), true, -1.0, true)
	draw_circle(right, 20.0, Color(shade, _opacity), true, -1.0, true)
	draw_line(left - Vector2(0, 3), right - Vector2(0, 3), Color(color, _opacity), 33.0, true)
	draw_circle(left - Vector2(0, 3), 16.5, Color(color, _opacity), true, -1.0, true)
	draw_circle(right - Vector2(0, 3), 16.5, Color(color.darkened(0.22), _opacity), true, -1.0, true)
	draw_line(left + Vector2(3, -12), right + Vector2(-13, -12), Color(color.lightened(0.33), _opacity), 2.0, true)

func _draw_ember(ember: Vector2, color: Color) -> void:
	draw_circle(ember, 14.0, Color(color, 0.16 * _opacity), true, -1.0, true)
	draw_circle(ember, 6.0, Color("#ff8b57", _opacity), true, -1.0, true)
	draw_circle(ember, 3.0, Color(PAPER, _opacity), true, -1.0, true)
	for index: int in range(6):
		var phase: float = 0.5 if reduced_motion else fposmod(_clock * (1.7 + danger) + float(index) / 6.0, 1.0)
		var ray: Vector2 = Vector2.from_angle(float(index) * 2.4)
		draw_line(ember + ray * (8.0 + phase * 18.0), ember + ray * (12.0 + phase * 18.0), Color(PAPER, (1.0 - phase) * _opacity), 2.0, true)

func _draw_swipe() -> void:
	var drift: float = 0.0 if reduced_motion else sin(_clock * 4.0) * 4.0
	var middle: Vector2 = Vector2(size.x * 0.5, size.y - 19.0 + drift)
	var arrow: PackedVector2Array = PackedVector2Array([
		middle + Vector2(-9, 4), middle + Vector2(0, -4), middle + Vector2(9, 4),
	])
	draw_polyline(Transform2D(0.0, Vector2(0, -8)) * arrow, Color(accent, 0.48), 2.0, true)
	draw_polyline(arrow, accent, 2.5, true)

func _draw_burst(center: Vector2, fit: float) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	for index: int in range(24):
		var direction: Vector2 = Vector2.from_angle(float(index) * TAU / 24.0)
		var radius: float = 48.0 if index % 2 == 0 else 78.0 + float(index % 5) * 4.0
		points.append(center + direction * radius * fit * _burst)
	draw_colored_polygon(points, Color("#ff9b57"))
	for index: int in range(8):
		var ray: Vector2 = Vector2.from_angle(float(index) * TAU / 8.0 + 0.21)
		draw_line(center + ray * 97.0 * fit * _burst, center + ray * 113.0 * fit * _burst, Color(accent, 0.85), 3.0, true)
	_draw_word("BOOM!", center, roundi(32.0 * fit), Color("#291528"))

func _draw_word(word: String, center: Vector2, font_size: int, color: Color) -> void:
	var font: Font = get_theme_font("font", "PrimaryButton")
	var width: float = font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var baseline: float = (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
	draw_string(font, center + Vector2(-width * 0.5, baseline), word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
