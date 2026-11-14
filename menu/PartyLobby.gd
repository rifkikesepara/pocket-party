class_name PartyLobby
extends Node

signal changed
signal game_requested
signal lobby_ended(message: String)

enum State { IDLE, SEARCHING, JOINING, HOST, GUEST, PLAYING }
enum Message { BEACON = 128, JOIN, ACCEPT, PRESENT, LEAVE, START, READY, OPEN_PROFILE = 144, MEMBER_PROFILE = 160 }

const BROADCAST: int = 255
const HOST_ID: int = 0
const GUEST_ID: int = 1
const TIMEOUT_MS: int = 6500
const TICK_SEC: float = 0.85
const FRAGMENT_INTERVAL: float = 0.045

class NearbyRoom:
	var last_seen: int
	var profile: PartyProfile
	var chunks: PackedByteArray
	var received: int = 0

var state: State = State.IDLE
var local_profile: PartyProfile
var peer_profile: PartyProfile
var rooms: Dictionary[int, NearbyRoom] = {}
var room_id: int = 0
var starting: bool = false

var _host: bool = false
var _previous_player_id: int = 0
var _member_token: int = 0
var _last_seen: int = 0
var _until_tick: float = 0.0
var _until_fragment: float = 0.0
var _member_chunks: PackedByteArray
var _member_received: int = 0
var _pending: Array[PackedByteArray] = []
var _profile_confirmed: bool = false
var _send_start_next: bool = false

func _ready() -> void:
	PartyNetworkBridge.lobby_packet_received.connect(_on_packet)

func open(profile: PartyProfile) -> bool:
	if not _prepare(profile, HOST_ID):
		return false
	_host = true
	room_id = _new_token()
	state = State.HOST
	_tick()
	changed.emit()
	return true

func scan(profile: PartyProfile) -> bool:
	if not _prepare(profile, GUEST_ID):
		return false
	state = State.SEARCHING
	changed.emit()
	return true

func join(id: int) -> void:
	if state != State.SEARCHING or not rooms.has(id) or rooms[id].profile == null:
		return
	room_id = id
	peer_profile = rooms[id].profile
	_member_token = _new_token()
	_last_seen = Time.get_ticks_msec()
	state = State.JOINING
	_tick()
	changed.emit()

func start_game() -> void:
	if state != State.HOST or peer_profile == null or starting:
		return
	starting = true
	_send_start_next = true
	_tick()
	changed.emit()

func leave() -> void:
	if _member_token != 0:
		_send(_peer_id(), _member_token, Message.LEAVE)
	_reset()

func game_tag() -> int:
	return 1 + _member_token % 65535

func _prepare(profile: PartyProfile, role: int) -> bool:
	if state != State.IDLE:
		return false
	if not PartyNetworkBridge.is_mock_mode and not PartyNetworkBridge.is_pc_ble_bridge_mode and not PartyNetworkBridge.switch_to_ble():
		return false
	_previous_player_id = PartyNetworkBridge.local_player_id
	PartyNetworkBridge.set_local_player_id(role)
	local_profile = profile
	return true

func _reset() -> void:
	if state != State.IDLE:
		PartyNetworkBridge.set_local_player_id(_previous_player_id)
	state = State.IDLE
	starting = false
	_host = false
	room_id = 0
	rooms.clear()
	_until_tick = 0.0
	_clear_member()
	changed.emit()

func _clear_member() -> void:
	peer_profile = null
	_member_token = 0
	_last_seen = 0
	_member_received = 0
	_member_chunks = PackedByteArray()
	_pending.clear()
	_profile_confirmed = false
	_send_start_next = false

func _process(delta: float) -> void:
	if state == State.IDLE:
		return
	var now: int = Time.get_ticks_msec()
	for id: int in rooms.keys():
		if now - rooms[id].last_seen > TIMEOUT_MS:
			rooms.erase(id)
			if state == State.SEARCHING:
				changed.emit()
	if _member_token != 0 and now - _last_seen > TIMEOUT_MS:
		_member_departed("Rakibin bağlantısı kesildi.")
	_until_tick -= delta
	_until_fragment -= delta
	if _until_tick <= 0.0:
		_tick()
	elif _until_fragment <= 0.0 and not _pending.is_empty():
		# Space profile fragments across frames for BLE write capacity.
		_until_fragment = FRAGMENT_INTERVAL
		PartyNetworkBridge.send_lobby_packet(BROADCAST if _host and _member_token == 0 else _peer_id(), room_id if _host and _member_token == 0 else _member_token, _pending.pop_front())

func _tick() -> void:
	_until_tick = TICK_SEC
	_until_fragment = FRAGMENT_INTERVAL
	_pending.clear()
	match state:
		State.HOST:
			if _member_token == 0:
				_send(BROADCAST, room_id, Message.BEACON)
				_queue_profile(Message.OPEN_PROFILE)
			elif starting and _send_start_next:
				_send(GUEST_ID, _member_token, Message.START)
				_send_start_next = false
			else:
				var token: PackedByteArray = PackedByteArray([0, 0, 0, 0])
				token.encode_u32(0, _member_token)
				_send(GUEST_ID, room_id, Message.ACCEPT, token)
				_send_start_next = starting
		State.JOINING:
			var token: PackedByteArray = PackedByteArray([0, 0, 0, 0])
			token.encode_u32(0, _member_token)
			_send(HOST_ID, room_id, Message.JOIN, token)
		State.GUEST:
			_send(HOST_ID, _member_token, Message.PRESENT)
			if not _profile_confirmed:
				_queue_profile(Message.MEMBER_PROFILE)
		State.PLAYING:
			_send(_peer_id(), _member_token, Message.PRESENT if _host else Message.READY)

