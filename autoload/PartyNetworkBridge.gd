extends Node

signal peer_discovered(peer_id: int, peer_name: String, rssi: int)
signal connected_to_table(local_id: int, is_host: bool)
signal packet_received(sender_id: int, target_id: int, game_id: int, heading: int, seed_val: int, payload: PackedByteArray)
signal lan_peer_connected(peer_ip: String)
signal transport_changed(mode_name: String)

const PACKET_SIZE: int = 16
const MOCK_BASE_PORT: int = 42420
const LAN_PORT: int = 42425

enum PacketType {
	CALIBRATION = 0x01,
	GAME_ACTION = 0x02,
	ROUND_END = 0x03,
	GAME_OVER = 0x04
}

var local_player_id: int = 0
var is_host: bool = false
var is_mock_mode: bool = false
var is_lan_mode: bool = false
var is_ble_mode: bool = false
var connected_peers: Dictionary = {} # { player_id: { "name": String, "heading": float } }

var _mock_udp: PacketPeerUDP = PacketPeerUDP.new()
var _lan_udp: PacketPeerUDP = PacketPeerUDP.new()
var _lan_peers: Dictionary = {}
var _ble_plugin: Object = null

func _ready() -> void:
	_parse_cli_args()
	if is_mock_mode:
		_init_mock_network()
	else:
		_init_native_ble()

func set_local_player_id(player_id: int) -> void:
	local_player_id = clampi(player_id, 0, 7)
	is_host = (local_player_id == 0)
	connected_to_table.emit(local_player_id, is_host)

func get_local_lan_ip() -> String:
	for addr: String in IP.get_local_addresses():
		if addr.contains(".") and not addr.begins_with("127.") and not addr.begins_with("169.254."):
			return addr
	return "127.0.0.1"

func connect_lan_peer(peer_ip: String, peer_port: int = LAN_PORT) -> void:
	var clean_ip: String = peer_ip.strip_edges()
	if clean_ip.is_empty():
		return
	var key: String = "%s:%d" % [clean_ip, peer_port]
	_lan_peers[key] = { "ip": clean_ip, "port": peer_port }
	send_packet(PacketType.CALIBRATION, 0xFF, 0, 0, 0, PackedByteArray())

func _parse_cli_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--mock-player="):
			is_mock_mode = true
			local_player_id = arg.split("=")[1].to_int()
			is_host = (local_player_id == 0)

func _init_mock_network() -> void:
	var port: int = MOCK_BASE_PORT + local_player_id
	var err: Error = _mock_udp.bind(port, "127.0.0.1")
	if err == OK:
		print("[PartyNetworkBridge] Mock UDP aktif. Oyuncu ID: %d, Port: %d" % [local_player_id, port])
		connected_to_table.emit(local_player_id, is_host)
	else:
		push_error("[PartyNetworkBridge] Mock UDP portu bağlanamadı: %d" % port)

func _init_native_ble() -> void:
	if Engine.has_singleton("PocketPartyBLE"):
		_ble_plugin = Engine.get_singleton("PocketPartyBLE")
		_ble_plugin.connect("on_ble_packet", _on_raw_packet_arrived)
		_ble_plugin.connect("on_peer_found", func(id: int, p_name: String, rssi: int) -> void:
			connected_peers[id] = { "name": p_name, "rssi": rssi }
			peer_discovered.emit(id, p_name, rssi)
		)
		call_deferred("switch_to_ble")
	else:
		push_warning("[PartyNetworkBridge] Native BLE eklentisi bulunamadı, LAN UDP test moduna geçiliyor.")
		_init_lan_network()

func switch_to_ble() -> bool:
	if _ble_plugin == null:
		if Engine.has_singleton("PocketPartyBLE"):
			_ble_plugin = Engine.get_singleton("PocketPartyBLE")
		else:
			push_warning("[PartyNetworkBridge] Bu platformda native BLE eklentisi yok.")
			return false
	if is_lan_mode:
		_lan_udp.close()
		is_lan_mode = false
	is_ble_mode = true
	if _ble_plugin.has_method("start_ble"):
		_ble_plugin.call("start_ble")
	if local_player_id == 0 and OS.get_name() in ["iOS", "Android"]:
		set_local_player_id(1)
	transport_changed.emit("BLE")
	print("[PartyNetworkBridge] Native BLE aktif. Oyuncu ID: %d" % local_player_id)
	return true

func switch_to_lan() -> void:
	if is_ble_mode and _ble_plugin != null and _ble_plugin.has_method("stop_ble"):
		_ble_plugin.call("stop_ble")
	is_ble_mode = false
	if not is_lan_mode:
		_init_lan_network()
	else:
		transport_changed.emit("LAN_UDP")

