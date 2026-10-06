class_name ArrowVisual
extends Node3D

const COLOR := Color(0.55, 0.95, 1.0)
const SHAFT_LENGTH := 1.3

var _trail: GPUParticles3D


func _ready() -> void:
	top_level = true
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = COLOR.lerp(Color.WHITE, 0.35)
	var shaft := MeshInstance3D.new()
	var shaft_mesh := CylinderMesh.new()
	shaft_mesh.top_radius = 0.07
	shaft_mesh.bottom_radius = 0.07
	shaft_mesh.height = SHAFT_LENGTH
	shaft_mesh.radial_segments = 8
	shaft_mesh.material = material
	shaft.mesh = shaft_mesh
	shaft.rotation_degrees.x = 90.0
	add_child(shaft)
	var head := MeshInstance3D.new()
	var head_mesh := CylinderMesh.new()
	head_mesh.top_radius = 0.0
	head_mesh.bottom_radius = 0.2
	head_mesh.height = 0.4
	head_mesh.radial_segments = 8
	head_mesh.material = material
	head.mesh = head_mesh
	head.rotation_degrees.x = 90.0
	head.position.z = SHAFT_LENGTH * 0.5 + 0.18
	add_child(head)
	var glow := Sprite3D.new()
	glow.texture = Fx.TEXTURES[&"soft"]
	glow.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	glow.modulate = Color(COLOR, 0.8)
	glow.pixel_size = 0.016
	glow.shaded = false
	glow.position.z = SHAFT_LENGTH * 0.5
	add_child(glow)
	_trail = Fx.emitter(&"trail", COLOR)
	add_child(_trail)
	visible = false


func show_at(point: Vector3, direction: Vector3) -> void:
	if not visible:
		visible = true
		_trail.restart()
	global_transform = Transform3D(Basis.looking_at(direction, Vector3.UP, true), point)
	_trail.emitting = true


func hide_arrow() -> void:
	visible = false
	_trail.emitting = false
