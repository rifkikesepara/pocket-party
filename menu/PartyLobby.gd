class_name PartyLobby
extends Node

signal changed
signal game_requested
signal lobby_ended(message: String)

enum State { IDLE, SEARCHING, JOINING, HOST, GUEST, PLAYING }
enum Message { BEACON = 128, JOIN, ACCEPT, PRESENT, LEAVE, START, READY, PHOTO_CHUNK, PHOTO_RECEIVED, OPEN_PROFILE = 144, MEMBER_PROFILE = 160 }

const BROADCAST: int = 255
const HOST_ID: int = 0
const GUEST_ID: int = 1
const TIMEOUT_MS: int = 6500
const TICK_SEC: float = 0.85
const FRAGMENT_INTERVAL: float = 0.045
const PHOTO_CHUNK_COUNT: int = PartyProfile.LOBBY_PHOTO_BYTES / 3
const PHOTO_INTERVAL: float = 0.03
const PHOTO_WAIT_MS: int = 22000
const WEB_PHOTO: int = 137
const OPEN_WEB_PHOTO: int = 138
const WEB_PHOTO_ACK: int = 139
const WEB_PHOTO_CHUNKS: int = PartyProfile.WEB_PHOTO_BYTES / 3
const FULL_PHOTO: int = 140
const OPEN_FULL_PHOTO: int = 141

class FullPhoto:
	var data: PackedByteArray
	var seen: PackedByteArray
	var contiguous: int = 0

	func receive(packet: PackedByteArray) -> Image:
		var index: int = packet.decode_u16(1)
		if index >= 32767:
			return null
		if seen.is_empty():
			seen.resize(32767)
			data.resize(65534)
		seen[index] = 1
		data[index * 2] = packet[3]
		data[index * 2 + 1] = packet[4]
		while contiguous < seen.size() and seen[contiguous] != 0:
			contiguous += 1
		var length: int = data.decode_u16(0)
		if length == 0 or contiguous * 2 < length + 2:
			return null
		return PartyProfile.decode_web_photo(data)

class WebPhoto:
	var data: PackedByteArray
	var seen: PackedByteArray

	func receive(packet: PackedByteArray) -> Image:
		if seen.is_empty():
			seen.resize(WEB_PHOTO_CHUNKS)
			data.resize(PartyProfile.WEB_PHOTO_BYTES)
		var index: int = packet[1]
		seen[index] = 1
		for byte: int in range(3):
			data[index * 3 + byte] = packet[2 + byte]
		var length: int = data.decode_u16(0)
		if length <= 0 or length > data.size() - 2:
			return null
		for chunk: int in range(ceili((length + 2) / 3.0)):
			if seen[chunk] == 0:
				return null
		return PartyProfile.decode_web_photo(data)

class NearbyRoom:
	var last_seen: int
	var profile: PartyProfile
	var chunks: PackedByteArray
	var received: int = 0
	var web_photo: WebPhoto = WebPhoto.new()
	var full_photo: FullPhoto = FullPhoto.new()

var state: State = State.IDLE
var local_profile: PartyProfile
var peer_profile: PartyProfile
var rooms: Dictionary[int, NearbyRoom] = {}
var room_id: int = 0
var starting: bool = false
var selected_game_id: int = 1

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
var _photo_out: PackedByteArray
var _photo_in: PackedByteArray
var _photo_chunks: PackedByteArray
var _photo_chunks_received: int = 0
var _photo_cursor: int = 0
var _photo_confirmed: bool = false
var _photo_wait_until: int = 0
var _web_out: PackedByteArray
var _web_in: WebPhoto = WebPhoto.new()
var _web_cursor: int = 0
var _full_out: PackedByteArray
var _full_in: FullPhoto = FullPhoto.new()
var _full_cursor: int = 0
var _open_preview_next: bool = true

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
	if state != State.HOST or peer_profile == null or starting or photos_syncing():
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

func photos_syncing() -> bool:
	return _photo_wait_until != 0 and _photo_exchange_active() and (
		(peer_profile.shares_lobby_photo and peer_profile.photo == null)
		or (not _photo_out.is_empty() and not _photo_confirmed)
	)

