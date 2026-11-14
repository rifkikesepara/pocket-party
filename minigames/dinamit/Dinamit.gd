class_name DinamitMinigame
extends MiniGameBase

const ACTION_START: int = 0x01
const ACTION_PASS: int = 0x02
const ACTION_EXPLODE: int = 0x03

const TARGET_BROADCAST: int = 0xFF
const COUNTDOWN_SEC: float = 3.0
const MIN_FUSE_SEC: float = 8.0
const MAX_FUSE_SEC: float = 16.0
const WARM: Color = Color("#ffc969")
const HOT: Color = Color("#ff6379")
const COOL: Color = Color("#88e7d4")
const NEUTRAL: Color = Color("#d4b9f3")

@onready var main_margin: MarginContainer = %MarginContainer
@onready var screen: VBoxContainer = %Screen
@onready var settings: Control = %Settings
@onready var settings_button: Button = %SettingsButton
@onready var close_settings: Button = %CloseSettings
@onready var connection: VBoxContainer = %Connection
@onready var role_button: Button = %RoleButton
@onready var ble_button: Button = %BleButton
@onready var lan_button: Button = %LanButton
@onready var ip_label: Label = %IpLabel
@onready var lan_bar: HBoxContainer = %LanBar
@onready var peer_ip_input: LineEdit = %PeerIpInput
@onready var connect_button: Button = %ConnectButton
@onready var status_label: Label = %StatusLabel
@onready var reduce_motion: CheckButton = %ReduceMotion

@onready var artwork: DinamitArtwork = %Artwork
@onready var local_player: Label = %LocalPlayer
@onready var peer_player: Label = %PeerPlayer
@onready var local_score: Label = %LocalScore
@onready var peer_score: Label = %PeerScore
@onready var round_label: Label = %RoundLabel
@onready var stage_status: Label = %StageStatus
@onready var fuse_value: Label = %FuseValue
@onready var fuse_bar: ProgressBar = %FuseBar
@onready var footer: PanelContainer = %Footer
@onready var holder_label: Label = %HolderLabel
@onready var hint_label: Label = %HintLabel
@onready var start_button: Button = %StartButton
@onready var pass_button: Button = %PassButton
@onready var flash: ColorRect = %Flash

var holder_id: int = 0
var fuse_total: float = 0.0
var fuse_remaining: float = 0.0

var _countdown: float = 0.0
var _countdown_digit: int = 0
var _pass_number: int = 0
var _round_number: int = 0
var _winner_id: int = -1
var _scores: Array[int] = [0, 0]
var _fuse_display_sec: int = -2
var _fuse_fill: StyleBoxFlat
var _footer_style: StyleBoxFlat
var _explosion_effect: Tween
var _settings_effect: Tween

func _ready() -> void:
	game_id = 1
	game_title = "Dinamit (Sıcak Patates)"
	super._ready()

	_fuse_fill = fuse_bar.get_theme_stylebox("fill").duplicate() as StyleBoxFlat
	fuse_bar.add_theme_stylebox_override("fill", _fuse_fill)
	_footer_style = footer.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	footer.add_theme_stylebox_override("panel", _footer_style)

	PartyNetworkBridge.connected_to_table.connect(_on_role_changed)
	PartyNetworkBridge.lan_peer_connected.connect(_on_lan_peer_connected)
	PartyNetworkBridge.peer_discovered.connect(_on_ble_peer_discovered)
	PartyNetworkBridge.transport_changed.connect(_on_transport_changed)
	role_button.pressed.connect(_on_role_button_pressed)
	ble_button.pressed.connect(_on_ble_button_pressed)
	lan_button.pressed.connect(PartyNetworkBridge.switch_to_lan)
	connect_button.pressed.connect(_on_connect_button_pressed)
	peer_ip_input.text_submitted.connect(_on_peer_ip_submitted)
	settings_button.pressed.connect(_open_settings)
	close_settings.pressed.connect(_close_settings)
	reduce_motion.toggled.connect(_on_reduce_motion_toggled)
	start_button.pressed.connect(_on_start_button_pressed)
	pass_button.pressed.connect(_pass_dynamite)
	get_viewport().size_changed.connect(_apply_safe_area)

	connection.visible = not PartyNetworkBridge.is_mock_mode
	_refresh_transport_ui()
	_apply_safe_area()
	_refresh_ui()

