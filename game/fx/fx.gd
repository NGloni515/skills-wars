class_name Fx
extends RefCounted

const TEXTURES := {
	&"soft": preload("res://fx/textures/soft.png"),
	&"drop": preload("res://fx/textures/drop.png"),
	&"ring": preload("res://fx/textures/ring.png"),
	&"star": preload("res://fx/textures/star.png"),
	&"spark": preload("res://fx/textures/spark.png"),
}

const PRESETS := {
	&"impact": {
		"texture": &"star", "amount": 14, "lifetime": 0.45, "velocity": Vector2(4.0, 7.5), "spread": 180.0,
		"gravity": Vector3(0, -3, 0), "scale": Vector2(0.3, 0.5), "color": Color(1.0, 0.92, 0.45), "spin": 360.0,
	},
	&"sparks": {
		"texture": &"spark", "amount": 12, "lifetime": 0.3, "velocity": Vector2(5.0, 9.0), "spread": 75.0,
		"gravity": Vector3(0, -9, 0), "scale": Vector2(0.18, 0.28), "color": Color(1.0, 0.75, 0.3), "spin": 90.0,
	},
	&"splash": {
		"texture": &"drop", "amount": 20, "lifetime": 0.7, "velocity": Vector2(3.0, 5.5), "spread": 35.0,
		"gravity": Vector3(0, -12, 0), "scale": Vector2(0.14, 0.26), "color": Color(0.85, 0.97, 1.0),
	},
	&"poof": {
		"texture": &"soft", "amount": 12, "lifetime": 0.75, "velocity": Vector2(1.0, 2.4), "spread": 180.0,
		"gravity": Vector3(0, 0.8, 0), "scale": Vector2(0.6, 0.95), "color": Color(0.92, 0.92, 0.9), "damping": 2.5,
		"grow": true,
	},
	&"sparkles": {
		"texture": &"star", "amount": 16, "lifetime": 0.85, "velocity": Vector2(1.6, 3.0), "spread": 25.0,
		"gravity": Vector3(0, -1.0, 0), "scale": Vector2(0.15, 0.28), "color": Color.WHITE, "spin": 180.0,
		"ring_radius": 0.8,
	},
	&"trail": {
		"texture": &"star", "amount": 12, "lifetime": 0.45, "velocity": Vector2(0.2, 0.6), "spread": 180.0,
		"gravity": Vector3(0, 0.5, 0), "scale": Vector2(0.12, 0.2), "color": Color(1.0, 0.9, 0.35), "spin": 180.0,
	},
	&"glow": {
		"texture": &"star", "amount": 8, "lifetime": 0.5, "velocity": Vector2(0.3, 0.8), "spread": 180.0,
		"gravity": Vector3(0, 0.8, 0), "scale": Vector2(0.1, 0.18), "color": Color(0.95, 0.45, 0.95), "spin": 180.0,
	},
	&"dust": {
		"texture": &"soft", "amount": 3, "lifetime": 0.5, "velocity": Vector2(0.4, 1.0), "spread": 60.0,
		"gravity": Vector3(0, 0.6, 0), "scale": Vector2(0.25, 0.4), "color": Color(0.82, 0.74, 0.58, 0.55),
		"damping": 1.5, "grow": true,
	},
}

static var _process_materials := {}
static var _draw_meshes := {}
static var _ring_mesh: QuadMesh


static func burst(parent: Node, position: Vector3, preset: StringName, tint := Color.WHITE, direction := Vector3.UP) -> GPUParticles3D:
	var particles := emitter(preset, tint)
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.process_material = particles.process_material.duplicate() if direction != Vector3.UP else particles.process_material
	(particles.process_material as ParticleProcessMaterial).direction = direction
	parent.add_child(particles)
	particles.global_position = position
	particles.emitting = true
	particles.finished.connect(particles.queue_free)
	return particles


static func emitter(preset: StringName, tint := Color.WHITE) -> GPUParticles3D:
	var settings: Dictionary = PRESETS[preset]
	var particles := GPUParticles3D.new()
	particles.amount = settings.amount
	particles.lifetime = settings.lifetime
	particles.local_coords = false
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.process_material = _process_material(preset)
	particles.draw_pass_1 = _draw_mesh(settings.texture)
	particles.set_instance_shader_parameter("tint", tint)
	return particles


