class_name TrapVisual
extends Node3D

const MODEL := preload("res://heroes/gaff/bear_trap.glb")
const HERO_SHADER := preload("res://shared/shaders/hero.gdshader")
const SNAP_SECONDS := 0.08
const FADE_SECONDS := 0.4

var sprung := false
var total_ticks := 1.0

var _jaws: Array[Node3D] = []
var _area: MeshInstance3D
var _countdown: MeshInstance3D
var _radius := 0.0


func setup(radius: float, color: Color, model_scale: float) -> void:
	_radius = radius
	var model: Node3D = MODEL.instantiate()
	model.scale = Vector3.ONE * model_scale
	add_child(model)
	var material := ShaderMaterial.new()
	material.shader = HERO_SHADER
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = material
	_jaws = [model.find_child("JawFar", true, false), model.find_child("JawNear", true, false)]
	if radius > 0.0:
		_area = Fx.ground_ring(Color(color, 0.85), radius)
		add_child(_area)
		_area.position.y = 0.03
		_countdown = Fx.ground_ring(Color(1.0, 1.0, 1.0, 0.9), radius)
		add_child(_countdown)
		_countdown.position.y = 0.04


func show_countdown(ticks_left: float) -> void:
	if _countdown:
		var fraction := clampf(ticks_left / total_ticks, 0.0, 1.0)
		_countdown.scale = Vector3.ONE * maxf(_radius * fraction, 0.01) * 2.5


func spring(animate := true) -> void:
	if sprung:
		return
	sprung = true
	if _countdown:
		_countdown.visible = false
	var closed := [deg_to_rad(90.0), deg_to_rad(-90.0)]
	for i in _jaws.size():
		if animate:
			create_tween().tween_property(_jaws[i], "rotation:x", closed[i], SNAP_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		else:
			_jaws[i].rotation.x = closed[i]
	if _area:
		var tween := _area.create_tween()
		tween.tween_method(func(alpha: float) -> void: _area.set_instance_shader_parameter("tint", Color(1.0, 1.0, 1.0, alpha)), 1.0, 0.0, FADE_SECONDS)


func vanish() -> void:
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE * 0.01, FADE_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)
