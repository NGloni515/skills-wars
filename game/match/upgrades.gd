class_name Upgrades
extends RefCounted

enum Kind { HOOK_RANGE, HOOK_SPEED, HOOK_SIZE, HOOK_COOLDOWN, ARROW_SPEED, ARROW_STUN, TRAP_SIZE, TRAP_COOLDOWN }
enum Skill { HOOK, ARROW, TRAP }

const COUNT := 8
const SKILL_NAMES: Array[String] = ["Hook", "Arrow", "Trap"]
const SKILL_OF: Array[int] = [Skill.HOOK, Skill.HOOK, Skill.HOOK, Skill.HOOK, Skill.ARROW, Skill.ARROW, Skill.TRAP, Skill.TRAP]
const NAMES: Array[String] = ["Range", "Speed", "Size", "Cooldown", "Speed", "Stun", "Size", "Cooldown"]
const FULL_NAMES: Array[String] = ["Hook range", "Hook speed", "Hook size", "Hook cooldown", "Arrow speed", "Stun time", "Trap size", "Trap cooldown"]
const UNITS: Array[String] = ["m", "m/s", "m", "s", "m/s", "s", "m", "s"]
const DECIMALS: Array[int] = [1, 0, 2, 0, 1, 1, 2, 0]
# Quick buy falls back to the least upgraded of these, in this order, when nothing is starred.
const QUICK_BUY_ORDER: Array[int] = [
	Kind.HOOK_RANGE, Kind.HOOK_COOLDOWN, Kind.HOOK_SPEED, Kind.ARROW_STUN,
	Kind.TRAP_SIZE, Kind.HOOK_SIZE, Kind.ARROW_SPEED, Kind.TRAP_COOLDOWN,
]


static func none() -> Array[int]:
	var levels: Array[int] = []
	levels.resize(COUNT)
	levels.fill(0)
	return levels


static func stat(definition: HeroDefinition, kind: Kind, level: int) -> float:
	match kind:
		Kind.HOOK_RANGE:
			return definition.hook.max_range + level * definition.hook.range_per_level
		Kind.HOOK_SPEED:
			return definition.hook.speed + level * definition.hook.speed_per_level
		Kind.HOOK_SIZE:
			return definition.hook.hit_radius + level * definition.hook.hit_radius_per_level
		Kind.HOOK_COOLDOWN:
			return maxf(0.1, definition.hook.cooldown + level * definition.hook.cooldown_per_level)
		Kind.ARROW_SPEED:
			return definition.arrow.speed + level * definition.arrow.speed_per_level
		Kind.ARROW_STUN:
			return definition.arrow.stun_time + level * definition.arrow.stun_time_per_level
		Kind.TRAP_SIZE:
			return definition.trap.radius + level * definition.trap.radius_per_level
		Kind.TRAP_COOLDOWN:
			return maxf(1.0, definition.trap.cooldown + level * definition.trap.cooldown_per_level)
	return 0.0


static func format_stat(kind: Kind, value: float) -> String:
	return String.num(value, DECIMALS[kind])


static func next_cost(levels: Array[int], costs: PackedInt32Array, kind: Kind) -> int:
	return costs[levels[kind]] if levels[kind] < costs.size() else -1


static func any_affordable(levels: Array[int], costs: PackedInt32Array, gold: int) -> bool:
	for kind in COUNT:
		var cost := next_cost(levels, costs, kind)
		if cost >= 0 and cost <= gold:
			return true
	return false


static func quick_buy_target(levels: Array[int], costs: PackedInt32Array, starred: int) -> int:
	if starred >= 0 and levels[starred] < costs.size():
		return starred
	var best := -1
	for kind in QUICK_BUY_ORDER:
		if levels[kind] < costs.size() and (best < 0 or levels[kind] < levels[best]):
			best = kind
	return best
