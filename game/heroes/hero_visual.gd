class_name HeroVisual
extends Node3D

const HERO_SHADER := preload("res://shared/shaders/hero.gdshader")
const OUTLINE_SHADER := preload("res://shared/shaders/outline.gdshader")
const RETURNS_TO_IDLE: Array[StringName] = [&"spawn", &"taunt"]

@export var team_color := Color(0.86, 0.24, 0.2):
	set(value):
		team_color = value
		if _material:
			_material.set_shader_parameter("team_color", value)

var _material: ShaderMaterial
var _player: AnimationPlayer
var _skeleton: Skeleton3D
var _chain_bone := -1
var _hook_in_hand: Node3D


func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = HERO_SHADER
	_material.set_shader_parameter("team_color", team_color)
	var outline := ShaderMaterial.new()
	outline.shader = OUTLINE_SHADER
	_material.next_pass = outline
	for mesh: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = _material
	_player = find_children("*", "AnimationPlayer", true, false)[0]
	_skeleton = find_children("*", "Skeleton3D", true, false)[0]
	_chain_bone = _skeleton.find_bone("chain_socket")
	_hook_in_hand = find_child("HookHead", true, false)
	_player.animation_finished.connect(_on_animation_finished)
	play(&"idle")


func play(anim: StringName, blend := 0.12) -> void:
	if _player.current_animation != anim:
		_player.play(anim, blend)


func restart(anim: StringName, blend := 0.08) -> void:
	_player.play(anim, blend)
	_player.seek(0.0, true)


func set_hook_in_hand(held: bool) -> void:
	_hook_in_hand.visible = held


func chain_origin() -> Vector3:
	return _skeleton.global_transform * _skeleton.get_bone_global_pose(_chain_bone).origin


func _on_animation_finished(anim: StringName) -> void:
	if anim in RETURNS_TO_IDLE:
		play(&"idle")
