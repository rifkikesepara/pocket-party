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

func _draw() -> void:
	draw_face(self, size * 0.5, minf(size.x, size.y) * 0.46, avatar)

static func draw_face(canvas: Control, center: Vector2, radius: float, look: int, angle: float = 0.0) -> void:
	var form: int = look / PartyProfile.COLOR_COUNT
	var paint: Color = COLORS[look % COLORS.size()]
	canvas.draw_set_transform(center, angle, Vector2.ONE * radius)
	var outline: PackedVector2Array = PackedVector2Array()
	for index: int in range(64):
		var theta: float = float(index) * TAU / 64.0
		var contour: float = 1.0 + (0.11 * cos(theta * 6.0) if form == 2 else 0.0)
		outline.append(Vector2.from_angle(theta) * contour)
	canvas.draw_colored_polygon(outline, paint)
	outline.append(outline[0])
	canvas.draw_polyline(outline, INK, 0.035, true)
	for x: float in [-0.32, 0.32]:
		var eye: Vector2 = Vector2(x, -0.12)
		if form == 1:
			canvas.draw_arc(eye + Vector2(0.0, 0.04), 0.125, PI, TAU, 14, INK, 0.07, true)
		else:
			canvas.draw_circle(eye, 0.105 if form == 3 else 0.085, INK)
			if form == 3:
				canvas.draw_circle(eye - Vector2(0.03, 0.04), 0.035, Color.WHITE)
	if form == 2:
		canvas.draw_circle(Vector2(0.0, 0.24), 0.145, INK)
	else:
		canvas.draw_arc(Vector2(0.0, 0.12), 0.27, 0.3, PI - 0.3, 20, INK, 0.065, true)
	for x: float in [-0.56, 0.56]:
		canvas.draw_circle(Vector2(x, 0.18), 0.105, Color(0.64, 0.21, 0.35, 0.25))
	canvas.draw_set_transform(Vector2.ZERO)