func _prepare(profile: PartyProfile, role: int) -> bool:
	if state != State.IDLE:
		return false
	if not PartyNetworkBridge.is_mock_mode and not PartyNetworkBridge.is_pc_ble_bridge_mode and not PartyNetworkBridge.switch_to_ble():
		return false
	_previous_player_id = PartyNetworkBridge.local_player_id
	PartyNetworkBridge.set_local_player_id(role)
	local_profile = profile
	_photo_out = profile.encode_lobby_photo()
	_web_out = profile.encode_web_photo()
	_full_out = profile.encode_full_photo()
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
	_photo_in.clear()
	_photo_chunks.clear()
	_photo_chunks_received = 0
	_photo_cursor = 0
	_photo_confirmed = false
	_photo_wait_until = 0
	_web_in = WebPhoto.new()
	_web_cursor = 0
	_full_cursor = 0
	_full_in = FullPhoto.new()
	_open_preview_next = true

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
	if _photo_wait_until != 0 and now >= _photo_wait_until:
		var was_syncing: bool = photos_syncing()
		_photo_wait_until = 0
		if was_syncing:
			changed.emit()
	_until_tick -= delta
	_until_fragment -= delta
	if _until_tick <= 0.0:
		_tick()
	elif _until_fragment <= 0.0 and not _pending.is_empty():
		# Space profile fragments across frames for BLE write capacity.
		_until_fragment = FRAGMENT_INTERVAL
		PartyNetworkBridge.send_lobby_packet(BROADCAST if _host and _member_token == 0 else _peer_id(), room_id if _host and _member_token == 0 else _member_token, _pending.pop_front())
	elif _until_fragment <= 0.0 and not _web_out.is_empty() and state == State.HOST and _member_token == 0:
		if _open_preview_next or _full_out.is_empty():
			_send_web_photo(BROADCAST, room_id, OPEN_WEB_PHOTO)
			_open_preview_next = _web_cursor != 0
		else:
			_send_full_photo(BROADCAST, room_id, OPEN_FULL_PHOTO)
			_open_preview_next = _full_cursor == 0
	elif _until_fragment <= 0.0 and _photo_exchange_active() and _photo_confirmed and peer_profile.supports_web_photo and not _full_out.is_empty():
		_send_full_photo(_peer_id(), _member_token, FULL_PHOTO)
	elif _until_fragment <= 0.0 and _photo_exchange_active() and not _photo_confirmed and not _photo_out.is_empty():
		if peer_profile.supports_web_photo and not _web_out.is_empty():
			_send_web_photo(_peer_id(), _member_token, WEB_PHOTO)
			return
		_until_fragment = PHOTO_INTERVAL
		var offset: int = _photo_cursor * 3
		_send(_peer_id(), _member_token, Message.PHOTO_CHUNK, PackedByteArray([
			_photo_cursor, _photo_out[offset], _photo_out[offset + 1], _photo_out[offset + 2],
		]))
		_photo_cursor = (_photo_cursor + 1) % PHOTO_CHUNK_COUNT

func _send_web_photo(target: int, token: int, command: int) -> void:
	_until_fragment = 0.012
	var offset: int = _web_cursor * 3
	_send(target, token, command, PackedByteArray([_web_cursor, _web_out[offset], _web_out[offset + 1], _web_out[offset + 2]]))
	_web_cursor = (_web_cursor + 1) % (_web_out.size() / 3)