static func ground_ring(color: Color, radius: float) -> MeshInstance3D:
	if _ring_mesh == null:
		_ring_mesh = QuadMesh.new()
		_ring_mesh.orientation = PlaneMesh.FACE_Y
		var material := _sprite_material(TEXTURES[&"ring"])
		material.set_shader_parameter("billboard", false)
		_ring_mesh.material = material
	var ring := MeshInstance3D.new()
	ring.mesh = _ring_mesh
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.set_instance_shader_parameter("tint", color)
	# The ring texture peaks at 80% of the quad's half-size.
	ring.scale = Vector3.ONE * radius * 2.5
	return ring


static func shockwave(parent: Node, position: Vector3, color: Color, radius: float, seconds := 0.4) -> void:
	var ring := ground_ring(color, radius)
	parent.add_child(ring)
	ring.global_position = position
	ring.scale = Vector3.ONE * radius * 0.3
	var tween := ring.create_tween().set_parallel()
	tween.tween_property(ring, "scale", Vector3.ONE * radius * 2.0, seconds).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_method(func(alpha: float) -> void: ring.set_instance_shader_parameter("tint", Color(color, alpha)), color.a, 0.0, seconds)
	tween.chain().tween_callback(ring.queue_free)


static func floating_text(parent: Node, position: Vector3, text: String, color: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0016
	label.font_size = 40
	label.outline_size = 12
	label.modulate = color
	label.outline_modulate = Color(0.1, 0.06, 0.0)
	parent.add_child(label)
	label.global_position = position
	var tween := label.create_tween().set_parallel()
	tween.tween_property(label, "position:y", label.position.y + 1.4, 0.9).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(label, "modulate:a", 0.0, 0.35).set_delay(0.55)
	tween.chain().tween_callback(label.queue_free)


static func warm_up(parent: Node) -> void:
	for preset: StringName in PRESETS:
		burst(parent, Vector3(0, -50, 0), preset)
	shockwave(parent, Vector3(0, -50, 0), Color.WHITE, 1.0, 0.05)


static func release() -> void:
	_process_materials.clear()
	_draw_meshes.clear()
	_ring_mesh = null


static func _process_material(preset: StringName) -> ParticleProcessMaterial:
	if _process_materials.has(preset):
		return _process_materials[preset]
	var settings: Dictionary = PRESETS[preset]
	var material := ParticleProcessMaterial.new()
	material.direction = Vector3.UP
	material.spread = settings.spread
	material.initial_velocity_min = settings.velocity.x
	material.initial_velocity_max = settings.velocity.y
	material.gravity = settings.gravity
	material.scale_min = settings.scale.x
	material.scale_max = settings.scale.y
	material.color = settings.color
	material.damping_min = settings.get("damping", 0.0)
	material.damping_max = settings.get("damping", 0.0)
	if settings.has("spin"):
		material.angle_min = 0.0
		material.angle_max = 360.0
		material.angular_velocity_min = -settings.spin
		material.angular_velocity_max = settings.spin
	if settings.has("ring_radius"):
		material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
		material.emission_ring_axis = Vector3.UP
		material.emission_ring_radius = settings.ring_radius
		material.emission_ring_inner_radius = settings.ring_radius * 0.8
		material.emission_ring_height = 0.05
	var fade := Gradient.new()
	fade.set_color(0, Color.WHITE)
	fade.set_color(1, Color(1, 1, 1, 0))
	var fade_texture := GradientTexture1D.new()
	fade_texture.gradient = fade
	material.color_ramp = fade_texture
	var size_curve := Curve.new()
	if settings.get("grow", false):
		size_curve.add_point(Vector2(0.0, 0.5))
		size_curve.add_point(Vector2(1.0, 1.0))
	else:
		size_curve.add_point(Vector2(0.0, 1.0))
		size_curve.add_point(Vector2(1.0, 0.2))
	var size_texture := CurveTexture.new()
	size_texture.curve = size_curve
	material.scale_curve = size_texture
	_process_materials[preset] = material
	return material


static func _draw_mesh(texture_name: StringName) -> QuadMesh:
	if _draw_meshes.has(texture_name):
		return _draw_meshes[texture_name]
	var mesh := QuadMesh.new()
	mesh.material = _sprite_material(TEXTURES[texture_name])
	_draw_meshes[texture_name] = mesh
	return mesh


static func _sprite_material(texture: Texture2D) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = preload("res://fx/fx_sprite.gdshader")
	material.set_shader_parameter("sprite", texture)
	return material
