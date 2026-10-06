class_name PowerUpVisual
extends Node3D

const ICONS: Array[Texture2D] = [
	preload("res://fx/textures/icon_shield.png"),
	preload("res://fx/textures/icon_haste.png"),
	preload("res://fx/textures/icon_gold.png"),
	preload("res://fx/textures/icon_big_hook.png"),
]
const BUBBLE_SHADER := preload("res://fx/bubble.gdshader")
const FLOAT_HEIGHT := 0.45
const BOB_HEIGHT := 0.08
const CARRIED_HEIGHT := 0.9

var kind := PowerUpState.Kind.SHIELD
var water_level := -0.3
var carried := false

var _ring: MeshInstance3D
var _phase := randf() * TAU


func setup(orb_kind: PowerUpState.Kind) -> void:
	kind = orb_kind
	var color := PowerUpState.COLORS[kind]
	var bubble := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 20
	sphere.rings = 10
	bubble.mesh = sphere
	var material := ShaderMaterial.new()
	material.shader = BUBBLE_SHADER
	material.set_shader_parameter("color", color)
	material.set_shader_parameter("fill", 0.22)
	bubble.material_override = material
	bubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bubble)
	var icon := Sprite3D.new()
	icon.texture = ICONS[kind]
	icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	icon.pixel_size = 0.0075
	icon.shaded = false
	icon.render_priority = 1
	add_child(icon)
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.5
	torus.outer_radius = 0.66
	torus.rings = 24
	torus.ring_segments = 6
	_ring.mesh = torus
	var ring_material := StandardMaterial3D.new()
	ring_material.albedo_color = color.lerp(Color.WHITE, 0.4)
	ring_material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	_ring.material_override = ring_material
	_ring.top_level = true
	add_child(_ring)


func place(point: Vector2, is_carried: bool) -> void:
	carried = is_carried
	var height := CARRIED_HEIGHT if carried else water_level + FLOAT_HEIGHT + sin(Time.get_ticks_msec() * 0.0025 + _phase) * BOB_HEIGHT
	global_position = Vector3(point.x, height, point.y)
	_ring.visible = not carried
	_ring.global_position = Vector3(point.x, water_level + 0.02, point.y)
	rotation.y += 0.02
