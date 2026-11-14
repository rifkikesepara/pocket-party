extends Control

const DINAMIT_SCENE: PackedScene = preload("res://minigames/dinamit/Dinamit.tscn")
const FACE_NAMES: Array[String] = ["Neşeli", "Gülen", "Şaşkın", "Meraklı"]
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

var _profile: PartyProfile = PartyProfile.new()
var _draft_color: int = 0
var _draft_face: int = 0
var _after_profile: Callable
var _game: DinamitMinigame

func _ready() -> void:
	_profile.load_saved()
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
	connection_test.visible = not OS.has_feature("mobile") and not PartyNetworkBridge.is_mock_mode
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
	if not page.visible:
		page_scroll.scroll_vertical = 0
	home.visible = page == home
	editor.visible = page == editor
	nearby.visible = page == nearby
	room.visible = page == room
	back.visible = page != home

func _show_home(message: String = "") -> void:
	_show_page(home)
	home_avatar.avatar = _profile.avatar
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
	editor_notice.hide()
	_update_avatar()

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
	_save_profile()

func _cycle_color() -> void:
	_draft_color = (_draft_color + 1) % PartyProfile.COLOR_COUNT
	_update_avatar()

func _cycle_face() -> void:
	_draft_face = (_draft_face + 1) % PartyProfile.FACE_COUNT
	_update_avatar()

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
	local_name.text = _profile.nickname
	local_role.text = "Sen · Ev sahibi" if host else "Sen"
	local_avatar.avatar = _profile.avatar
	peer_avatar.visible = peer != null
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
	_game.leave_lobby_requested.connect(_leave_to_home)
	menu.hide()
	add_child(_game)

func _open_connection_test() -> void:
	_game = DINAMIT_SCENE.instantiate() as DinamitMinigame
	_game.leave_lobby_requested.connect(_leave_to_home)
	_game.show_menu_button = true
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