func _process(delta: float) -> void:
	if not is_round_active:
		return

	# Keep the full fuse available when the countdown reaches zero.
	if _countdown > 0.0:
		_countdown = maxf(0.0, _countdown - delta)
		var digit: int = ceili(_countdown)
		if digit != _countdown_digit:
			_countdown_digit = digit
			if digit == 0:
				_notify_dynamite_received()
			_refresh_ui()
		return

	fuse_remaining = maxf(0.0, fuse_remaining - delta)
	_refresh_fuse_visuals()

	if fuse_remaining <= 0.0 and holder_id == PartyNetworkBridge.local_player_id:
		send_game_action(TARGET_BROADCAST, _turn_payload(ACTION_EXPLODE, holder_id))
		_handle_explosion(holder_id)

func _on_start_button_pressed() -> void:
	if is_round_active or not _can_start() or settings.visible:
		return
	var seed_val: int = randi()
	var round_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	round_rng.seed = seed_val
	var initial_holder: int = round_rng.randi_range(0, 1)
	var fuse_tenths: int = roundi(round_rng.randf_range(MIN_FUSE_SEC, MAX_FUSE_SEC) * 10.0)

	_begin_round(seed_val, initial_holder, fuse_tenths)
	send_game_action(TARGET_BROADCAST, PackedByteArray([ACTION_START, initial_holder, fuse_tenths]))

func _begin_round(seed_val: int, initial_holder: int, fuse_tenths: int) -> void:
	holder_id = initial_holder
	fuse_total = float(fuse_tenths) / 10.0
	fuse_remaining = fuse_total
	_countdown = COUNTDOWN_SEC
	_countdown_digit = ceili(COUNTDOWN_SEC)
	_pass_number = 0
	_winner_id = -1
	_round_number += 1
	start_round(seed_val)

func _on_round_started() -> void:
	_close_settings(false)
	_reset_explosion_effect()
	artwork.reset_motion()
	_refresh_ui()

func _on_round_ended(winner_id: int) -> void:
	_winner_id = winner_id
	_scores[winner_id] += 1
	_refresh_ui()
	artwork.play_explosion()
	_play_explosion_effect()

func _on_flick(_locked_heading: float, _force: float) -> void:
	_pass_dynamite()

func _pass_dynamite() -> void:
	if not _can_pass() or settings.visible:
		return
	var target: int = _opponent_id()
	var fuse_tenths: int = clampi(floori(fuse_remaining * 10.0), 1, 255)
	_pass_number += 1
	holder_id = target
	send_game_action(target, _turn_payload(ACTION_PASS, fuse_tenths))
	_refresh_ui()
	artwork.play_pass(false)

func _turn_payload(action: int, value: int) -> PackedByteArray:
	# Use the spare game bytes to reject duplicate and out-of-order handoffs.
	var payload: PackedByteArray = PackedByteArray([action, value, 0, 0])
	payload.encode_u16(2, _pass_number)
	return payload

func _on_network_packet(sender_id: int, target_id: int, p_game_id: int, heading: int, seed_val: int, payload: PackedByteArray) -> void:
	if p_game_id != game_id or sender_id != _opponent_id() or payload.is_empty():
		return
	if payload[0] == ACTION_START:
		if is_round_active or sender_id != 0 or target_id != TARGET_BROADCAST:
			return
		if payload.size() < 3 or (_round_number > 0 and seed_val == current_seed):
			return
		if payload[1] > 1 or payload[2] < roundi(MIN_FUSE_SEC * 10.0) or payload[2] > roundi(MAX_FUSE_SEC * 10.0):
			return
		_begin_round(seed_val, payload[1], payload[2])
	elif seed_val == current_seed:
		super._on_network_packet(sender_id, target_id, p_game_id, heading, seed_val, payload)

func _on_action_received(sender_id: int, target_id: int, _heading: int, payload: PackedByteArray) -> void:
	if payload.size() < 4 or sender_id != holder_id:
		return
	var pass_number: int = payload.decode_u16(2)
	if payload[0] == ACTION_PASS and target_id == PartyNetworkBridge.local_player_id:
		if pass_number != _pass_number + 1 or payload[1] == 0:
			return
		# A valid pass can arrive just before the local countdown finishes.
		_countdown = 0.0
		_countdown_digit = 0
		_pass_number = pass_number
		holder_id = target_id
		fuse_remaining = minf(fuse_total, float(payload[1]) / 10.0)
		_notify_dynamite_received()
		_refresh_ui()
		artwork.play_pass(true)
	elif payload[0] == ACTION_EXPLODE and target_id == TARGET_BROADCAST:
		if pass_number == _pass_number and payload[1] == holder_id:
			_handle_explosion(payload[1])

func _notify_dynamite_received() -> void:
	if holder_id == PartyNetworkBridge.local_player_id:
		Input.vibrate_handheld(120, 0.5)

func _handle_explosion(loser_id: int) -> void:
	if loser_id == PartyNetworkBridge.local_player_id:
		Input.vibrate_handheld(600, 1.0)
	fuse_remaining = 0.0
	end_round(1 - loser_id)

