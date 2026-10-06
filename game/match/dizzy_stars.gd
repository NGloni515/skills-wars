class_name DizzyStars
extends Node3D

const COUNT := 4
const RADIUS := 0.45
const SPIN_SPEED := 4.5


func _ready() -> void:
	for i in COUNT:
		var star := Sprite3D.new()
		star.texture = Fx.TEXTURES[&"star"]
		star.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		star.modulate = Color(1.0, 0.9, 0.35)
		star.pixel_size = 0.0038
		star.shaded = false
		star.no_depth_test = true
		var angle := TAU * i / COUNT
		star.position = Vector3(cos(angle) * RADIUS, 0.0, sin(angle) * RADIUS)
		add_child(star)
	visible = false


func _process(delta: float) -> void:
	if visible:
		rotation.y += SPIN_SPEED * delta
