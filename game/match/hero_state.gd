class_name HeroState
extends RefCounted

enum Life { ALIVE, CAUGHT, DEAD }
enum Action { NONE, CASTING, HOOK_OUT, HOOK_BACK }

var peer_id := 0
var definition: HeroDefinition
var team := 0
var slot := 0
var is_bot := false

var position := Vector2.ZERO
var facing := 0.0
var moving := false

var life := Life.ALIVE
var life_tick := 0
var caught_by := 0

var action := Action.NONE
var action_tick := 0
var cooldown_until := 0
var hook_direction := Vector2.RIGHT
var hook_origin := Vector2.ZERO
var hook_head := Vector2.ZERO
var hook_target := 0
var hook_kills := false

var gold := 0
var upgrades: Array[int] = [0, 0, 0, 0]

var last_input_seq := 0
var last_move := Vector2.ZERO
var pending_inputs := {}


func hook_visible() -> bool:
	return action == Action.HOOK_OUT or action == Action.HOOK_BACK


func can_act() -> bool:
	return life == Life.ALIVE and action == Action.NONE


func hook_range() -> float:
	return definition.hook.max_range + upgrades[HookSkill.Upgrade.RANGE] * definition.hook.range_per_level


func hook_speed() -> float:
	return definition.hook.speed + upgrades[HookSkill.Upgrade.SPEED] * definition.hook.speed_per_level


func hook_return_speed() -> float:
	return definition.hook.return_speed + upgrades[HookSkill.Upgrade.SPEED] * definition.hook.speed_per_level


func hook_radius() -> float:
	return definition.hook.hit_radius + upgrades[HookSkill.Upgrade.SIZE] * definition.hook.hit_radius_per_level


func hook_cooldown() -> float:
	return maxf(0.1, definition.hook.cooldown + upgrades[HookSkill.Upgrade.COOLDOWN] * definition.hook.cooldown_per_level)


func to_row() -> Array:
	return [
		peer_id, HeroRoster.index_of(definition.id), team,
		position.x, position.y, facing, moving,
		life, life_tick, action, action_tick,
		hook_head.x, hook_head.y, hook_direction.angle(), last_input_seq,
		gold, upgrades[0], upgrades[1], upgrades[2], upgrades[3],
	]


func apply_row(row: Array) -> HeroState:
	peer_id = row[0]
	definition = HeroRoster.ALL[row[1]]
	team = row[2]
	position = Vector2(row[3], row[4])
	facing = row[5]
	moving = row[6]
	life = row[7]
	life_tick = row[8]
	action = row[9]
	action_tick = row[10]
	hook_head = Vector2(row[11], row[12])
	hook_direction = Vector2.from_angle(row[13])
	last_input_seq = row[14]
	gold = row[15]
	upgrades = [row[16], row[17], row[18], row[19]]
	return self
