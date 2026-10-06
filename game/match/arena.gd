class_name Arena
extends RefCounted

const HERO_WALL_LAYER := 2
const HOOK_WALL_LAYER := 4

var hero_walls: Array[Rect2] = []
var hero_blockers: Array[Vector3] = []
var hook_blockers: Array[Vector3] = []
var spawns: Array[Array] = [[], []]
var bounds := Rect2()


static func from_map(map: Node3D) -> Arena:
	var arena := Arena.new()
	for body: StaticBody3D in map.find_children("*", "StaticBody3D", true, false):
		for shape_node: CollisionShape3D in body.find_children("*", "CollisionShape3D", false, false):
			arena._add_shape(shape_node, body.collision_layer)
	for i in arena.hero_walls.size():
		arena.bounds = arena.hero_walls[i] if i == 0 else arena.bounds.merge(arena.hero_walls[i])
	for team in 2:
		for marker: Node3D in map.get_tree().get_nodes_in_group("spawn_team_%d" % team):
			if map.is_ancestor_of(marker):
				var forward := marker.global_basis.z
				arena.spawns[team].append({"position": _flat(marker.global_position), "facing": atan2(forward.x, forward.z)})
	return arena


func move_circle(from: Vector2, motion: Vector2, radius: float) -> Vector2:
	var p := from + motion
	for _pass in 2:
		for rect in hero_walls:
			p = _push_out_of_rect(p, radius, rect)
		for circle in hero_blockers:
			p = _push_out_of_circle(p, radius, circle)
	return p


func first_hook_blocker_hit(from: Vector2, to: Vector2, hook_radius: float) -> float:
	var nearest := INF
	for circle in hook_blockers:
		var t := _segment_circle_hit(from, to, Vector2(circle.x, circle.y), circle.z + hook_radius)
		if t < nearest:
			nearest = t
	return nearest


func spawn_point(team: int, slot: int) -> Dictionary:
	var options: Array = spawns[team]
	if options.is_empty():
		return {"position": Vector2(-12.0 if team == 0 else 12.0, 0.0), "facing": 0.0}
	return options[slot % options.size()]


static func distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := 0.0 if ab.length_squared() == 0.0 else clampf((point - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return point.distance_to(a + ab * t)


func _add_shape(shape_node: CollisionShape3D, layer: int) -> void:
	var center := _flat(shape_node.global_position)
	var shape := shape_node.shape
	if shape is BoxShape3D:
		var size: Vector3 = shape.size * shape_node.global_basis.get_scale()
		var rect := Rect2(center - Vector2(size.x, size.z) * 0.5, Vector2(size.x, size.z))
		if layer & HERO_WALL_LAYER:
			hero_walls.append(rect)
	elif shape is CylinderShape3D:
		var circle := Vector3(center.x, center.y, shape.radius)
		if layer & HERO_WALL_LAYER:
			hero_blockers.append(circle)
		if layer & HOOK_WALL_LAYER:
			hook_blockers.append(circle)


static func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


static func _push_out_of_rect(p: Vector2, radius: float, rect: Rect2) -> Vector2:
	var closest := p.clamp(rect.position, rect.end)
	var offset := p - closest
	var distance := offset.length()
	if distance >= radius:
		return p
	if distance > 0.0001:
		return closest + offset / distance * radius
	var to_left := p.x - rect.position.x
	var to_right := rect.end.x - p.x
	var to_top := p.y - rect.position.y
	var to_bottom := rect.end.y - p.y
	var smallest := minf(minf(to_left, to_right), minf(to_top, to_bottom))
	if smallest == to_left:
		return Vector2(rect.position.x - radius, p.y)
	if smallest == to_right:
		return Vector2(rect.end.x + radius, p.y)
	if smallest == to_top:
		return Vector2(p.x, rect.position.y - radius)
	return Vector2(p.x, rect.end.y + radius)


static func _push_out_of_circle(p: Vector2, radius: float, circle: Vector3) -> Vector2:
	var center := Vector2(circle.x, circle.y)
	var min_distance := radius + circle.z
	var offset := p - center
	if offset.length_squared() >= min_distance * min_distance:
		return p
	var direction := offset.normalized() if offset.length_squared() > 0.0001 else Vector2.RIGHT
	return center + direction * min_distance


static func _segment_circle_hit(a: Vector2, b: Vector2, center: Vector2, radius: float) -> float:
	var d := b - a
	var f := a - center
	var qa := d.dot(d)
	if qa == 0.0:
		return 0.0 if f.length() <= radius else INF
	var qb := 2.0 * f.dot(d)
	var qc := f.dot(f) - radius * radius
	if qc <= 0.0:
		return 0.0
	var discriminant := qb * qb - 4.0 * qa * qc
	if discriminant < 0.0:
		return INF
	var t := (-qb - sqrt(discriminant)) / (2.0 * qa)
	return t if t >= 0.0 and t <= 1.0 else INF
