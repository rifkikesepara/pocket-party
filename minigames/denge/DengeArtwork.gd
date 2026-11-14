class_name DengeArtwork
extends Control

const NAVY: Color = Color("#10156c")
const ROYAL: Color = Color("#081b9d")
const CREAM: Color = Color("#fff6df")
const CORAL: Color = Color("#ff766a")
const YELLOW: Color = Color("#e6ef28")
const MINT: Color = Color("#7be0ad")

var local_ball: Vector2 = Vector2.ZERO
var peer_ball: Vector2 = Vector2.ZERO
var tilt_vec: Vector2 = Vector2.ZERO
var wind_vec: Vector2 = Vector2.ZERO
var is_active: bool = false
var is_countdown: bool = false
var is_fallen: bool = false
var danger_ratio: float = 0.0
var prefer_reduced_motion: bool = false

var _shake_time: float = 0.0

func reset_motion() -> void:
	local_ball = Vector2.ZERO
	peer_ball = Vector2.ZERO
	tilt_vec = Vector2.ZERO
	wind_vec = Vector2.ZERO
	is_fallen = false
	danger_ratio = 0.0
	_shake_time = 0.0
	queue_redraw()

func play_fall() -> void:
	is_fallen = true
	if not prefer_reduced_motion:
		_shake_time = 0.35
	queue_redraw()

func _process(delta: float) -> void:
	if _shake_time > 0.0:
		_shake_time = maxf(0.0, _shake_time - delta)
		queue_redraw()

func _draw() -> void:
	var center: Vector2 = size * 0.5
	if _shake_time > 0.0 and not prefer_reduced_motion:
		var mag: float = (_shake_time / 0.35) * 8.0
		center += Vector2(randf_range(-mag, mag), randf_range(-mag, mag))

	var radius: float = minf(size.x, size.y) * 0.44
	if radius <= 8.0:
		return

	# Outer danger ring
	var rim_color: Color = CORAL if danger_ratio > 0.65 or is_fallen else YELLOW
	draw_circle(center, radius + 10.0, NAVY)
	draw_arc(center, radius + 4.0, 0.0, TAU, 64, rim_color, 6.0, true)

	# Arena surface
	draw_circle(center, radius, CREAM)
	draw_arc(center, radius * 0.68, 0.0, TAU, 48, Color(0.063, 0.082, 0.424, 0.16), 2.0, true)
	draw_arc(center, radius * 0.32, 0.0, TAU, 36, Color(0.063, 0.082, 0.424, 0.22), 2.0, true)
	draw_line(center - Vector2(radius * 0.85, 0.0), center + Vector2(radius * 0.85, 0.0), Color(0.063, 0.082, 0.424, 0.12), 2.0)
	draw_line(center - Vector2(0.0, radius * 0.85), center + Vector2(0.0, radius * 0.85), Color(0.063, 0.082, 0.424, 0.12), 2.0)

	# Center target pad
	draw_circle(center, radius * 0.14, Color(0.902, 0.937, 0.157, 0.45))

	# Wind indicator arrow from center
	if is_active and not is_countdown and wind_vec.length() > 0.05:
		var w_end: Vector2 = center + wind_vec.limit_length(1.0) * (radius * 0.45)
		draw_line(center, w_end, Color(1.0, 0.463, 0.416, 0.55), 3.0, true)

	# Peer ghost ball
	var peer_px: Vector2 = center + peer_ball * (radius - 14.0)
	draw_circle(peer_px, 11.0, Color(0.482, 0.878, 0.678, 0.85))
	draw_arc(peer_px, 11.0, 0.0, TAU, 24, NAVY, 2.5, true)

	# Local player ball
	var ball_radius: float = 18.0
	var local_px: Vector2 = center + local_ball * (radius - ball_radius)
	var ball_color: Color = CORAL if is_fallen or danger_ratio > 0.72 else ROYAL
	draw_circle(local_px + Vector2(0.0, 4.0), ball_radius, Color(0.063, 0.082, 0.424, 0.25))
	draw_circle(local_px, ball_radius, ball_color)
	draw_arc(local_px, ball_radius, 0.0, TAU, 32, NAVY, 3.5, true)
	draw_circle(local_px - Vector2(5.0, 5.0), 5.0, CREAM)