func _init_lan_network() -> void:
	var default_id: int = 1 if OS.get_name() in ["iOS", "Android"] else 0
	set_local_player_id(default_id)
	var err: Error = _lan_udp.bind(LAN_PORT, "*")
	if err == OK:
		_lan_udp.set_broadcast_enabled(true)
		is_lan_mode = true
		transport_changed.emit("LAN_UDP")
		print("[PartyNetworkBridge] LAN UDP aktif. Oyuncu ID: %d, Port: %d" % [local_player_id, LAN_PORT])
	else:
		push_warning("[PartyNetworkBridge] LAN UDP portu bağlanamadı: %d" % LAN_PORT)

func _process(_delta: float) -> void:
	if is_mock_mode and _mock_udp.get_available_packet_count() > 0:
		var raw: PackedByteArray = _mock_udp.get_packet()
		_on_raw_packet_arrived(raw)
	elif is_lan_mode:
		while _lan_udp.get_available_packet_count() > 0:
			var raw: PackedByteArray = _lan_udp.get_packet()
			var peer_ip: String = _lan_udp.get_packet_ip()
			var peer_port: int = _lan_udp.get_packet_port()
			var key: String = "%s:%d" % [peer_ip, peer_port]
			if not peer_ip.is_empty() and not _lan_peers.has(key):
				_lan_peers[key] = { "ip": peer_ip, "port": peer_port }
				lan_peer_connected.emit(peer_ip)
				send_packet(PacketType.CALIBRATION, 0xFF, 0, 0, 0, PackedByteArray())
			_on_raw_packet_arrived(raw)

func send_packet(p_type: int, target_id: int, game_id: int, heading: int, seed_val: int, custom_payload: PackedByteArray) -> void:
	var packet: PackedByteArray = PackedByteArray()
	packet.resize(PACKET_SIZE)
	packet.fill(0)
	
	packet.encode_u8(0, p_type)
	packet.encode_u8(1, local_player_id)
	packet.encode_u8(2, target_id)
	packet.encode_u8(3, game_id)
	packet.encode_u16(4, clampi(heading, 0, 360))
	packet.encode_u32(6, seed_val)
	
	var copy_len: int = mini(custom_payload.size(), 5)
	for i: int in range(copy_len):
		packet.encode_u8(10 + i, custom_payload[i])
	
	packet.encode_u8(15, _calculate_checksum(packet))
	_dispatch_raw_packet(packet)

func _dispatch_raw_packet(packet: PackedByteArray) -> void:
	if is_mock_mode:
		# Mock modda 0-3 arası tüm yerel portlara yayın yap
		for peer_id: int in range(4):
			if peer_id != local_player_id:
				_mock_udp.set_dest_address("127.0.0.1", MOCK_BASE_PORT + peer_id)
				_mock_udp.put_packet(packet)
	elif is_lan_mode:
		_broadcast_lan_packet(packet)
	elif _ble_plugin != null:
		_ble_plugin.send_ble_packet(packet)

func _broadcast_lan_packet(packet: PackedByteArray) -> void:
	for peer_info: Dictionary in _lan_peers.values():
		_lan_udp.set_dest_address(peer_info["ip"], peer_info["port"])
		_lan_udp.put_packet(packet)
	var sent_targets: Dictionary = {}
	for addr: String in IP.get_local_addresses():
		if addr.contains(".") and not addr.begins_with("127.") and not addr.begins_with("169.254."):
			var parts: PackedStringArray = addr.split(".")
			if parts.size() == 4:
				var bcast: String = "%s.%s.%s.255" % [parts[0], parts[1], parts[2]]
				if not sent_targets.has(bcast):
					sent_targets[bcast] = true
					_lan_udp.set_dest_address(bcast, LAN_PORT)
					_lan_udp.put_packet(packet)
	_lan_udp.set_dest_address("255.255.255.255", LAN_PORT)
	_lan_udp.put_packet(packet)

func _on_raw_packet_arrived(packet: PackedByteArray) -> void:
	if packet.size() != PACKET_SIZE:
		return
	if packet.decode_u8(15) != _calculate_checksum(packet):
		push_warning("[PartyNetworkBridge] Checksum hatası, paket düşürüldü.")
		return
		
	var sender_id: int = packet.decode_u8(1)
	if sender_id == local_player_id:
		return
	var target_id: int = packet.decode_u8(2)
	var game_id: int = packet.decode_u8(3)
	var heading: int = packet.decode_u16(4)
	var seed_val: int = packet.decode_u32(6)
	var payload: PackedByteArray = packet.slice(10, 15)
	
	packet_received.emit(sender_id, target_id, game_id, heading, seed_val, payload)

func _calculate_checksum(packet: PackedByteArray) -> int:
	var xor_val: int = 0
	for i: int in range(15):
		xor_val ^= packet[i]
	return xor_val