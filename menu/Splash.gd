extends Control
## Shown once at app launch. Load the menu while its poster is on screen.
const MENU_PATH: String = "res://menu/PartyMenu.tscn"
const MIN_DISPLAY_SECONDS: float = 0.65

@onready var error_message: Label = %ErrorMessage
@onready var retry_button: Button = %Retry

var _elapsed: float = 0.0
var _loading: bool = false
var _menu_scene: PackedScene
var _transitioning: bool = false
var _reduced_motion: bool = false

func _ready() -> void:
	var preferences: ConfigFile = ConfigFile.new()
	if preferences.load(PartyProfile.CONFIG_PATH) == OK:
		_reduced_motion = bool(preferences.get_value("profile", "reduced_motion", false))
	retry_button.pressed.connect(_request_menu)
	_request_menu()

func _request_menu() -> void:
	if _loading:
		return
	error_message.hide()
	retry_button.hide()
	_loading = true
	# Present the lightweight poster before loading the menu and game resources.
	await get_tree().process_frame
	await get_tree().process_frame
	_menu_scene = load(MENU_PATH) as PackedScene
	_loading = false
	if _menu_scene == null:
		_show_error()

func _process(delta: float) -> void:
	_elapsed += delta
	if _loading or _transitioning or _menu_scene == null:
		return
	if _elapsed >= MIN_DISPLAY_SECONDS:
		_open_menu()

func _input(event: InputEvent) -> void:
	if retry_button.visible:
		return
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	var click: InputEventMouseButton = event as InputEventMouseButton
	if (touch != null and touch.pressed) or (click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT) or event.is_action_pressed("ui_accept"):
		_elapsed = MIN_DISPLAY_SECONDS
		get_viewport().set_input_as_handled()

func _open_menu() -> void:
	_loading = false
	if _menu_scene == null:
		_show_error()
		return
	_transitioning = true
	var next_scene: Control = _menu_scene.instantiate() as Control
	get_tree().root.add_child(next_scene)
	get_tree().current_scene = next_scene
	# The menu is already rendered beneath the splash, so no blank frame occurs.
	var transition: Tween = create_tween()
	transition.tween_property(self, "modulate:a", 0.0, 0.12 if _reduced_motion else 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	transition.tween_callback(queue_free)

func _show_error() -> void:
	_loading = false
	error_message.show()
	retry_button.show()
	retry_button.grab_focus()
