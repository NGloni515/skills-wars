class_name HeroState
extends RefCounted

enum Life { ALIVE, CAUGHT, DEAD }
enum Action { NONE, CASTING, HOOK_OUT, HOOK_BACK, ARROW_CAST, TRAP_CAST }

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
var hook_powerup := 0
var hook_is_big := false
var hook_held := false
var hook_aim := Vector2.ZERO

var gold := 0
var upgrades: Array[int] = [0, 0, 0, 0]

var shield_until := 0
var haste_until := 0
var stunned_until := 0
var rooted_until := 0
var shielded := false
var stunned := false
var rooted := false
var speed_multiplier := 1.0
var big_hook_ready := false

var arrow_cooldown_until := 0
var arrow_direction := Vector2.RIGHT
var arrow_flying := false
var arrow_position := Vector2.ZERO

var trap_cooldown_until := 0
var trap_target := Vector2.ZERO

var last_input_seq := 0
var last_move := Vector2.ZERO
var pending_inputs := {}


func hook_visible() -> bool:
	return action == Action.HOOK_OUT or action == Action.HOOK_BACK


func can_act() -> bool:
	return life == Life.ALIVE and action == Action.NONE and not stunned


func can_move() -> bool:
	return can_act() and not rooted


func hook_range() -> float:
	return definition.hook.max_range + upgrades[HookSkill.Upgrade.RANGE] * definition.hook.range_per_level


func hook_speed() -> float:
	return definition.hook.speed + upgrades[HookSkill.Upgrade.SPEED] * definition.hook.speed_per_level


func hook_return_speed() -> float:
	return definition.hook.return_speed + upgrades[HookSkill.Upgrade.SPEED] * definition.hook.speed_per_level


func hook_radius() -> float:
	var radius := definition.hook.hit_radius + upgrades[HookSkill.Upgrade.SIZE] * definition.hook.hit_radius_per_level
	return radius * definition.hook.big_hook_multiplier if hook_is_big else radius


func move_speed() -> float:
	return definition.move_speed * speed_multiplier


func hook_cooldown() -> float:
	return maxf(0.1, definition.hook.cooldown + upgrades[HookSkill.Upgrade.COOLDOWN] * definition.hook.cooldown_per_level)


func to_row() -> Array:
	return [
		peer_id, HeroRoster.index_of(definition.id), team,
		position.x, position.y, facing, moving,
		life, life_tick, action, action_tick,
		hook_head.x, hook_head.y, hook_direction.angle(), last_input_seq,
		gold, upgrades[0], upgrades[1], upgrades[2], upgrades[3],
		shielded, speed_multiplier, big_hook_ready, hook_is_big, cooldown_until,
		caught_by, stunned, arrow_flying, arrow_position.x, arrow_position.y, arrow_direction.angle(), arrow_cooldown_until,
		rooted, trap_cooldown_until,
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
	shielded = row[20]
	speed_multiplier = row[21]
	big_hook_ready = row[22]
	hook_is_big = row[23]
	cooldown_until = row[24]
	caught_by = row[25]
	stunned = row[26]
	arrow_flying = row[27]
	arrow_position = Vector2(row[28], row[29])
	arrow_direction = Vector2.from_angle(row[30])
	arrow_cooldown_until = row[31]
	rooted = row[32]
	trap_cooldown_until = row[33]
	return self
