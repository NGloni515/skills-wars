extends Node3D

const CAMERA_OFFSET := Vector3(0.0, 11.0, 7.7)
const CAMERA_LEAD := Vector3(3.5, 0.0, 0.0)
const CAMERA_FOLLOW_SPEED := 6.0

@onready var _player: Node3D = $Player
@onready var _camera: Camera3D = $Camera3D
@onready var _hook_button: AimButton = $HUD/HookButton


func _ready() -> void:
	_camera.global_position = _camera_target()
	_camera.look_at(_player.global_position + CAMERA_LEAD)
	if "--autofire" in OS.get_cmdline_user_args():
		get_tree().create_timer(1.0).timeout.connect(_hook_button.fired.emit.bind(Vector2.RIGHT))


func _process(delta: float) -> void:
	_camera.global_position = _camera.global_position.lerp(_camera_target(), minf(1.0, CAMERA_FOLLOW_SPEED * delta))


func _camera_target() -> Vector3:
	return _player.global_position + CAMERA_LEAD + CAMERA_OFFSET
