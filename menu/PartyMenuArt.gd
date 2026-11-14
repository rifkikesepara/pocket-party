extends Control

var reduced_motion: bool = false:
	set(value):
		reduced_motion = value
		_time = 0.0
		queue_redraw()

var _time: float = 0.0

func _process(delta: float) -> void:
	if reduced_motion or not is_visible_in_tree():
		return
	_time += delta
	queue_redraw()

func _draw() -> void:
	var center: Vector2 = size * Vector2(0.5, 0.53)
	var scale_factor: float = minf(size.x / 350.0, size.y / 181.0)
	draw_circle(center, 102.0 * scale_factor, Color("#302144"), true, -1.0, true)
	for index: int in range(3):
		var radius: float = (62.0 + 17.0 * float(index)) * scale_factor
		var phase: float = float(index) * 1.2 + _time * 0.18
		draw_arc(center, radius, phase, phase + 4.8, 60, Color("#624578"), 1.0, true)
	for index: int in range(11):
		var x: float = -149.0 + float(index) * 29.0
		var y: float = -53.0 + float((index * 37) % 106)
		var point: Vector2 = center + Vector2(x, y + sin(_time * 1.5 + float(index)) * 4.0) * scale_factor
		var color: Color = PartyAvatar.COLORS[index % PartyAvatar.COLORS.size()]
		var arm: float = (3.0 + float(index % 3) * 2.0) * scale_factor
		draw_line(point - Vector2(arm, 0.0), point + Vector2(arm, 0.0), color, 1.6, true)
		draw_line(point - Vector2(0.0, arm), point + Vector2(0.0, arm), color, 1.6, true)

	PartyAvatar.draw_face(self, center + Vector2(-81, 10 + 6.0 * sin(_time * 1.25)) * scale_factor, 45.0 * scale_factor, 26, -0.26 + sin(_time * 1.25) * 0.06)
	PartyAvatar.draw_face(self, center + Vector2(78, 13 + 6.0 * sin(_time * 1.35 + 2.3)) * scale_factor, 43.0 * scale_factor, 43, 0.22 + sin(_time * 1.35) * 0.06)
	PartyAvatar.draw_face(self, center + Vector2(0, -19 + 7.0 * sin(_time * 1.4 + 1.2)) * scale_factor, 53.0 * scale_factor, 30, -0.07 + sin(_time * 1.4) * 0.06)
