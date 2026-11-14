class_name AvatarPhotoPicker
extends Node

signal finished(photo: Image, failed: bool)

const MAX_FILE_BYTES: int = 24 * 1024 * 1024
const FILTERS: PackedStringArray = ["*.png,*.jpg,*.jpeg,*.webp;Fotoğraflar;image/png,image/jpeg,image/webp"]

var _busy: bool = false

func open() -> bool:
	if _busy:
		return false
	_busy = true
	if OS.get_name() == "iOS":
		if Engine.has_singleton("PocketPartyBLE"):
			var ios: Object = Engine.get_singleton("PocketPartyBLE")
			if ios.has_method("pick_avatar_photo") and ios.has_signal("avatar_photo_picked"):
				ios.connect("avatar_photo_picked", _on_ios_photo, CONNECT_ONE_SHOT)
				ios.call("pick_avatar_photo")
				return true
	elif DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		var error: Error = DisplayServer.file_dialog_show("Avatar fotoğrafı seç", OS.get_system_dir(OS.SYSTEM_DIR_PICTURES), "", false, DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, FILTERS, _on_file_selected, get_window().get_window_id())
		if error == OK:
			return true
	_busy = false
	return false

func _on_ios_photo(bytes: PackedByteArray, failed: bool) -> void:
	_busy = false
	if bytes.is_empty():
		finished.emit(null, failed)
	else:
		_decode(bytes)

func _on_file_selected(selected: bool, paths: PackedStringArray, _filter: int) -> void:
	_busy = false
	if not selected or paths.is_empty():
		finished.emit(null, false)
		return
	var file: FileAccess = FileAccess.open(paths[0], FileAccess.READ)
	if file == null or file.get_length() > MAX_FILE_BYTES:
		finished.emit(null, true)
		return
	_decode(file.get_buffer(file.get_length()))

func _decode(bytes: PackedByteArray) -> void:
	var image: Image = Image.new()
	var status: Error = ERR_FILE_UNRECOGNIZED
	if bytes.size() >= 8 and bytes[0] == 137 and bytes[1] == 80:
		status = image.load_png_from_buffer(bytes)
	elif bytes.size() >= 3 and bytes[0] == 255 and bytes[1] == 216:
		status = image.load_jpg_from_buffer(bytes)
	elif bytes.size() >= 12 and bytes.slice(8, 12).get_string_from_ascii() == "WEBP":
		status = image.load_webp_from_buffer(bytes)
	var photo: Image = PartyProfile.prepare_photo(image) if status == OK else null
	finished.emit(photo, photo == null)
