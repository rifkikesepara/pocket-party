extends Button
## A slight printed-poster tilt; the hit area follows the visual transform.
@export var angle_degrees: float = -3.0

func _ready() -> void:
	resized.connect(_place_pivot)
	_place_pivot()

func _place_pivot() -> void:
	pivot_offset = size * 0.5
	rotation_degrees = angle_degrees
