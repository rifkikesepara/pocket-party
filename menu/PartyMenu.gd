extends Control

const DINAMIT_SCENE: PackedScene = preload("res://minigames/dinamit/Dinamit.tscn")
const FACE_NAMES: Array[String] = ["Neşeli", "Gülen", "Şaşkın", "Meraklı", "Kedi", "Bıyıklı", "Şapşal", "Uzaylı"]
const COLOR_NAMES: Array[String] = ["Bal", "Nane", "Leylak", "Çilek", "Gök", "Şeftali"]

@onready var lobby: PartyLobby = %Lobby
@onready var safe_margin: MarginContainer = %SafeMargin
@onready var menu: Control = %Menu
@onready var home: VBoxContainer = %Home
@onready var editor: VBoxContainer = %Profile
@onready var nearby: VBoxContainer = %Nearby
@onready var room: VBoxContainer = %Room
@onready var back: Button = %Back
@onready var edit_profile: Button = %EditProfile
@onready var host_button: Button = %Host
@onready var search_button: Button = %Search
@onready var save_profile: Button = %SaveProfile
@onready var nickname: LineEdit = %Nickname
@onready var editor_avatar: PartyAvatar = %EditorAvatar
@onready var home_avatar: PartyAvatar = %HomeAvatar
@onready var home_name: Label = %HomeName
@onready var home_notice: Label = %HomeNotice
@onready var editor_notice: Label = %EditorNotice
@onready var color_button: Button = %Color
@onready var face_button: Button = %Face
@onready var room_list: VBoxContainer = %RoomList
@onready var nearby_status: Label = %NearbyStatus
@onready var room_status: Label = %RoomStatus
@onready var room_meter: ProgressBar = %RoomMeter
@onready var local_avatar: PartyAvatar = %LocalAvatar
@onready var peer_avatar: PartyAvatar = %PeerAvatar
@onready var local_name: Label = %LocalName
@onready var peer_name: Label = %PeerName
@onready var local_role: Label = %LocalRole
@onready var peer_role: Label = %PeerRole
@onready var start_game: Button = %StartGame
@onready var leave_room: Button = %LeaveRoom
@onready var page_scroll: ScrollContainer = %Scroll
@onready var connection_test: Button = %ConnectionTest
@onready var transport_hint: Label = %Transport
@onready var photo_button: Button = %Photo
@onready var photo_hint: Label = %PhotoHint
@onready var remove_photo: Button = %RemovePhoto
@onready var party_art: Control = %PartyArt
@onready var reduce_motion: CheckButton = %ReduceMotion

var _profile: PartyProfile = PartyProfile.new()
var _draft_color: int = 0
var _draft_face: int = 0
var _after_profile: Callable
var _game: DinamitMinigame
var _draft_photo: Image
var _photo_picker: AvatarPhotoPicker
var _page_tween: Tween
var _avatar_tween: Tween
var _peer_tween: Tween
var _room_meter_tween: Tween

func _ready() -> void:
	_profile.load_saved()
	_photo_picker = AvatarPhotoPicker.new()
	add_child(_photo_picker)
	_photo_picker.finished.connect(_on_photo_picked)
	photo_button.pressed.connect(_pick_photo)
	remove_photo.pressed.connect(_clear_photo)
	(%Shuffle as Button).pressed.connect(_randomize_avatar)
	reduce_motion.set_pressed_no_signal(_profile.reduced_motion)
	reduce_motion.toggled.connect(_change_motion_preference)
	party_art.set("reduced_motion", _profile.reduced_motion)
	edit_profile.pressed.connect(_show_profile)
	host_button.pressed.connect(_require_profile.bind(_host_room))
	search_button.pressed.connect(_require_profile.bind(_search_rooms))
	back.pressed.connect(_navigate_back)
	save_profile.pressed.connect(_save_profile)
	nickname.text_submitted.connect(_submit_profile)
	color_button.pressed.connect(_cycle_color)
	face_button.pressed.connect(_cycle_face)
	start_game.pressed.connect(lobby.start_game)
	leave_room.pressed.connect(_leave_to_home)
	connection_test.pressed.connect(_open_connection_test)
	connection_test.visible = not OS.has_feature("mobile") and not PartyNetworkBridge.is_mock_mode and not PartyNetworkBridge.is_pc_ble_bridge_mode
	if PartyNetworkBridge.is_pc_ble_bridge_mode:
		transport_hint.text = "PC Bluetooth köprüsü · pc_ble_bridge.py çalışır durumda olmalı."
	lobby.changed.connect(_update_lobby)
	lobby.game_requested.connect(_open_game)
	lobby.lobby_ended.connect(_on_lobby_ended)
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()
	_show_home()

