@tool
extends Node3D

@export var terrain_material: Material
@export var water_half_width := 2.9
@export var water_level := -0.3


func _ready() -> void:
	for mesh: MeshInstance3D in $Terrain.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = terrain_material


func is_water(point: Vector2) -> bool:
	return absf(point.x) < water_half_width
