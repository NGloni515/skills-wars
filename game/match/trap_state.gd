class_name TrapState
extends RefCounted

var id := 0
var team := 0
var owner := 0
var position := Vector2.ZERO
var trigger_tick := 0
var sprung := false
var sprung_tick := 0
var radius := 1.8
var root_ticks := 0
var visible_ticks := 0


func to_row() -> Array:
	return [id, team, owner, position.x, position.y, trigger_tick, sprung, radius]


func apply_row(row: Array) -> TrapState:
	id = row[0]
	team = row[1]
	owner = row[2]
	position = Vector2(row[3], row[4])
	trigger_tick = row[5]
	sprung = row[6]
	radius = row[7]
	return self
