extends Control

func _draw() -> void:
	var center: Vector2 = size * Vector2(0.5, 0.53)
	var scale_factor: float = minf(size.x / 360.0, size.y / 172.0)
	for index: int in range(3):
		var radius: float = (62.0 + 17.0 * float(index)) * scale_factor
		draw_arc(center, radius, 0.0, TAU, 60, Color("#54415e"), 1.0, true)
	for index: int in range(11):
		var x: float = -149.0 + float(index) * 29.0
		var y: float = -53.0 + float((index * 37) % 106)
		var point: Vector2 = center + Vector2(x, y) * scale_factor
		var color: Color = PartyAvatar.COLORS[index % PartyAvatar.COLORS.size()]
		var arm: float = (3.0 + float(index % 3) * 2.0) * scale_factor
		draw_line(point - Vector2(arm, 0.0), point + Vector2(arm, 0.0), color, 1.6, true)
		draw_line(point - Vector2(0.0, arm), point + Vector2(0.0, arm), color, 1.6, true)

	PartyAvatar.draw_face(self, center + Vector2(-65, 9) * scale_factor, 42.0 * scale_factor, 8, -0.26)
	PartyAvatar.draw_face(self, center + Vector2(68, 4) * scale_factor, 42.0 * scale_factor, 13, 0.21)
	PartyAvatar.draw_face(self, center + Vector2(0, -15) * scale_factor, 52.0 * scale_factor, 0, -0.06)
