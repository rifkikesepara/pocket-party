extends Node

signal peer_discovered(peer_id: int, peer_name: String, rssi: int)
signal connected_to_table(local_id: int, is_host: bool)
signal packet_received(sender_id: int, target_id: int, game_id: int, heading: int, seed_val: int, payload: PackedByteArray)

const PACKET_SIZE: int = 16
const MOCK_BASE_PORT: int = 42420

enum PacketType {
	CALIBRATION = 0x01,
	GAME_ACTION = 0x02,
	ROUND_END = 0x03,
	GAME_OVER = 0x04
}

var local_player_id: int = 0
var is_host: bool = false
var is_mock_mode: bool = false
var connected_peers: Dictionary = {} # { player_id: { "name": String, "heading": float } }

var _mock_udp: PacketPeerUDP = PacketPeerUDP.new()
var _ble_plugin: Object = null

func _ready() -> void:
	_parse_cli_args()
	if is_mock_mode:
		_init_mock_network()
	else:
		_init_native_ble()

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
			peer_discovered.emit(id, p_name, rssi)
		)
	else:
		push_warning("[PartyNetworkBridge] Native BLE eklentisi bulunamadı, tek oyunculu/mock moda geçiliyor.")

func _process(_delta: float) -> void:
	if is_mock_mode and _mock_udp.get_available_packet_count() > 0:
		var raw: PackedByteArray = _mock_udp.get_packet()
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
	elif _ble_plugin != null:
		_ble_plugin.send_ble_packet(packet)

func _on_raw_packet_arrived(packet: PackedByteArray) -> void:
	if packet.size() != PACKET_SIZE:
		return
	if packet.decode_u8(15) != _calculate_checksum(packet):
		push_warning("[PartyNetworkBridge] Checksum hatası, paket düşürüldü.")
		return
		
	var sender_id: int = packet.decode_u8(1)
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