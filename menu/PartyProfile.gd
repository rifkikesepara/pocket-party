class_name PartyProfile
extends RefCounted

const CONFIG_PATH: String = "user://party_profile.cfg"
const MAX_NAME_BYTES: int = 24
const COLOR_COUNT: int = 6
const FACE_COUNT: int = 4
const AVATAR_COUNT: int = COLOR_COUNT * FACE_COUNT
const CHUNK_COUNT: int = 7
const WIRE_SIZE: int = CHUNK_COUNT * 4

var nickname: String = ""
var avatar: int = 0

func load_saved() -> void:
	var config: ConfigFile = ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return
	var saved_name: String = str(config.get_value("profile", "nickname", ""))
	if is_valid_name(saved_name):
		nickname = saved_name
	avatar = clampi(int(config.get_value("profile", "avatar", 0)), 0, AVATAR_COUNT - 1)

func save() -> Error:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("profile", "nickname", nickname)
	config.set_value("profile", "avatar", avatar)
	return config.save(CONFIG_PATH)

static func is_valid_name(value: String) -> bool:
	return not value.is_empty() and value == value.strip_edges() and value == value.strip_escapes() and value.to_utf8_buffer().size() <= MAX_NAME_BYTES

func encode() -> PackedByteArray:
	var wire: PackedByteArray = PackedByteArray([avatar])
	wire.append_array(nickname.to_utf8_buffer())
	wire.resize(WIRE_SIZE)
	return wire

static func decode(wire: PackedByteArray) -> PartyProfile:
	if wire.size() != WIRE_SIZE or wire[0] >= AVATAR_COUNT:
		return null
	var nickname_end: int = 1
	while nickname_end < wire.size() and wire[nickname_end] != 0:
		nickname_end += 1
	if nickname_end > MAX_NAME_BYTES + 1:
		return null
	var value: String = wire.slice(1, nickname_end).get_string_from_utf8()
	if not is_valid_name(value):
		return null
	var profile: PartyProfile = PartyProfile.new()
	profile.nickname = value
	profile.avatar = wire[0]
	return profile
