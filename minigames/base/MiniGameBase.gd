class_name MiniGameBase
extends Control

@export var game_id: int = 1
@export var game_title: String = "Mini Oyun"
@export var round_duration: float = 45.0

var is_round_active: bool = false
var current_seed: int = 0
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	PartyNetworkBridge.packet_received.connect(_on_network_packet)
	SensorGestureController.aim_target_changed.connect(_on_aim_changed)
	SensorGestureController.flick_detected.connect(_on_flick)
	SensorGestureController.tilt_changed.connect(_on_tilt)
	SensorGestureController.device_flipped.connect(_on_flipped)

func start_round(seed_val: int) -> void:
	current_seed = seed_val
	rng.seed = seed_val
	is_round_active = true
	_on_round_started()

func end_round(winner_id: int) -> void:
	if not is_round_active:
		return
	is_round_active = false
	_on_round_ended(winner_id)

func send_game_action(target_id: int, custom_bytes: PackedByteArray) -> void:
	var heading_int: int = int(roundf(SensorGestureController.smoothed_heading))
	PartyNetworkBridge.send_packet(
		PartyNetworkBridge.PacketType.GAME_ACTION,
		target_id,
		game_id,
		heading_int,
		current_seed,
		custom_bytes
	)

func _on_network_packet(sender_id: int, target_id: int, p_game_id: int, heading: int, _seed: int, payload: PackedByteArray) -> void:
	if p_game_id != game_id or not is_round_active:
		return
	_on_action_received(sender_id, target_id, heading, payload)

# Alt sınıfların (Dinamit, Düello, Casus vb.) ezeceği sanal metodlar
func _on_round_started() -> void:
	pass

func _on_round_ended(_winner_id: int) -> void:
	pass

func _on_action_received(_sender_id: int, _target_id: int, _heading: int, _payload: PackedByteArray) -> void:
	pass

func _on_aim_changed(_target_player_id: int) -> void:
	pass

func _on_flick(_locked_heading: float, _force: float) -> void:
	pass

func _on_tilt(_pitch: float, _roll: float) -> void:
	pass

func _on_flipped(_is_face_down: bool) -> void:
	pass