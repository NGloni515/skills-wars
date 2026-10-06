class_name BotBrain
extends RefCounted

const WANDER_SECONDS := Vector2(1.5, 3.5)
const FIRE_SECONDS := Vector2(1.6, 3.2)
const AIM_ERROR_DEGREES := 6.0
const BANK_X := Vector2(4.6, 12.0)
const BANK_Z := 13.0
const ENGAGE_X := 4.6

var _rng := RandomNumberGenerator.new()
var _wander_target := Vector2.ZERO
var _next_wander_tick := 0
var _next_fire_tick := 0


func _init() -> void:
	_rng.randomize()
	_next_fire_tick = int(_rng.randf_range(FIRE_SECONDS.x, FIRE_SECONDS.y) * MatchSimulation.TICK_RATE)


func decide(me: HeroState, others: Array, tick: int) -> Array:
	if me.life != HeroState.Life.ALIVE:
		return [Vector2.ZERO, Vector2.ZERO]
	if tick >= _next_wander_tick or me.position.distance_to(_wander_target) < 0.5:
		var side := -1.0 if me.team == 0 else 1.0
		_wander_target = Vector2(side * _rng.randf_range(BANK_X.x, BANK_X.y), _rng.randf_range(-BANK_Z, BANK_Z))
		_next_wander_tick = tick + _seconds_to_ticks(WANDER_SECONDS)
	var fire := Vector2.ZERO
	var enemy := _closest_enemy(me, others)
	if enemy and me.can_act() and tick >= _next_fire_tick:
		var skill := me.definition.hook
		var distance := me.position.distance_to(enemy.position)
		if distance <= me.hook_range():
			var flight_time := skill.release_time + distance / me.hook_speed()
			var velocity := enemy.last_move * enemy.definition.move_speed if enemy.moving else Vector2.ZERO
			var error := deg_to_rad(_rng.randf_range(-AIM_ERROR_DEGREES, AIM_ERROR_DEGREES))
			fire = (enemy.position + velocity * flight_time - me.position).normalized().rotated(error)
			_next_fire_tick = tick + _seconds_to_ticks(FIRE_SECONDS)
		else:
			var side := -1.0 if me.team == 0 else 1.0
			_wander_target = Vector2(side * ENGAGE_X, clampf(enemy.position.y, -BANK_Z, BANK_Z))
	return [(_wander_target - me.position).normalized(), fire]


func _closest_enemy(me: HeroState, others: Array) -> HeroState:
	var best: HeroState = null
	for other: HeroState in others:
		if other.team == me.team or other.life != HeroState.Life.ALIVE:
			continue
		if best == null or me.position.distance_to(other.position) < me.position.distance_to(best.position):
			best = other
	return best


func _seconds_to_ticks(range_seconds: Vector2) -> int:
	return int(_rng.randf_range(range_seconds.x, range_seconds.y) * MatchSimulation.TICK_RATE)
