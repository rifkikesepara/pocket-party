class_name PartyProfile
extends RefCounted

const CONFIG_PATH: String = "user://party_profile.cfg"
const MAX_NAME_BYTES: int = 24
const COLOR_COUNT: int = 6
const FACE_COUNT: int = 8
const PHOTO_SIZE: int = 256
const AVATAR_COUNT: int = COLOR_COUNT * FACE_COUNT
const CHUNK_COUNT: int = 7
const WIRE_SIZE: int = CHUNK_COUNT * 4

var nickname: String = ""
var avatar: int = 0
var photo: Image
var reduced_motion: bool = false

func load_saved() -> void:
	var config: ConfigFile = ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return
	var saved_name: String = str(config.get_value("profile", "nickname", ""))
	if is_valid_name(saved_name):
		nickname = saved_name
	avatar = clampi(int(config.get_value("profile", "avatar", 0)), 0, AVATAR_COUNT - 1)
	reduced_motion = bool(config.get_value("profile", "reduced_motion", false))
	var encoded_photo: String = str(config.get_value("profile", "photo", ""))
	if not encoded_photo.is_empty():
		var image: Image = Image.new()
		if image.load_png_from_buffer(Marshalls.base64_to_raw(encoded_photo)) == OK:
			photo = image

func save() -> Error:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("profile", "nickname", nickname)
	config.set_value("profile", "avatar", avatar)
	config.set_value("profile", "reduced_motion", reduced_motion)
	if photo != null:
		config.set_value("profile", "photo", Marshalls.raw_to_base64(photo.save_png_to_buffer()))
	return config.save(CONFIG_PATH)

static func prepare_photo(image: Image) -> Image:
	if image == null or image.is_empty():
		return null
	var edge: int = mini(image.get_width(), image.get_height())
	var origin: Vector2i = (image.get_size() - Vector2i(edge, edge)) / 2
	var square: Image = image.get_region(Rect2i(origin, Vector2i(edge, edge)))
	square.resize(PHOTO_SIZE, PHOTO_SIZE, Image.INTERPOLATE_LANCZOS)
	return square

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
