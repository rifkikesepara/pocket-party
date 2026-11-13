extends Node

signal aim_target_changed(target_player_id: int)
signal flick_detected(locked_heading: float, force: float)
signal tilt_changed(pitch: float, roll: float)
signal device_flipped(is_face_down: bool)

const MAX_MOCK_PLAYERS: int = 4
const SWIPE_THRESHOLD_PX: float = 80.0
const FLICK_ACCEL_THRESHOLD: float = 18.0

var smoothed_heading: float = 0.0
var current_target_id: int = 1

var _touch_start_pos: Vector2 = Vector2.ZERO
var _is_touching: bool = false
var _last_face_down: bool = false
var _flick_cooldown: float = 0.0

func _ready() -> void:
	current_target_id = (PartyNetworkBridge.local_player_id + 1) % 2
	_update_heading_for_target()

func _process(delta: float) -> void:
	if _flick_cooldown > 0.0:
		_flick_cooldown -= delta

	var accel: Vector3 = Input.get_accelerometer()
	if accel != Vector3.ZERO:
		var pitch: float = atan2(accel.y, accel.z)
		var roll: float = atan2(-accel.x, sqrt(accel.y * accel.y + accel.z * accel.z))
		tilt_changed.emit(pitch, roll)

		var is_face_down: bool = accel.z < -7.5
		if is_face_down != _last_face_down:
			_last_face_down = is_face_down
			device_flipped.emit(is_face_down)

		if _flick_cooldown <= 0.0 and accel.length() > FLICK_ACCEL_THRESHOLD:
			_flick_cooldown = 0.4
			flick_detected.emit(smoothed_heading, accel.length())

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.keycode == KEY_LEFT:
			_cycle_target(-1)
		elif key_event.keycode == KEY_RIGHT:
			_cycle_target(1)
		elif key_event.keycode == KEY_SPACE:
			flick_detected.emit(smoothed_heading, 1.0)
	elif event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event as InputEventScreenTouch
		if touch.pressed:
			_touch_start_pos = touch.position
			_is_touching = true
		elif _is_touching:
			_is_touching = false
			_evaluate_swipe(touch.position - _touch_start_pos)
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_touch_start_pos = mb.position
				_is_touching = true
			elif _is_touching:
				_is_touching = false
				_evaluate_swipe(mb.position - _touch_start_pos)

func _evaluate_swipe(delta_pos: Vector2) -> void:
	if delta_pos.y < -SWIPE_THRESHOLD_PX and absf(delta_pos.y) > absf(delta_pos.x):
		var force: float = clampf(-delta_pos.y / 200.0, 0.5, 2.0)
		flick_detected.emit(smoothed_heading, force)

func _cycle_target(step: int) -> void:
	var local_id: int = PartyNetworkBridge.local_player_id
	var candidate: int = posmod(current_target_id + step, MAX_MOCK_PLAYERS)
	if candidate == local_id:
		candidate = posmod(candidate + step, MAX_MOCK_PLAYERS)
	current_target_id = candidate
	_update_heading_for_target()
	aim_target_changed.emit(current_target_id)

func _update_heading_for_target() -> void:
	smoothed_heading = float(current_target_id * 90)