func _on_packet(sender: int, target: int, id: int, data: PackedByteArray) -> void:
	if state == State.IDLE or sender != _peer_id() or target not in [PartyNetworkBridge.local_player_id, BROADCAST]:
		return
	var command: int = data[0]
	var now: int = Time.get_ticks_msec()
	if state == State.SEARCHING and target == BROADCAST:
		_read_announcement(id, command, data, now)
		return
	if state == State.HOST and command == Message.JOIN and id == room_id:
		var token: int = data.decode_u32(1)
		if token != 0 and (_member_token == 0 or token == _member_token):
			if _member_token == 0:
				_member_token = token
				_last_seen = now
				_tick()
			elif peer_profile == null:
				_last_seen = now
		return
	if state == State.JOINING and command == Message.ACCEPT and id == room_id and data.decode_u32(1) == _member_token:
		state = State.GUEST
		_last_seen = now
		_tick()
		changed.emit()
		return
	if _member_token == 0 or state == State.JOINING:
		return
	if state == State.GUEST and command == Message.ACCEPT and id == room_id and data.decode_u32(1) == _member_token:
		_last_seen = now
		return
	if id != _member_token:
		return
	match command:
		Message.LEAVE:
			_member_departed("Rakibin lobiden ayrıldı.")
		Message.PRESENT:
			_last_seen = now
			if state == State.GUEST:
				_profile_confirmed = true
		Message.START:
			if state == State.GUEST:
				_last_seen = now
				_enter_game()
		Message.READY:
			if state == State.HOST and starting:
				_last_seen = now
				_enter_game()
			elif state == State.PLAYING:
				_last_seen = now
		_:
			if state == State.HOST and peer_profile == null:
				_read_member_profile(command, data)

func _read_announcement(id: int, command: int, data: PackedByteArray, now: int) -> void:
	if id == 0:
		return
	if command == Message.BEACON:
		if not rooms.has(id):
			if rooms.size() >= 12:
				return
			var entry: NearbyRoom = NearbyRoom.new()
			entry.chunks.resize(PartyProfile.WIRE_SIZE)
			rooms[id] = entry
		rooms[id].last_seen = now
		return
	var index: int = command - Message.OPEN_PROFILE
	if not rooms.has(id) or index < 0 or index >= PartyProfile.CHUNK_COUNT:
		return
	var entry: NearbyRoom = rooms[id]
	if entry.profile != null:
		return
	entry.received = _read_fragment(entry.chunks, entry.received, index, data)
	if entry.received == (1 << PartyProfile.CHUNK_COUNT) - 1:
		entry.profile = PartyProfile.decode(entry.chunks)
		entry.received = 0
		if entry.profile != null:
			changed.emit()

func _read_member_profile(command: int, data: PackedByteArray) -> void:
	var index: int = command - Message.MEMBER_PROFILE
	if index < 0 or index >= PartyProfile.CHUNK_COUNT:
		return
	if _member_chunks.is_empty():
		_member_chunks.resize(PartyProfile.WIRE_SIZE)
	_member_received = _read_fragment(_member_chunks, _member_received, index, data)
	if _member_received == (1 << PartyProfile.CHUNK_COUNT) - 1:
		peer_profile = PartyProfile.decode(_member_chunks)
		_member_received = 0
		if peer_profile != null:
			_send(GUEST_ID, _member_token, Message.PRESENT)
			changed.emit()

func _read_fragment(wire: PackedByteArray, mask: int, index: int, data: PackedByteArray) -> int:
	for byte: int in range(4):
		wire[index * 4 + byte] = data[1 + byte]
	return mask | (1 << index)

func _queue_profile(base_command: int) -> void:
	var wire: PackedByteArray = local_profile.encode()
	for index: int in range(PartyProfile.CHUNK_COUNT):
		var payload: PackedByteArray = PackedByteArray([base_command + index])
		payload.append_array(wire.slice(4 * index, 4 * (index + 1)))
		_pending.append(payload)

func _send(target: int, id: int, command: int, content: PackedByteArray = PackedByteArray()) -> void:
	var payload: PackedByteArray = PackedByteArray([command])
	payload.append_array(content)
	PartyNetworkBridge.send_lobby_packet(target, id, payload)

func _enter_game() -> void:
	state = State.PLAYING
	starting = false
	game_requested.emit()
	_tick()

func _member_departed(message: String) -> void:
	if state == State.JOINING:
		message = "Bu lobiye bağlanılamadı. Yeniden ara veya başka bir lobi seç."
	if state == State.HOST:
		starting = false
		_clear_member()
		_tick()
		changed.emit()
	else:
		_reset()
	lobby_ended.emit(message)

func _peer_id() -> int:
	return GUEST_ID if _host else HOST_ID

func _new_token() -> int:
	return maxi(randi(), 1)