func _send_full_photo(target: int, token: int, command: int) -> void:
	_until_fragment = 0.012
	var offset: int = _full_cursor * 2
	var payload: PackedByteArray = PackedByteArray([0, 0, _full_out[offset], _full_out[offset + 1]])
	payload.encode_u16(0, _full_cursor)
	_send(target, token, command, payload)
	_full_cursor = (_full_cursor + 1) % (_full_out.size() / 2)

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
				_send(GUEST_ID, _member_token, Message.START, PackedByteArray([selected_game_id]))
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
		_photo_wait_until = now + PHOTO_WAIT_MS
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
		FULL_PHOTO:
			if target == PartyNetworkBridge.local_player_id and _photo_exchange_active():
				_read_full_photo(peer_profile, _full_in, data)
		WEB_PHOTO:
			if target == PartyNetworkBridge.local_player_id and _photo_exchange_active():
				if peer_profile.photo == null:
					peer_profile.photo = _web_in.receive(data)
					if peer_profile.photo != null:
						changed.emit()
				if peer_profile.photo != null:
					_send(_peer_id(), _member_token, WEB_PHOTO_ACK)
		WEB_PHOTO_ACK:
			if target == PartyNetworkBridge.local_player_id and _photo_exchange_active() and not _photo_confirmed:
				_photo_confirmed = true
				changed.emit()
		Message.LEAVE:
			_member_departed("Rakibin lobiden ayrıldı.")
		Message.PRESENT:
			_last_seen = now
			if state == State.GUEST:
				_profile_confirmed = true
		Message.START:
			if state == State.GUEST:
				_last_seen = now
				if data.size() >= 2 and data[1] in [1, 2]:
					selected_game_id = data[1]
				_enter_game()
		Message.READY:
			if state == State.HOST and starting:
				_last_seen = now
				_enter_game()
			elif state == State.PLAYING:
				_last_seen = now
		Message.PHOTO_CHUNK:
			if target == PartyNetworkBridge.local_player_id and _photo_exchange_active():
				_read_photo_chunk(data)
		Message.PHOTO_RECEIVED:
			if target == PartyNetworkBridge.local_player_id and _photo_exchange_active() and not _photo_confirmed:
				_photo_confirmed = true
				changed.emit()
		_:
			if state == State.HOST and peer_profile == null:
				_read_member_profile(command, data)

func _photo_exchange_active() -> bool:
	return (state == State.HOST or state == State.GUEST) and not starting and peer_profile != null and peer_profile.supports_lobby_photo

func _read_photo_chunk(data: PackedByteArray) -> void:
	var chunk: int = data[1]
	if chunk >= PHOTO_CHUNK_COUNT:
		return
	if peer_profile.photo != null:
		# A repeated transfer means the acknowledgement may have been lost.
		if chunk == 0 or chunk == PHOTO_CHUNK_COUNT - 1:
			_send(_peer_id(), _member_token, Message.PHOTO_RECEIVED)
		return
	if _photo_chunks.is_empty():
		_photo_chunks.resize(PHOTO_CHUNK_COUNT)
		_photo_in.resize(PartyProfile.LOBBY_PHOTO_BYTES)
	if _photo_chunks[chunk] != 0:
		return
	_photo_chunks[chunk] = 1
	_photo_chunks_received += 1
	for byte: int in range(3):
		_photo_in[chunk * 3 + byte] = data[2 + byte]
	if _photo_chunks_received == PHOTO_CHUNK_COUNT:
		peer_profile.photo = PartyProfile.decode_lobby_photo(_photo_in)
		_send(_peer_id(), _member_token, Message.PHOTO_RECEIVED)
		changed.emit()

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
	if command == OPEN_FULL_PHOTO and rooms.has(id):
		var room: NearbyRoom = rooms[id]
		if room.profile != null:
			_read_full_photo(room.profile, room.full_photo, data)
		return
	if command == OPEN_WEB_PHOTO and rooms.has(id):
		var room: NearbyRoom = rooms[id]
		if room.profile != null and room.profile.photo == null:
			room.profile.photo = room.web_photo.receive(data)
			if room.profile.photo != null:
				changed.emit()
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

func _read_full_photo(profile: PartyProfile, transfer: FullPhoto, data: PackedByteArray) -> void:
	if profile.photo != null and profile.photo.get_width() >= PartyProfile.PHOTO_SIZE:
		return
	var photo: Image = transfer.receive(data)
	if photo != null and photo.get_size() == Vector2i(PartyProfile.PHOTO_SIZE, PartyProfile.PHOTO_SIZE):
		profile.photo = photo
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
			_photo_wait_until = Time.get_ticks_msec() + PHOTO_WAIT_MS
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