func _can_start() -> bool:
	return PartyNetworkBridge.local_player_id == 0

func _can_pass() -> bool:
	return is_round_active and _countdown <= 0.0 and fuse_remaining > 0.0 and holder_id == PartyNetworkBridge.local_player_id

func _opponent_id() -> int:
	return 1 - PartyNetworkBridge.local_player_id

func _refresh_ui() -> void:
	var local_id: int = PartyNetworkBridge.local_player_id
	var peer_id: int = _opponent_id()
	if local_id not in [0, 1]:
		stage_status.text = "2 OYUNCULU MASA"
		holder_label.text = "Masa dolu"
		hint_label.text = "Dinamit için oyuncu 0 ve 1 rollerini kullan."
		start_button.hide()
		return

	local_player.text = "Oyuncu %d" % local_id
	peer_player.text = "Oyuncu %d" % peer_id
	local_score.text = str(_scores[local_id])
	peer_score.text = str(_scores[peer_id])
	role_button.text = "Oyuncu %d rolüne geç" % peer_id
	round_label.text = "TUR %02d" % maxi(1, _round_number)
	settings_button.disabled = is_round_active
	start_button.visible = not is_round_active and _can_start()
	start_button.text = "Yeniden oyna  →" if _winner_id >= 0 else "Turu başlat  →"
	pass_button.visible = _can_pass()
	artwork.countdown = _countdown_digit if is_round_active else 0
	artwork.fuse_lit = is_round_active and _countdown <= 0.0
	artwork.show_swipe = pass_button.visible
	artwork.exploded = not is_round_active and _winner_id >= 0

	var accent: Color = NEUTRAL
	if artwork.exploded:
		var won: bool = _winner_id == local_id
		accent = COOL if won else HOT
		stage_status.text = "●  PATLADI"
		holder_label.text = "Turu kazandın!" if won else "Tur rakibin!"
		hint_label.text = "Dinamit rakibinde patladı." if won else "Dinamit sende patladı."
		if not _can_start():
			hint_label.text += " Yeni turu Oyuncu 0 başlatır."
	elif is_round_active and _countdown > 0.0:
		stage_status.text = "●  BAŞLIYOR"
		holder_label.text = "Hazır ol!"
		hint_label.text = "İlk dinamit sende." if holder_id == local_id else "İlk dinamit rakibinde."
	elif is_round_active:
		var has_dynamite: bool = holder_id == local_id
		accent = WARM if has_dynamite else COOL
		stage_status.text = "●  SENDE" if has_dynamite else "●  RAKİPTE"
		holder_label.text = "Dinamit sende!" if has_dynamite else "Dinamit rakipte"
		hint_label.text = "Yukarı kaydır veya cihazı savur." if has_dynamite else "Hazır bekle, rakibin dinamiti sana atabilir."
		if has_dynamite and not OS.has_feature("mobile"):
			hint_label.text = "Yukarı kaydır veya Space’e bas."
	else:
		stage_status.text = "●  HAZIR" if _can_start() else "●  BEKLİYOR"
		holder_label.text = "Masayı hazırla" if _can_start() else "Hazır bekle"
		hint_label.text = "Fitil bitmeden dinamiti rakibine gönder." if _can_start() else "Oyuncu 0 turu başlattığında geri sayım başlar."

	artwork.accent = accent
	stage_status.add_theme_color_override("font_color", accent)
	holder_label.add_theme_color_override("font_color", accent)
	_footer_style.border_color = Color(accent, 0.42)
	_refresh_fuse_visuals()

func _refresh_fuse_visuals() -> void:
	var burning: bool = artwork.fuse_lit
	var fraction: float = clampf(fuse_remaining / fuse_total, 0.0, 1.0) if burning else 0.0
	fuse_bar.value = fraction
	var seconds: int = ceili(fuse_remaining) if burning else (0 if artwork.exploded else -1)
	if seconds != _fuse_display_sec:
		_fuse_display_sec = seconds
		fuse_value.text = "%d sn" % seconds if seconds >= 0 else "—"
	var danger: float = 1.0 - smoothstep(0.0, 4.0, fuse_remaining) if burning else 0.0
	var color: Color = artwork.accent.lerp(HOT, danger)
	fuse_value.add_theme_color_override("font_color", color)
	_fuse_fill.bg_color = color
	artwork.fuse_fraction = fraction
	artwork.danger = danger
	artwork.queue_redraw()

func _play_explosion_effect() -> void:
	if reduce_motion.button_pressed:
		return
	flash.color.a = 0.58
	flash.show()
	_explosion_effect = create_tween().set_parallel()
	_explosion_effect.tween_property(flash, "color:a", 0.0, 0.24).set_trans(Tween.TRANS_QUAD)
	_explosion_effect.tween_method(_shake_screen, 1.0, 0.0, 0.32).set_trans(Tween.TRANS_QUAD)
	_explosion_effect.chain().tween_callback(_reset_explosion_effect)

