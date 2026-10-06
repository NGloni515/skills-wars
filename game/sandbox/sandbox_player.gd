extends CharacterBody3D

enum HookState { READY, WINDUP, OUT, BACK }

const MOVE_SPEED := 5.5
const TURN_SPEED := 14.0
const HOOK_RELEASE_TIME := 0.3
const HOOK_SPEED := 24.0
const HOOK_RANGE := 13.0
const HOOK_HEIGHT := 0.9
const HOOK_HIT_RADIUS := 0.9
const HOOK_WALL_MASK := 4
const TARGET_RESPAWN_TIME := 2.5

@export var aim_button: AimButton
@export var target: HeroVisual

@onready var _visual: HeroVisual = $Gaff
@onready var _chain: HookChain = $HookChain
@onready var _aim_line: MeshInstance3D = $AimLine

var _hook := HookState.READY
var _hook_timer := 0.0
var _hook_origin := Vector3.ZERO
var _hook_direction := Vector3.BACK
var _hook_head := Vector3.ZERO
var _caught := false
var _target_down := false
var _target_home: Transform3D


func _ready() -> void:
	aim_button.fired.connect(_on_hook_fired)
	_aim_line.top_level = true
	_aim_line.visible = false
	_target_home = target.global_transform


func _physics_process(delta: float) -> void:
	_update_hook(delta)
	var input := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var move := Vector3(input.x, 0.0, input.y) if _hook == HookState.READY else Vector3.ZERO
	velocity = move * MOVE_SPEED
	move_and_slide()
	var aim := _aim_direction()
	if aim != Vector3.ZERO:
		_turn_towards(aim, delta)
	elif move.length() > 0.05:
		_turn_towards(move, delta)
	_update_aim_line(aim)
	_update_animation(move)


func _on_hook_fired(direction: Vector2) -> void:
	if _hook != HookState.READY:
		return
	var aim := Vector3(direction.x, 0.0, direction.y)
	_hook_direction = aim.normalized() if aim != Vector3.ZERO else global_basis.z.normalized()
	rotation.y = atan2(_hook_direction.x, _hook_direction.z)
	_hook = HookState.WINDUP
	_hook_timer = 0.0
	_visual.restart(&"hook_cast")


func _update_hook(delta: float) -> void:
	match _hook:
		HookState.WINDUP:
			_hook_timer += delta
			if _hook_timer >= HOOK_RELEASE_TIME:
				_hook = HookState.OUT
				_hook_origin = global_position + Vector3.UP * HOOK_HEIGHT + _hook_direction * 0.7
				_hook_head = _hook_origin
				_visual.set_hook_in_hand(false)
		HookState.OUT:
			var step_to := _hook_head + _hook_direction * HOOK_SPEED * delta
			if _hook_origin.distance_to(step_to) >= HOOK_RANGE:
				step_to = _hook_origin + _hook_direction * HOOK_RANGE
				_hook = HookState.BACK
			var query := PhysicsRayQueryParameters3D.create(_hook_head, step_to, HOOK_WALL_MASK)
			var hit := get_world_3d().direct_space_state.intersect_ray(query)
			if hit:
				step_to = hit.position
				_hook = HookState.BACK
			_hook_head = step_to
			if _touches_target():
				_caught = true
				_hook = HookState.BACK
				target.restart(&"dragged")
		HookState.BACK:
			_hook_head = _hook_head.move_toward(_hook_origin, HOOK_SPEED * delta)
			if _caught:
				target.global_position = Vector3(_hook_head.x, 0.0, _hook_head.z)
			if _hook_head.is_equal_approx(_hook_origin):
				_finish_hook()
	if _hook == HookState.OUT or _hook == HookState.BACK:
		_chain.show_chain(_visual.chain_origin(), _hook_head, _hook_direction)


func _touches_target() -> bool:
	if _caught or _target_down:
		return false
	var offset := target.global_position - _hook_head
	return Vector2(offset.x, offset.z).length() < HOOK_HIT_RADIUS


func _finish_hook() -> void:
	_hook = HookState.READY
	_chain.hide_chain()
	_visual.set_hook_in_hand(true)
	if _caught:
		_caught = false
		_target_down = true
		target.restart(&"death")
		get_tree().create_timer(TARGET_RESPAWN_TIME).timeout.connect(_respawn_target)


func _respawn_target() -> void:
	target.global_transform = _target_home
	target.restart(&"spawn")
	_target_down = false


func _aim_direction() -> Vector3:
	if _hook != HookState.READY or not aim_button.is_aiming():
		return Vector3.ZERO
	var direction := aim_button.aim_direction()
	return Vector3(direction.x, 0.0, direction.y)


func _turn_towards(direction: Vector3, delta: float) -> void:
	rotation.y = lerp_angle(rotation.y, atan2(direction.x, direction.z), minf(1.0, TURN_SPEED * delta))


func _update_aim_line(aim: Vector3) -> void:
	_aim_line.visible = aim != Vector3.ZERO
	if _aim_line.visible:
		var center := global_position + aim * (HOOK_RANGE * 0.5) + Vector3.UP * 0.05
		_aim_line.global_transform = Transform3D(Basis.looking_at(aim), center)


func _update_animation(move: Vector3) -> void:
	if _hook == HookState.READY:
		_visual.play(&"run" if move.length() > 0.05 else &"idle")
	elif _hook == HookState.BACK:
		_visual.play(&"reel")
