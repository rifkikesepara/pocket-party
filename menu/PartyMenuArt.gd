extends Control
## Resolution-independent artwork for the club-poster pages.

const INK: Color = Color("10156c")
const CREAM: Color = Color("fff6df")
const PEACH: Color = Color("ffac80")
const MONOGRAM: Texture2D = preload("res://assets/branding/pp-monogram.svg")
const WORDMARK: Texture2D = preload("res://assets/branding/pp-wordmark.svg")
const DISPLAY: Font = preload("res://assets/fonts/BarlowCondensed-BlackItalic.ttf")

@export_enum("Home", "Ribbon", "Background", "Dynamite", "Balance", "Flip") var artwork: int = 0
@export var poster_title: String = "POCKET\nPARTY"
@export var peach_ribbon: bool = false

var reduced_motion: bool = false:
	set(value):
		reduced_motion = value
		_time = 0.0
		queue_redraw()
var _time: float = 0.0

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	resized.connect(queue_redraw)

func _process(delta: float) -> void:
	if artwork != 0 or reduced_motion or not is_visible_in_tree():
		return
	_time += delta
	queue_redraw()

func _draw() -> void:
	match artwork:
		0: _home()
		1: _ribbon()
		2: _background()
		3, 4, 5:
			var factor: float = minf(size.x / 140.0, size.y / 140.0)
			draw_set_transform(size * 0.5, -0.12, Vector2.ONE * factor)
			match artwork:
				3: _bomb()
				4: _balance()
				5: _phone(Vector2.ZERO, 0.29, 0.65)
			draw_set_transform(Vector2.ZERO)

func _background() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("081b9d"))
	draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(size.x * 0.40, 0), Vector2(0, size.y * 0.065)]), PEACH)
	draw_colored_polygon(PackedVector2Array([Vector2(0, size.y), Vector2(size.x, size.y * 0.97), size]), PEACH)

func _home() -> void:
	var factor: float = minf(size.x / 376.0, size.y / 500.0)
	var origin: Vector2 = (size - Vector2(376, 500) * factor) * 0.5
	var bob: float = sin(_time * 1.7) * 2.0
	draw_set_transform(origin, 0.0, Vector2.ONE * factor)
	draw_texture_rect(MONOGRAM, Rect2(48, 16 + bob, 280, 252), false)
	draw_texture_rect(WORDMARK, Rect2(0, 295, 376, 188), false)
	draw_set_transform(Vector2.ZERO)

func _ribbon() -> void:
	var factor: float = size.x / 376.0
	var two_lines: bool = poster_title.contains("\n")
	draw_set_transform(Vector2(0, 27) * factor, -0.12, Vector2.ONE * factor)
	var bottom: float = 124.0 if two_lines else 78.0
	draw_colored_polygon(PackedVector2Array([Vector2(34, 23), Vector2(392, -7), Vector2(395, bottom), Vector2(7, bottom + 13), Vector2(91, 65)]), PEACH if peach_ribbon else CREAM)
	var baseline: float = 65.0
	for word: String in poster_title.split("\n"):
		var font_size: int = 61 if two_lines else 52
		var width: float = DISPLAY.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_string(DISPLAY, Vector2(367 - width, baseline), word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, INK)
		baseline += 54
	draw_set_transform(Vector2.ZERO)

func _box(rect: Rect2, color: Color, radius: int, border: int = 0, edge: Color = INK) -> void:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.set_border_width_all(border)
	style.border_color = edge
	draw_style_box(style, rect)

func _phone(center: Vector2, angle: float, factor: float) -> void:
	var base: Transform2D = Transform2D(angle, center).scaled_local(Vector2.ONE * factor)
	var parent_transform: Transform2D = Transform2D.IDENTITY
	if artwork == 0:
		parent_transform = Transform2D(0.0, Vector2(size.x * 0.5, size.y * 0.74)).scaled_local(Vector2.ONE * minf(size.x / 376.0, size.y / 500.0))
	else:
		parent_transform = Transform2D(-0.12, size * 0.5).scaled_local(Vector2.ONE * minf(size.x / 140.0, size.y / 140.0))
	draw_set_transform_matrix(parent_transform * base)
	_box(Rect2(-58, -96, 116, 192), CREAM, 20)
	_box(Rect2(-51, -89, 102, 178), INK, 15)
	_box(Rect2(-40, -69, 80, 132), CREAM, 9)
	draw_line(Vector2(-13, -78), Vector2(13, -78), CREAM, 4, true)
	draw_line(Vector2(-7, 76), Vector2(7, 76), CREAM, 5, true)
	draw_circle(Vector2(-20, -9), 6, INK)
	draw_circle(Vector2(20, -9), 6, INK)
	draw_arc(Vector2(0, -1), 12, 0.1, PI - 0.1, 20, INK, 6, true)
	draw_circle(Vector2(-28, 7), 4, PEACH)
	draw_circle(Vector2(28, 7), 4, PEACH)

func _bomb() -> void:
	draw_arc(Vector2(-2, 7), 43, 2.5, 4.0, 24, INK, 4, true)
	draw_circle(Vector2(2, 10), 34, INK)
	draw_arc(Vector2(2, 10), 26, 3.65, 4.45, 16, CREAM, 3, true)
	draw_line(Vector2(14, -19), Vector2(24, -34), INK, 11, true)
	draw_arc(Vector2(34, -34), 10, PI, TAU, 16, INK, 3, true)
	_burst(Vector2(44, -43), PEACH)

func _balance() -> void:
	for index: int in range(3):
		var y: float = 28 - index * 26
		var width: float = 88 - index * 23
		_box(Rect2(-width * 0.5, y - 12, width, 25), INK, 12)
		_box(Rect2(-width * 0.5 + 6, y - 11, width - 12, 15), CREAM, 9)
	_burst(Vector2(-44, -35), PEACH)

func _burst(origin: Vector2, color: Color) -> void:
	for index: int in range(3):
		var angle: float = -2.5 + index * 0.55
		var direction: Vector2 = Vector2.from_angle(angle)
		var side: Vector2 = direction.orthogonal() * 4
		draw_colored_polygon(PackedVector2Array([origin + direction * 9, origin + direction * 29 + side, origin + direction * 29 - side]), color)
