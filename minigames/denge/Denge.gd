class_name DengeMinigame
extends MiniGameBase

signal leave_lobby_requested

const ACTION_START: int = 0x01
const ACTION_STATE: int = 0x02
const ACTION_FELL: int = 0x03

const TARGET_BROADCAST: int = 0xFF
const COUNTDOWN_SEC: float = 3.0
const STATE_SYNC_INTERVAL: float = 0.1
const TILT_SENSITIVITY: float = 1.65
const DAMPING: float = 2.4

@onready var main_margin: MarginContainer = %MarginContainer
@onready var artwork: DengeArtwork = %Artwork
@onready var local_player: Label = %LocalPlayer
@onready var peer_player: Label = %PeerPlayer
@onready var local_score: Label = %LocalScore
@onready var peer_score: Label = %PeerScore
@onready var round_label: Label = %RoundLabel
@onready var stage_status: Label = %StageStatus
@onready var timer_label: Label = %TimerLabel
@onready var footer_label: Label = %FooterLabel
@onready var hint_label: Label = %HintLabel
@onready var start_button: Button = %StartButton
@onready var menu_button: Button = %MenuButton

var lobby_tag: int = 0
var lobby_local_name: String = ""
var lobby_peer_name: String = ""
var show_menu_button: bool = false
var prefer_reduced_motion: bool = false

var _scores: Array[int] = [0, 0]
var _round_number: int = 0
var _winner_id: int = -1
var _countdown: float = 0.0
var _elapsed: float = 0.0
var _state_timer: float = 0.0

var _ball_pos: Vector2 = Vector2.ZERO
var _ball_vel: Vector2 = Vector2.ZERO
var _peer_pos: Vector2 = Vector2.ZERO
var _raw_tilt: Vector2 = Vector2.ZERO
var _base_tilt: Vector2 = Vector2.ZERO
var _has_calibrated: bool = false
var _wind: Vector2 = Vector2.ZERO
var _wind_target: Vector2 = Vector2.ZERO
var _wind_timer: float = 0.0
var _touch_anchor: Vector2 = Vector2.ZERO
var _touch_tilt: Vector2 = Vector2.ZERO
var _is_dragging: bool = false

func _ready() -> void:
	game_id = 2
	game_title = "Denge"
	super._ready()
	artwork.prefer_reduced_motion = prefer_reduced_motion
	start_button.pressed.connect(_on_start_button_pressed)
	menu_button.pressed.connect(func() -> void: leave_lobby_requested.emit())
	menu_button.visible = show_menu_button or lobby_tag != 0
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()
	_refresh_ui()

func _process(delta: float) -> void:
	if not is_round_active:
		return

	if _countdown > 0.0:
		_countdown = maxf(0.0, _countdown - delta)
		if _countdown <= 0.0:
			_base_tilt = _raw_tilt
			_has_calibrated = true
		_refresh_ui()
		return

	_elapsed += delta
	_wind_timer -= delta
	if _wind_timer <= 0.0:
		_wind_timer = rng.randf_range(1.4, 2.6)
		var angle: float = rng.randf_range(0.0, TAU)
		var strength: float = minf(0.95, 0.28 + _elapsed * 0.025)
		_wind_target = Vector2(cos(angle), sin(angle)) * strength
	_wind = _wind.lerp(_wind_target, minf(1.0, delta * 2.5))

	var rel_tilt: Vector2 = Vector2.ZERO
	if _is_dragging:
		rel_tilt = _touch_tilt
	elif _has_calibrated:
		rel_tilt = Vector2(
			clampf((_raw_tilt.x - _base_tilt.x) * TILT_SENSITIVITY, -1.0, 1.0),
			clampf((_raw_tilt.y - _base_tilt.y) * TILT_SENSITIVITY, -1.0, 1.0)
		)

	_ball_vel += (rel_tilt * 1.45 + _wind) * delta
	_ball_vel -= _ball_vel * DAMPING * delta
	_ball_pos += _ball_vel * delta

	artwork.local_ball = _ball_pos
	artwork.peer_ball = _peer_pos
	artwork.wind_vec = _wind
	artwork.danger_ratio = _ball_pos.length()
	artwork.is_active = true
	artwork.is_countdown = false
	artwork.queue_redraw()
	timer_label.text = "%.1f sn" % _elapsed

	if _ball_pos.length() >= 1.0:
		_ball_pos = _ball_pos.normalized()
		artwork.local_ball = _ball_pos
		var loser_id: int = PartyNetworkBridge.local_player_id
		send_game_action(TARGET_BROADCAST, PackedByteArray([ACTION_FELL, loser_id]))
		_handle_fall(loser_id)
		return

	_state_timer -= delta
	if _state_timer <= 0.0:
		_state_timer = STATE_SYNC_INTERVAL
		var qx: int = clampi(int(roundf(_ball_pos.x * 127.0)), -127, 127) + 128
		var qy: int = clampi(int(roundf(_ball_pos.y * 127.0)), -127, 127) + 128
		send_game_action(_opponent_id(), PackedByteArray([ACTION_STATE, qx, qy]))

