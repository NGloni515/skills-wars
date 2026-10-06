class_name PowerUpState
extends RefCounted

enum Kind { SHIELD, HASTE, GOLD, BIG_HOOK }

const NAMES: Array[String] = ["Shield", "Haste", "Gold", "Big hook"]
const COLORS: Array[Color] = [Color(0.35, 0.8, 1.0), Color(1.0, 0.85, 0.2), Color(1.0, 0.7, 0.15), Color(0.95, 0.4, 0.95)]

var id := 0
var kind := Kind.SHIELD
var position := Vector2.ZERO
var carried_by := 0


func to_row() -> Array:
	return [id, kind, position.x, position.y, carried_by]


func apply_row(row: Array) -> PowerUpState:
	id = row[0]
	kind = row[1]
	position = Vector2(row[2], row[3])
	carried_by = row[4]
	return self
