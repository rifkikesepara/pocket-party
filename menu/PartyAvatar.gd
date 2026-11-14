class_name PartyAvatar
extends Control

const COLORS: Array[Color] = [
	Color("#ffc969"), Color("#93edcc"), Color("#dbb7ff"),
	Color("#ff879f"), Color("#83c9ff"), Color("#ffab85"),
]
const INK: Color = Color("#281a32")

@export var avatar: int = 0:
	set(value):
		avatar = value
		queue_redraw()

var photo_texture: Texture2D:
	set(value):
		photo_texture = value
		queue_redraw()

func _draw() -> void:
	var center: Vector2 = size * 0.5
	var radius: float = minf(size.x, size.y) * 0.43
	if photo_texture == null:
		draw_face(self, center, radius, avatar)
		return
	var points: PackedVector2Array = PackedVector2Array()
	var uv: PackedVector2Array = PackedVector2Array()
	for index: int in range(64):
		var direction: Vector2 = Vector2.from_angle(index * TAU / 64.0)
		points.append(center + direction * radius)
		uv.append(Vector2(0.5, 0.5) + direction * 0.5)
	draw_circle(center, radius + 3.0, COLORS[avatar % COLORS.size()], true, -1.0, true)
	draw_polygon(points, PackedColorArray([Color.WHITE]), uv, photo_texture)

static func draw_face(canvas: Control, center: Vector2, radius: float, look: int, angle: float = 0.0) -> void:
	var form: int = look / PartyProfile.COLOR_COUNT
	var paint: Color = COLORS[look % COLORS.size()]
	canvas.draw_set_transform(center, angle, Vector2.ONE * radius)
	if form == 4:
		for ear: float in [-0.62, 0.62]:
			canvas.draw_colored_polygon(PackedVector2Array([Vector2(ear - 0.3, -0.45), Vector2(ear, -1.18), Vector2(ear + 0.3, -0.56)]), paint)
	if form == 7:
		canvas.draw_line(Vector2(0, -0.7), Vector2(0.22, -1.19), INK, 0.09, true)
		canvas.draw_circle(Vector2(0.22, -1.19), 0.15, paint)
	var outline: PackedVector2Array = PackedVector2Array()
	for index: int in range(64):
		var theta: float = float(index) * TAU / 64.0
		var contour: float = 1.0 + (0.11 * cos(theta * 6.0) if form == 2 or form == 7 else 0.0)
		outline.append(Vector2.from_angle(theta) * contour)
	canvas.draw_colored_polygon(outline, paint)
	outline.append(outline[0])
	canvas.draw_polyline(outline, INK, 0.035, true)
	for x: float in [-0.32, 0.32]:
		var eye: Vector2 = Vector2(x, -0.12)
		if form == 5:
			canvas.draw_circle(eye, 0.23, INK)
			canvas.draw_line(eye + Vector2(-0.09, 0.04), eye + Vector2(0.06, -0.12), Color("#d9c7fa"), 0.07, true)
		elif form == 6:
			var pupil: Vector2 = eye + Vector2(signf(x) * 0.04, 0.03)
			canvas.draw_circle(eye, 0.20, Color.WHITE)
			canvas.draw_circle(pupil, 0.09, INK)
		elif form == 1:
			canvas.draw_arc(eye + Vector2(0.0, 0.04), 0.125, PI, TAU, 14, INK, 0.07, true)
		else:
			canvas.draw_circle(eye, 0.105 if form == 3 else 0.085, INK)
			if form == 3:
				canvas.draw_circle(eye - Vector2(0.03, 0.04), 0.035, Color.WHITE)
	if form == 5:
		canvas.draw_line(Vector2(-0.28, -0.12), Vector2(0.28, -0.12), INK, 0.095, true)
		canvas.draw_circle(Vector2(-0.16, 0.25), 0.15, INK)
		canvas.draw_circle(Vector2(0.16, 0.25), 0.15, INK)
	elif form == 4:
		canvas.draw_circle(Vector2(0, 0.14), 0.09, INK)
		for side: float in [-1.0, 1.0]:
			canvas.draw_line(Vector2(side * 0.55, 0.18), Vector2(side * 0.84, 0.1), INK, 0.037, true)
			canvas.draw_line(Vector2(side * 0.55, 0.30), Vector2(side * 0.85, 0.31), INK, 0.037, true)
		canvas.draw_arc(Vector2(0, 0.15), 0.25, 0.3, PI - 0.3, 20, INK, 0.065, true)
	elif form == 6:
		canvas.draw_circle(Vector2(0.05, 0.33), 0.22, INK)
		canvas.draw_circle(Vector2(0.09, 0.45), 0.13, Color("#fa6298"))
		canvas.draw_rect(Rect2(-0.045, 0.15, 0.11, 0.13), Color.WHITE)
	elif form == 7:
		canvas.draw_arc(Vector2(0.0, 0.07), 0.34, 0.22, PI - 0.22, 20, INK, 0.15, true)
		canvas.draw_rect(Rect2(-0.12, 0.31, 0.10, 0.13), Color.WHITE)
		canvas.draw_rect(Rect2(0.035, 0.31, 0.10, 0.13), Color.WHITE)
	elif form == 2:
		canvas.draw_circle(Vector2(0.0, 0.24), 0.145, INK)
	else:
		canvas.draw_arc(Vector2(0.0, 0.12), 0.27, 0.3, PI - 0.3, 20, INK, 0.065, true)
	for x: float in [-0.56, 0.56]:
		canvas.draw_circle(Vector2(x, 0.18), 0.105, Color(0.64, 0.21, 0.35, 0.25))
	canvas.draw_set_transform(Vector2.ZERO)