func _unhandled_input(event: InputEvent) -> void:
	if not is_round_active or _countdown > 0.0:
		return
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event as InputEventScreenTouch
		if touch.pressed:
			_touch_anchor = touch.position
			_is_dragging = true
		else:
			_is_dragging = false
			_touch_tilt = Vector2.ZERO
	elif event is InputEventScreenDrag and _is_dragging:
		var drag: InputEventScreenDrag = event as InputEventScreenDrag
		_touch_tilt = ((drag.position - _touch_anchor) / 90.0).limit_length(1.0)
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_touch_anchor = mb.position
				_is_dragging = true
			else:
				_is_dragging = false
				_touch_tilt = Vector2.ZERO
	elif event is InputEventMouseMotion and _is_dragging:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		_touch_tilt = ((mm.position - _touch_anchor) / 90.0).limit_length(1.0)

func _on_tilt(pitch: float, roll: float) -> void:
	_raw_tilt = Vector2(roll, -pitch)
	if not _has_calibrated and _countdown > 0.0:
		_base_tilt = _raw_tilt

func _on_start_button_pressed() -> void:
	if is_round_active:
		return
	var base_seed: int = randi()
	var new_seed: int = (base_seed & ~0xFFFF) | (lobby_tag & 0xFFFF) if lobby_tag != 0 else base_seed
	_begin_round(new_seed)
	send_game_action(TARGET_BROADCAST, PackedByteArray([ACTION_START]))

func _begin_round(seed_val: int) -> void:
	_round_number += 1
	_winner_id = -1
	_countdown = COUNTDOWN_SEC
	_elapsed = 0.0
	_state_timer = 0.0
	_ball_pos = Vector2.ZERO
	_ball_vel = Vector2.ZERO
	_peer_pos = Vector2.ZERO
	_wind = Vector2.ZERO
	_wind_target = Vector2.ZERO
	_wind_timer = 0.8
	_has_calibrated = false
	_is_dragging = false
	_touch_tilt = Vector2.ZERO
	artwork.reset_motion()
	start_round(seed_val)

func _on_round_started() -> void:
	start_button.visible = false
	artwork.is_active = true
	artwork.is_countdown = true
	_refresh_ui()

func _on_round_ended(winner_id: int) -> void:
	_winner_id = winner_id
	_scores[winner_id] += 1
	artwork.is_active = false
	artwork.is_countdown = false
	artwork.play_fall()
	_refresh_ui()

func _on_network_packet(sender_id: int, target_id: int, p_game_id: int, heading: int, seed_val: int, payload: PackedByteArray) -> void:
	if p_game_id != game_id or sender_id != _opponent_id() or payload.is_empty():
		return
	if lobby_tag != 0 and (seed_val & 0xFFFF) != lobby_tag:
		return
	if payload[0] == ACTION_START:
		if is_round_active or sender_id != 0 or target_id != TARGET_BROADCAST:
			return
		if _round_number > 0 and seed_val == current_seed:
			return
		_begin_round(seed_val)
	elif seed_val == current_seed:
		super._on_network_packet(sender_id, target_id, p_game_id, heading, seed_val, payload)

