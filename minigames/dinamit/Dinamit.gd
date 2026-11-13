class_name DinamitMinigame
extends MiniGameBase

const ACTION_START: int = 0x01
const ACTION_PASS: int = 0x02
const ACTION_EXPLODE: int = 0x03

const TARGET_BROADCAST: int = 0xFF
const MIN_FUSE_SEC: float = 8.0
const MAX_FUSE_SEC: float = 16.0

@onready var player_label: Label = %PlayerLabel
@onready var ip_label: Label = %IpLabel
@onready var lan_bar: HBoxContainer = %LanBar
@onready var peer_ip_input: LineEdit = %PeerIpInput
@onready var connect_button: Button = %ConnectButton
@onready var status_label: Label = %StatusLabel
@onready var holder_label: Label = %HolderLabel
@onready var target_label: Label = %TargetLabel
@onready var fuse_bar: ProgressBar = %FuseBar
@onready var start_button: Button = %StartButton
@onready var background_panel: ColorRect = %Background

var holder_id: int = 0
var selected_target_id: int = 1
var fuse_total: float = 12.0
var fuse_remaining: float = 0.0

func _ready() -> void:
	game_id = 1
	game_title = "Dinamit (Sıcak Patates)"
	super._ready()
	PartyNetworkBridge.packet_received.connect(_on_pre_round_packet)
	PartyNetworkBridge.lan_peer_connected.connect(_on_lan_peer_connected)
	start_button.pressed.connect(_on_start_button_pressed)
	connect_button.pressed.connect(_on_connect_button_pressed)

	lan_bar.visible = PartyNetworkBridge.is_lan_mode
	ip_label.visible = PartyNetworkBridge.is_lan_mode
	ip_label.text = "IP: %s (Port 42425)" % PartyNetworkBridge.get_local_lan_ip()

	selected_target_id = SensorGestureController.current_target_id
	_refresh_ui()

func _process(delta: float) -> void:
	if not is_round_active:
		return

	fuse_remaining = maxf(0.0, fuse_remaining - delta)
	_refresh_fuse_visuals()

	if fuse_remaining <= 0.0 and holder_id == PartyNetworkBridge.local_player_id:
		var payload: PackedByteArray = PackedByteArray([ACTION_EXPLODE, holder_id])
		send_game_action(TARGET_BROADCAST, payload)
		_handle_explosion(holder_id)

func _on_connect_button_pressed() -> void:
	var ip: String = peer_ip_input.text.strip_edges()
	if ip.is_empty():
		return
	PartyNetworkBridge.connect_lan_peer(ip)
	status_label.text = "Ping gönderildi: %s" % ip

func _on_lan_peer_connected(peer_ip: String) -> void:
	status_label.text = "Bağlandı: %s" % peer_ip

func _on_start_button_pressed() -> void:
	if is_round_active:
		return
	var new_seed: int = randi()
	start_round(new_seed)

	var initial_holder: int = rng.randi_range(0, 1)
	var fuse_sec: float = rng.randf_range(MIN_FUSE_SEC, MAX_FUSE_SEC)
	var fuse_tenths: int = clampi(int(roundf(fuse_sec * 10.0)), 10, 255)

	holder_id = initial_holder
	fuse_total = float(fuse_tenths) / 10.0
	fuse_remaining = fuse_total

	var payload: PackedByteArray = PackedByteArray([ACTION_START, initial_holder, fuse_tenths])
	send_game_action(TARGET_BROADCAST, payload)
	_notify_dynamite_received()
	_refresh_ui()

func _on_round_started() -> void:
	start_button.visible = false
	status_label.text = "Tur başladı!"
	_refresh_ui()

func _on_round_ended(_winner_id: int) -> void:
	start_button.visible = PartyNetworkBridge.is_host or not PartyNetworkBridge.is_mock_mode
	_refresh_ui()

func _on_aim_changed(target_player_id: int) -> void:
	selected_target_id = target_player_id
	_refresh_ui()

func _on_flick(_locked_heading: float, _force: float) -> void:
	if not is_round_active:
		return
	if holder_id != PartyNetworkBridge.local_player_id:
		return
	if selected_target_id == PartyNetworkBridge.local_player_id:
		return

	var fuse_tenths: int = clampi(int(roundf(fuse_remaining * 10.0)), 1, 255)
	var payload: PackedByteArray = PackedByteArray([ACTION_PASS, fuse_tenths])
	var target: int = selected_target_id
	holder_id = target
	send_game_action(target, payload)
	_refresh_ui()

func _on_pre_round_packet(_sender_id: int, _target_id: int, p_game_id: int, _heading: int, seed_val: int, payload: PackedByteArray) -> void:
	if p_game_id != game_id or is_round_active:
		return
	if payload.size() >= 3 and payload[0] == ACTION_START:
		start_round(seed_val)
		holder_id = payload[1]
		fuse_total = float(payload[2]) / 10.0
		fuse_remaining = fuse_total
		_notify_dynamite_received()
		_refresh_ui()

func _on_action_received(_sender_id: int, target_id: int, _heading: int, payload: PackedByteArray) -> void:
	if payload.is_empty():
		return

	var action: int = payload[0]
	if action == ACTION_PASS and payload.size() >= 2:
		holder_id = target_id
		fuse_remaining = float(payload[1]) / 10.0
		_notify_dynamite_received()
		_refresh_ui()
	elif action == ACTION_EXPLODE and payload.size() >= 2:
		_handle_explosion(payload[1])

func _notify_dynamite_received() -> void:
	if holder_id == PartyNetworkBridge.local_player_id:
		Input.vibrate_handheld(120, 0.5)

func _handle_explosion(loser_id: int) -> void:
	if loser_id == PartyNetworkBridge.local_player_id:
		Input.vibrate_handheld(600, 1.0)
	var winner_id: int = (loser_id + 1) % 2
	status_label.text = "BOOM! Oyuncu %d patladı!" % loser_id
	end_round(winner_id)

func _refresh_ui() -> void:
	var local_id: int = PartyNetworkBridge.local_player_id
	var role_tag: String = " (Host)" if PartyNetworkBridge.is_host else ""
	player_label.text = "Oyuncu %d%s" % [local_id, role_tag]
	target_label.text = "Hedef: Oyuncu %d  (Sol/Sağ Ok)" % selected_target_id

	if not is_round_active:
		holder_label.text = "Bekleniyor..."
		start_button.visible = PartyNetworkBridge.is_host or not PartyNetworkBridge.is_mock_mode
		background_panel.color = Color(0.12, 0.14, 0.18)
		fuse_bar.value = 0.0
		return

	if holder_id == local_id:
		holder_label.text = "DİNAMİT SENDE!\n[SPACE] veya Yukarı Kaydır"
		background_panel.color = Color(0.45, 0.12, 0.12)
	else:
		holder_label.text = "Dinamit: Oyuncu %d" % holder_id
		background_panel.color = Color(0.12, 0.18, 0.24)

	_refresh_fuse_visuals()

func _refresh_fuse_visuals() -> void:
	if fuse_total <= 0.0:
		fuse_bar.value = 0.0
		return
	fuse_bar.value = (fuse_remaining / fuse_total) * 100.0
