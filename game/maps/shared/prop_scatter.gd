@tool
class_name PropScatter
extends MultiMeshInstance3D

@export var source: PackedScene:
	set(value):
		source = value
		_rebuild()
@export var count := 40:
	set(value):
		count = value
		_rebuild()
@export var area := Rect2(-18, -15, 36, 30):
	set(value):
		area = value
		_rebuild()
@export var keep_out_half_width := 4.4:
	set(value):
		keep_out_half_width = value
		_rebuild()
@export var scale_range := Vector2(0.8, 1.2):
	set(value):
		scale_range = value
		_rebuild()
@export var random_seed := 1:
	set(value):
		random_seed = value
		_rebuild()


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if not is_inside_tree() or source == null:
		return
	var mesh := _first_mesh(source)
	if mesh == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	var transforms: Array[Transform3D] = []
	var attempts := 0
	while transforms.size() < count and attempts < count * 20:
		attempts += 1
		var x := rng.randf_range(area.position.x, area.end.x)
		var z := rng.randf_range(area.position.y, area.end.y)
		if absf(x) < keep_out_half_width:
			continue
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(scale_range.x, scale_range.y))
		transforms.append(Transform3D(basis, Vector3(x, 0.0, z)))
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.mesh = mesh
	instances.instance_count = transforms.size()
	for i in transforms.size():
		instances.set_instance_transform(i, transforms[i])
	multimesh = instances


func _first_mesh(scene: PackedScene) -> Mesh:
	var root := scene.instantiate()
	var found := root.find_children("*", "MeshInstance3D", true, false)
	var mesh: Mesh = found[0].mesh if found else null
	root.free()
	return mesh