func _on_action_received(_sender_id: int, target_id: int, _heading: int, payload: PackedByteArray) -> void:
	if payload.is_empty():
		return
	var action: int = payload[0]
	if action == ACTION_STATE and payload.size() >= 3 and target_id == PartyNetworkBridge.local_player_id:
		_peer_pos = Vector2(float(payload[1] - 128) / 127.0, float(payload[2] - 128) / 127.0)
	elif action == ACTION_FELL and payload.size() >= 2 and target_id == TARGET_BROADCAST:
		_handle_fall(payload[1])

func _handle_fall(loser_id: int) -> void:
	if not is_round_active:
		return
	if loser_id == PartyNetworkBridge.local_player_id:
		Input.vibrate_handheld(500, 1.0)
	var winner_id: int = (loser_id + 1) % 2
	end_round(winner_id)

func _opponent_id() -> int:
	return (PartyNetworkBridge.local_player_id + 1) % 2

func _player_name(id: int) -> String:
	if id == PartyNetworkBridge.local_player_id:
		return lobby_local_name if not lobby_local_name.is_empty() else "Sen (%d)" % id
	return lobby_peer_name if not lobby_peer_name.is_empty() else "Rakip (%d)" % id

func _refresh_ui() -> void:
	var local_id: int = PartyNetworkBridge.local_player_id
	var opp_id: int = _opponent_id()
	local_player.text = _player_name(local_id)
	peer_player.text = _player_name(opp_id)
	local_score.text = str(_scores[local_id])
	peer_score.text = str(_scores[opp_id])
	round_label.text = "TUR %d" % maxi(_round_number, 1)

	if not is_round_active:
		start_button.visible = PartyNetworkBridge.is_host or not (PartyNetworkBridge.is_mock_mode or PartyNetworkBridge.is_lan_mode or PartyNetworkBridge.is_ble_mode)
		start_button.text = "TEKRAR OYNA" if _round_number > 0 else "TURU BAŞLAT"
		if _winner_id == -1:
			stage_status.text = "HAZIR"
			timer_label.text = "0.0 sn"
			footer_label.text = "Telefonu sabit tut"
			hint_label.text = "Eğerek veya sürükleyerek topu çemberde tut"
		elif _winner_id == local_id:
			stage_status.text = "KAZANDIN!"
			footer_label.text = "Rakibin dengesini kaybetti"
			hint_label.text = "%.1f sn dayandın" % _elapsed
		else:
			stage_status.text = "DÜŞTÜ!"
			footer_label.text = "Top çemberden çıktı"
			hint_label.text = "%.1f sn dayandın" % _elapsed
		return

	if _countdown > 0.0:
		stage_status.text = "HAZIRLAN"
		timer_label.text = str(ceili(_countdown))
		footer_label.text = "Telefonu rahat tuttuğun açıda sabitle"
		hint_label.text = "Başlıyor..."
	else:
		stage_status.text = "DENGEDE TUT!"
		footer_label.text = "Yeşil nokta: %s" % _player_name(opp_id)
		hint_label.text = "Eğ veya sürükle · WASD / Ok tuşları"

func _apply_safe_area() -> void:
	if not OS.has_feature("mobile"):
		return
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	var win_size: Vector2i = DisplayServer.window_get_size()
	if not safe.has_area() or win_size.x <= 0 or win_size.y <= 0:
		return
	var vp_size: Vector2 = get_viewport_rect().size
	var ratio: Vector2 = vp_size / Vector2(win_size)
	var trailing: Vector2i = win_size - safe.end
	main_margin.add_theme_constant_override("margin_left", maxi(20, roundi(safe.position.x * ratio.x) + 14))
	main_margin.add_theme_constant_override("margin_top", maxi(24, roundi(safe.position.y * ratio.y) + 14))
	main_margin.add_theme_constant_override("margin_right", maxi(20, roundi(trailing.x * ratio.x) + 14))
	main_margin.add_theme_constant_override("margin_bottom", maxi(24, roundi(trailing.y * ratio.y) + 14))