func _unhandled_input(event: InputEvent) -> void:
	if menu.visible and back.visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_navigate_back()

func _show_page(page: Control) -> void:
	var changing: bool = not page.visible
	if changing:
		if _page_tween != null:
			_page_tween.kill()
		page_scroll.scroll_vertical = 0
	home.visible = page == home
	editor.visible = page == editor
	nearby.visible = page == nearby
	room.visible = page == room
	back.visible = page != home
	if changing:
		page.modulate.a = 0.0 if not _profile.reduced_motion else 1.0
		if not _profile.reduced_motion:
			_page_tween = create_tween()
			_page_tween.tween_property(page, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _show_home(message: String = "") -> void:
	_show_page(home)
	home_avatar.avatar = _profile.avatar
	home_avatar.photo_texture = ImageTexture.create_from_image(_profile.photo) if _profile.photo != null else null
	home_name.text = _profile.nickname if not _profile.nickname.is_empty() else "Profil oluştur"
	home_notice.text = message
	home_notice.visible = not message.is_empty()

func _require_profile(next: Callable) -> void:
	if _profile.nickname.is_empty():
		_after_profile = next
		_show_profile()
	else:
		next.call()

func _show_profile() -> void:
	_show_page(editor)
	nickname.text = _profile.nickname
	_draft_color = _profile.avatar % PartyProfile.COLOR_COUNT
	_draft_face = _profile.avatar / PartyProfile.COLOR_COUNT
	_draft_photo = _profile.photo
	editor_notice.hide()
	_update_avatar()
	_update_photo_preview()

func _save_profile() -> void:
	var value: String = nickname.text.strip_edges()
	if not PartyProfile.is_valid_name(value):
		editor_notice.text = "Bir takma ad gir. Adın uzunsa kısaltmayı dene."
		editor_notice.show()
		nickname.grab_focus()
		return
	var updated: PartyProfile = PartyProfile.new()
	updated.nickname = value
	updated.avatar = editor_avatar.avatar
	updated.photo = _draft_photo
	updated.reduced_motion = _profile.reduced_motion
	if updated.save() != OK:
		editor_notice.text = "Profil kaydedilemedi. Tekrar dene."
		editor_notice.show()
		return
	_profile = updated
	var next: Callable = _after_profile
	_after_profile = Callable()
	_show_home()
	if next.is_valid():
		next.call()

func _submit_profile(_value: String) -> void:
	if not save_profile.disabled:
		_save_profile()

func _cycle_color() -> void:
	_draft_color = (_draft_color + 1) % PartyProfile.COLOR_COUNT
	_update_avatar()
	_animate_avatar()

func _cycle_face() -> void:
	_draft_face = (_draft_face + 1) % PartyProfile.FACE_COUNT
	_update_avatar()
	_animate_avatar()

func _randomize_avatar() -> void:
	_draft_face = (_draft_face + randi_range(1, PartyProfile.FACE_COUNT - 1)) % PartyProfile.FACE_COUNT
	_draft_color = randi_range(0, PartyProfile.COLOR_COUNT - 1)
	_update_avatar()
	_animate_avatar()

func _animate_avatar() -> void:
	if _avatar_tween != null:
		_avatar_tween.kill()
	editor_avatar.pivot_offset = editor_avatar.size * 0.5
	editor_avatar.scale = Vector2.ONE
	if not _profile.reduced_motion:
		editor_avatar.scale = Vector2.ONE * 0.92
		_avatar_tween = create_tween()
		_avatar_tween.tween_property(editor_avatar, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _pick_photo() -> void:
	editor_notice.hide()
	photo_button.disabled = _photo_picker.open()
	save_profile.disabled = photo_button.disabled
	if not photo_button.disabled:
		editor_notice.text = "Fotoğraf seçici açılamadı."
		editor_notice.show()

func _on_photo_picked(photo: Image, failed: bool) -> void:
	photo_button.disabled = false
	save_profile.disabled = false
	if not editor.visible:
		return
	if failed:
		editor_notice.text = "Fotoğraf okunamadı. Başka bir görsel seç."
		editor_notice.show()
	elif photo != null:
		_draft_photo = photo
		_update_photo_preview()
		_animate_avatar()

func _clear_photo() -> void:
	_draft_photo = null
	_update_photo_preview()
	_animate_avatar()

func _update_photo_preview() -> void:
	var has_photo: bool = _draft_photo != null
	editor_avatar.photo_texture = ImageTexture.create_from_image(_draft_photo) if has_photo else null
	photo_button.text = "Fotoğrafı değiştir" if has_photo else "Galeriden fotoğraf seç"
	remove_photo.visible = has_photo
	photo_hint.visible = has_photo
	(%Options as HBoxContainer).visible = not has_photo

func _change_motion_preference(enabled: bool) -> void:
	_profile.reduced_motion = enabled
	party_art.set("reduced_motion", enabled)
	if _profile.save() != OK:
		_show_home("Hareket tercihi kaydedilemedi.")

func _update_avatar() -> void:
	editor_avatar.avatar = _draft_face * PartyProfile.COLOR_COUNT + _draft_color
	color_button.text = "Renk · %s  ›" % COLOR_NAMES[_draft_color]
	face_button.text = "Yüz · %s  ›" % FACE_NAMES[_draft_face]

func _host_room() -> void:
	if not lobby.open(_profile):
		_show_bluetooth_error()

func _search_rooms() -> void:
	if not lobby.scan(_profile):
		_show_bluetooth_error()

func _show_bluetooth_error() -> void:
	if OS.get_name() == "Windows":
		_show_home("PC’de lobi için pc_ble_bridge.py betiğini çalıştır ve oyunu --pc-ble-bridge seçeneğiyle başlat. UDP 42425 boş olmalı.")
	else:
		_show_home("Bluetooth bağlantısı kullanılamıyor. BLE destekli mobil sürümü kullan.")

func _update_lobby() -> void:
	match lobby.state:
		PartyLobby.State.SEARCHING:
			_show_page(nearby)
			_update_room_list()
		PartyLobby.State.JOINING:
			_show_page(nearby)
			_update_room_list()
			nearby_status.text = "%s lobisine bağlanılıyor…" % lobby.peer_profile.nickname
		PartyLobby.State.HOST, PartyLobby.State.GUEST:
			_show_page(room)
			_update_room()

func _update_room_list() -> void:
	var count: int = 0
	for child: Node in room_list.get_children():
		room_list.remove_child(child)
		child.queue_free()
	for id: int in lobby.rooms:
		var candidate: PartyLobby.NearbyRoom = lobby.rooms[id]
		if candidate.profile == null:
			continue
		count += 1
		var item: HBoxContainer = HBoxContainer.new()
		item.add_theme_constant_override("separation", 10)
		var avatar: PartyAvatar = PartyAvatar.new()
		avatar.avatar = candidate.profile.avatar
		avatar.custom_minimum_size = Vector2(48, 48)
		avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		item.add_child(avatar)
		var join_button: Button = Button.new()
		join_button.text = "%s  ·  Katıl  ›" % candidate.profile.nickname
		join_button.custom_minimum_size.y = 48.0
		join_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		join_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		join_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		join_button.disabled = lobby.state != PartyLobby.State.SEARCHING
		join_button.pressed.connect(lobby.join.bind(id))
		item.add_child(join_button)
		room_list.add_child(item)
	nearby_status.text = "Yakındaki lobiler aranıyor. Bluetooth’u açık tut." if count == 0 else "Katılmak istediğin lobiyi seç."

func _update_room() -> void:
	var host: bool = lobby.state == PartyLobby.State.HOST
	var peer: PartyProfile = lobby.peer_profile
	var occupancy: float = 1.0 if peer == null else 2.0
	if _room_meter_tween != null:
		_room_meter_tween.kill()
	if _profile.reduced_motion:
		room_meter.value = occupancy
	else:
		_room_meter_tween = create_tween()
		_room_meter_tween.tween_property(room_meter, "value", occupancy, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	local_name.text = _profile.nickname
	local_role.text = "Sen · Ev sahibi" if host else "Sen"
	local_avatar.avatar = _profile.avatar
	local_avatar.photo_texture = home_avatar.photo_texture
	var joining: bool = peer != null and not peer_avatar.visible
	peer_avatar.visible = peer != null
	if joining and not _profile.reduced_motion:
		if _peer_tween != null:
			_peer_tween.kill()
		peer_avatar.modulate.a = 0.0
		_peer_tween = create_tween()
		_peer_tween.tween_property(peer_avatar, "modulate:a", 1.0, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	elif peer == null or _profile.reduced_motion:
		peer_avatar.modulate.a = 1.0
	peer_name.text = peer.nickname if peer != null else "Boş koltuk"
	peer_role.text = ("Misafir" if host else "Ev sahibi") if peer != null else "Oyuncu bekleniyor"
	start_game.visible = host
	start_game.disabled = peer == null or lobby.starting
	if lobby.starting:
		room_status.text = "Dinamit açılıyor…"
	elif not host:
		room_status.text = "Ev sahibinin oyunu açması bekleniyor."
	elif peer != null:
		room_status.text = "2 / 2 oyuncu · Masa hazır"
	else:
		room_status.text = "1 / 2 oyuncu · Arkadaşın Yakındaki lobiler’den sana katılabilir."

func _open_game() -> void:
	_game = DINAMIT_SCENE.instantiate() as DinamitMinigame
	_game.lobby_tag = lobby.game_tag()
	_game.lobby_local_name = _profile.nickname
	_game.lobby_peer_name = lobby.peer_profile.nickname
	_game.prefer_reduced_motion = _profile.reduced_motion
	_game.leave_lobby_requested.connect(_leave_to_home)
	menu.hide()
	add_child(_game)

func _open_connection_test() -> void:
	_game = DINAMIT_SCENE.instantiate() as DinamitMinigame
	_game.leave_lobby_requested.connect(_leave_to_home)
	_game.show_menu_button = true
	_game.prefer_reduced_motion = _profile.reduced_motion
	menu.hide()
	add_child(_game)

func _navigate_back() -> void:
	if editor.visible:
		_after_profile = Callable()
		_show_home()
	else:
		_leave_to_home()

func _leave_to_home() -> void:
	lobby.leave()
	_close_game()
	_show_home()

func _on_lobby_ended(message: String) -> void:
	if lobby.state == PartyLobby.State.HOST:
		room_status.text = "%s Yeni oyuncu katılabilir." % message
	else:
		_close_game()
		_show_home(message)

func _close_game() -> void:
	if is_instance_valid(_game):
		remove_child(_game)
		_game.queue_free()
		_game = null
	menu.show()

func _apply_safe_area() -> void:
	if not OS.has_feature("mobile"):
		return
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	var window_size: Vector2i = DisplayServer.window_get_size()
	if not safe.has_area() or window_size.x <= 0 or window_size.y <= 0:
		return
	var ratio: Vector2 = get_viewport_rect().size / Vector2(window_size)
	var trailing: Vector2i = window_size - safe.end
	safe_margin.add_theme_constant_override("margin_left", maxi(24, roundi(safe.position.x * ratio.x) + 16))
	safe_margin.add_theme_constant_override("margin_top", maxi(24, roundi(safe.position.y * ratio.y) + 16))
	safe_margin.add_theme_constant_override("margin_right", maxi(24, roundi(trailing.x * ratio.x) + 16))
	safe_margin.add_theme_constant_override("margin_bottom", maxi(24, roundi(trailing.y * ratio.y) + 16))