func _shake_screen(strength: float) -> void:
	var phase: float = (1.0 - strength) * TAU * 2.5
	screen.position = Vector2(sin(phase), sin(phase * 1.73)) * 7.0 * strength

func _reset_explosion_effect() -> void:
	if _explosion_effect != null:
		_explosion_effect.kill()
		_explosion_effect = null
	screen.position = Vector2.ZERO
	flash.hide()

func _open_settings() -> void:
	if is_round_active:
		return
	settings.show()
	screen.hide()
	close_settings.grab_focus()
	if not reduce_motion.button_pressed:
		settings.modulate.a = 0.0
		_settings_effect = create_tween()
		_settings_effect.tween_property(settings, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _close_settings(restore_focus: bool = true) -> void:
	var was_open: bool = settings.visible
	if _settings_effect != null:
		_settings_effect.kill()
		_settings_effect = null
	settings.modulate.a = 1.0
	settings.hide()
	screen.show()
	if was_open and restore_focus:
		settings_button.grab_focus()

func _on_reduce_motion_toggled(enabled: bool) -> void:
	artwork.reduced_motion = enabled
	artwork.reset_motion()
	_reset_explosion_effect()

func _on_connect_button_pressed() -> void:
	var ip: String = peer_ip_input.text.strip_edges()
	if not ip.is_valid_ip_address() or not ip.contains("."):
		status_label.text = "Geçerli bir IPv4 adresi gir."
		return
	PartyNetworkBridge.connect_lan_peer(ip)
	status_label.text = "%s adresine bağlantı isteği gönderildi." % ip
	peer_ip_input.release_focus()

func _on_peer_ip_submitted(_text: String) -> void:
	_on_connect_button_pressed()

func _on_lan_peer_connected(peer_ip: String) -> void:
	status_label.text = "%s bağlandı." % peer_ip

func _on_ble_peer_discovered(_id: int, peer_name: String, rssi: int) -> void:
	status_label.text = "%s bulundu (%d dBm)." % [peer_name, rssi]

func _on_role_button_pressed() -> void:
	PartyNetworkBridge.set_local_player_id(_opponent_id())

func _on_role_changed(local_id: int, _host: bool) -> void:
	SensorGestureController.current_target_id = 1 - local_id
	_refresh_ui()

func _on_ble_button_pressed() -> void:
	if not PartyNetworkBridge.switch_to_ble():
		status_label.text = "Bu cihazda yerel Bluetooth yok. Wi-Fi / LAN kullan."

func _on_transport_changed(_mode_name: String) -> void:
	_refresh_transport_ui()

func _refresh_transport_ui() -> void:
	lan_bar.visible = PartyNetworkBridge.is_lan_mode
	ip_label.visible = PartyNetworkBridge.is_lan_mode
	ip_label.text = "Bu cihaz  %s · 42425" % PartyNetworkBridge.get_local_lan_ip()
	ble_button.disabled = PartyNetworkBridge.is_ble_mode
	lan_button.disabled = PartyNetworkBridge.is_lan_mode
	if PartyNetworkBridge.is_mock_mode:
		status_label.text = "Yerel UDP test modu"
	elif PartyNetworkBridge.is_ble_mode:
		status_label.text = "Bağlantı modu  ·  Bluetooth"
	elif PartyNetworkBridge.is_lan_mode:
		status_label.text = "Bağlantı modu  ·  Wi-Fi / LAN"
	else:
		status_label.text = "Bağlantı kurulamadı."

func _apply_safe_area() -> void:
	if not OS.has_feature("mobile"):
		return
	var safe_rect: Rect2i = DisplayServer.get_display_safe_area()
	var win_size: Vector2i = DisplayServer.window_get_size()
	if win_size.x <= 0 or win_size.y <= 0 or not safe_rect.has_area():
		return
	var viewport_scale: Vector2 = get_viewport_rect().size / Vector2(win_size)
	var trailing: Vector2i = win_size - safe_rect.end
	main_margin.add_theme_constant_override("margin_left", maxi(24, roundi(safe_rect.position.x * viewport_scale.x) + 16))
	main_margin.add_theme_constant_override("margin_top", maxi(24, roundi(safe_rect.position.y * viewport_scale.y) + 16))
	main_margin.add_theme_constant_override("margin_right", maxi(24, roundi(trailing.x * viewport_scale.x) + 16))
	main_margin.add_theme_constant_override("margin_bottom", maxi(24, roundi(trailing.y * viewport_scale.y) + 16))
