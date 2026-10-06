class_name HookChain
extends Node3D

const HERO_SHADER := preload("res://shared/shaders/hero.gdshader")
const OUTLINE_SHADER := preload("res://shared/shaders/outline.gdshader")
const CHAIN_LINK := preload("res://heroes/gaff/chain_link.glb")
const LINK_SPACING := 0.14
const MAX_LINKS := 260
const BIG_HEAD_SCALE := 1.8

@onready var _head: Node3D = $Head
@onready var _links: MultiMeshInstance3D = $Links


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	var material := ShaderMaterial.new()
	material.shader = HERO_SHADER
	var head_material: ShaderMaterial = material.duplicate()
	head_material.next_pass = ShaderMaterial.new()
	head_material.next_pass.shader = OUTLINE_SHADER
	for mesh: MeshInstance3D in _head.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = head_material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = _link_mesh()
	multimesh.instance_count = MAX_LINKS
	multimesh.visible_instance_count = 0
	_links.multimesh = multimesh
	_links.material_override = material
	visible = false


func show_chain(origin: Vector3, head: Vector3, direction: Vector3) -> void:
	visible = true
	_head.global_transform = Transform3D(Basis.looking_at(direction, Vector3.UP, true), head)
	var span := head - origin
	var multimesh := _links.multimesh
	var count := mini(int(span.length() / LINK_SPACING), MAX_LINKS)
	if count == 0:
		multimesh.visible_instance_count = 0
		return
	var axis := span.normalized()
	var flat := Basis.looking_at(axis, Vector3.UP)
	var turned := flat.rotated(axis, PI / 2.0)
	for i in count:
		var link_position := origin + span * ((i + 0.5) / count)
		multimesh.set_instance_transform(i, Transform3D(flat if i % 2 == 0 else turned, link_position))
	multimesh.visible_instance_count = count


func set_big(big: bool) -> void:
	_head.scale = Vector3.ONE * (BIG_HEAD_SCALE if big else 1.0)


func hide_chain() -> void:
	visible = false


func _link_mesh() -> Mesh:
	var scene := CHAIN_LINK.instantiate()
	var mesh: Mesh = scene.find_children("*", "MeshInstance3D", true, false)[0].mesh
	scene.free()
	return mesh
