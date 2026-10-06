class_name BotBrain
extends RefCounted

const WANDER_SECONDS := Vector2(1.5, 3.5)
const FIRE_SECONDS := Vector2(1.6, 3.2)
const AIM_ERROR_DEGREES := 6.0
const ORB_AIM_ERROR_DEGREES := 2.5
const ARROW_CHANCE_PER_TICK := 1.0 / 90.0
const FEINT_CHANCE := 0.15
const TRAP_CHANCE_PER_TICK := 1.0 / 150.0
const DODGE_CHANCE := 0.7
const FEINT_RELEASE := Vector2(0.1, 0.3)
const BANK_X := Vector2(4.6, 12.0)
const BANK_Z := 13.0
const ENGAGE_X := 4.6

var _rng := RandomNumberGenerator.new()
var _wander_target := Vector2.ZERO
var _next_wander_tick := 0
var _next_fire_tick := 0
var _hook_aim := Vector2.ZERO
var _hold_until_tick := -1
var _dodged_casts := {}


func _init() -> void:
	_rng.randomize()
	_next_fire_tick = int(_rng.randf_range(FIRE_SECONDS.x, FIRE_SECONDS.y) * MatchSimulation.TICK_RATE)


func decide(me: HeroState, others: Array, tick: int, orbs: Array = []) -> Array:
	if me.life != HeroState.Life.ALIVE:
		_hold_until_tick = -1
		return [Vector2.ZERO, 0, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
	if tick >= _next_wander_tick or me.position.distance_to(_wander_target) < 0.5:
		var side := -1.0 if me.team == 0 else 1.0
		_wander_target = Vector2(side * _rng.randf_range(BANK_X.x, BANK_X.y), _rng.randf_range(-BANK_Z, BANK_Z))
		_next_wander_tick = tick + _seconds_to_ticks(WANDER_SECONDS)
	_react_to_trap_casts(me, others, tick)
	var move := (_wander_target - me.position).normalized()
	if tick < _hold_until_tick:
		return [move, MatchSimulation.HOOK_HELD, _hook_aim, Vector2.ZERO, Vector2.ZERO]
	if not me.can_act():
		return [move, 0, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
	var fire := _choose_hook(me, others, orbs, tick)
	if fire != Vector2.ZERO:
		_hook_aim = fire
		var hold := me.definition.hook.release_time + 0.1
		if _rng.randf() < FEINT_CHANCE:
			hold = _rng.randf_range(FEINT_RELEASE.x, FEINT_RELEASE.y)
			_next_fire_tick = tick + int(0.6 * MatchSimulation.TICK_RATE)
		_hold_until_tick = tick + int(hold * MatchSimulation.TICK_RATE)
		return [move, MatchSimulation.HOOK_PRESSED | MatchSimulation.HOOK_HELD, fire, Vector2.ZERO, Vector2.ZERO]
	var enemy := _closest_enemy(me, others, false)
	var arrow := Vector2.ZERO
	if enemy and tick >= me.arrow_cooldown_until and not me.arrow_flying and _rng.randf() < ARROW_CHANCE_PER_TICK:
		arrow = _lead(me, enemy, me.definition.arrow.cast_time, me.definition.arrow.speed, AIM_ERROR_DEGREES)
		return [move, 0, Vector2.ZERO, arrow, Vector2.ZERO]
	if enemy and tick >= me.trap_cooldown_until and _rng.randf() < TRAP_CHANCE_PER_TICK:
		var trap := me.definition.trap
		var velocity := enemy.last_move * enemy.move_speed() if enemy.moving else Vector2.ZERO
		return [move, MatchSimulation.TRAP_CAST, Vector2.ZERO, Vector2.ZERO, enemy.position + velocity * (trap.cast_time + trap.delay) * 0.6]
	return [move, 0, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]


func _react_to_trap_casts(me: HeroState, others: Array, tick: int) -> void:
	for other: HeroState in others:
		if other.team == me.team or other.action != HeroState.Action.TRAP_CAST:
			continue
		var key := "%d:%d" % [other.peer_id, other.action_tick]
		if _dodged_casts.has(key):
			continue
		_dodged_casts[key] = true
		if _rng.randf() < DODGE_CHANCE:
			var side := -1.0 if me.team == 0 else 1.0
			_wander_target = Vector2(side * _rng.randf_range(BANK_X.x, BANK_X.y), _rng.randf_range(-BANK_Z, BANK_Z))
			_next_wander_tick = tick + _seconds_to_ticks(WANDER_SECONDS)


func _choose_hook(me: HeroState, others: Array, orbs: Array, tick: int) -> Vector2:
	if tick < _next_fire_tick or tick < me.cooldown_until:
		return Vector2.ZERO
	var fire := Vector2.ZERO
	var stunned := _closest_enemy(me, others, true)
	var enemy := _closest_enemy(me, others, false)
	var orb := _closest_orb(me, orbs)
	if stunned and me.position.distance_to(stunned.position) <= me.hook_range():
		fire = _aim(me, stunned.position, ORB_AIM_ERROR_DEGREES)
	elif enemy and me.position.distance_to(enemy.position) <= me.hook_range():
		fire = _lead(me, enemy, me.definition.hook.release_time, me.hook_speed(), AIM_ERROR_DEGREES)
	elif orb:
		fire = _aim(me, orb.position, ORB_AIM_ERROR_DEGREES)
	elif enemy:
		var side := -1.0 if me.team == 0 else 1.0
		_wander_target = Vector2(side * ENGAGE_X, clampf(enemy.position.y, -BANK_Z, BANK_Z))
	if fire != Vector2.ZERO:
		_next_fire_tick = tick + _seconds_to_ticks(FIRE_SECONDS)
	return fire


func _lead(me: HeroState, target: HeroState, windup: float, speed: float, error_degrees: float) -> Vector2:
	var flight_time := windup + me.position.distance_to(target.position) / speed
	var velocity := target.last_move * target.move_speed() if target.moving else Vector2.ZERO
	return _aim(me, target.position + velocity * flight_time, error_degrees)


func _aim(me: HeroState, point: Vector2, error_degrees: float) -> Vector2:
	return (point - me.position).normalized().rotated(deg_to_rad(_rng.randf_range(-error_degrees, error_degrees)))


func _closest_orb(me: HeroState, orbs: Array) -> PowerUpState:
	var best: PowerUpState = null
	for orb: PowerUpState in orbs:
		var distance := me.position.distance_to(orb.position)
		if orb.carried_by == 0 and distance <= me.hook_range() and (best == null or distance < me.position.distance_to(best.position)):
			best = orb
	return best


func _closest_enemy(me: HeroState, others: Array, stunned_only: bool) -> HeroState:
	var best: HeroState = null
	for other: HeroState in others:
		if other.team == me.team or other.life != HeroState.Life.ALIVE or (stunned_only and not other.stunned):
			continue
		if best == null or me.position.distance_to(other.position) < me.position.distance_to(best.position):
			best = other
	return best


func _seconds_to_ticks(range_seconds: Vector2) -> int:
	return int(_rng.randf_range(range_seconds.x, range_seconds.y) * MatchSimulation.TICK_RATE)
