class_name MatchSimulation
extends RefCounted

signal hero_killed(victim: int, killer: int)
signal roster_changed
signal powerup_collected(peer_id: int, kind: PowerUpState.Kind)
signal shield_blocked(victim: int, attacker: int)
signal hero_stunned(victim: int, attacker: int)
signal hook_feinted(peer_id: int)
signal hero_trapped(victim: int, owner: int)

enum Phase { PLAYING, ENDED }

const TICK_RATE := 60
const HOOK_PRESSED := 1
const HOOK_HELD := 2
const TRAP_CAST := 4
const MAX_INPUT_BACKLOG := 8
const BOT_SHOPPING_INTERVAL := 2 * TICK_RATE
const ARROW_SPAWN_OFFSET := 0.6
const ARROW_EXIT_MARGIN := 1.0

var arena: Arena
var rules: MatchRules
var tick := 0
var heroes := {}
var names := {}
var score := [0, 0]
var phase := Phase.PLAYING
var phase_tick := 0
var winner := -1
var overtime := false
var fill_with_bots := false
var bots := {}
var powerups := {}
var traps := {}
var _next_bot_id := -1
var _next_powerup_id := 1
var _next_trap_id := 1
var _next_powerup_tick := 0
var _rng := RandomNumberGenerator.new()


func _init(match_arena: Arena, match_rules: MatchRules) -> void:
	arena = match_arena
	rules = match_rules
	_rng.randomize()
	_next_powerup_tick = int(rules.powerup_interval * TICK_RATE)


func add_player(peer_id: int, definition: HeroDefinition, display_name: String) -> HeroState:
	var hero := _add_hero(peer_id, definition, _team_for(false))
	names[peer_id] = display_name
	if fill_with_bots:
		balance_bots()
	roster_changed.emit()
	return hero


func add_bot(definition: HeroDefinition, team := -1) -> HeroState:
	var bot_id := _next_bot_id
	_next_bot_id -= 1
	var hero := _add_hero(bot_id, definition, team if team >= 0 else _team_for(true))
	hero.is_bot = true
	bots[bot_id] = BotBrain.new()
	names[bot_id] = "Bot %d" % -bot_id
	roster_changed.emit()
	return hero


func remove_hero(peer_id: int) -> void:
	var hero: HeroState = heroes.get(peer_id)
	if hero == null:
		return
	_cancel_hook(hero)
	var catcher: HeroState = heroes.get(hero.caught_by)
	if catcher:
		catcher.hook_target = 0
	heroes.erase(peer_id)
	bots.erase(peer_id)
	names.erase(peer_id)
	if fill_with_bots and not hero.is_bot:
		balance_bots()
	roster_changed.emit()


func balance_bots() -> void:
	for team in 2:
		var wanted := maxi(0, rules.team_size - _count(team, false))
		var team_bots := _bots_in(team)
		while team_bots.size() > wanted:
			remove_hero(team_bots.pop_back().peer_id)
		for i in wanted - team_bots.size():
			add_bot(HeroRoster.ALL[0], team)


func human_count() -> int:
	return _count(0, false) + _count(1, false)


func push_input(peer_id: int, seq: int, move: Vector2, flags := 0, hook_aim := Vector2.ZERO, arrow := Vector2.ZERO, trap_target := Vector2.ZERO) -> void:
	var hero: HeroState = heroes.get(peer_id)
	if hero == null or seq <= hero.last_input_seq or hero.pending_inputs.has(seq):
		return
	hero.pending_inputs[seq] = [move.limit_length(1.0), flags, hook_aim.limit_length(1.0), arrow, trap_target]


func try_buy(peer_id: int, upgrade: int) -> bool:
	var hero: HeroState = heroes.get(peer_id)
	if hero == null or phase != Phase.PLAYING or upgrade < 0 or upgrade >= hero.upgrades.size():
		return false
	var level := hero.upgrades[upgrade]
	if level >= rules.upgrade_costs.size() or hero.gold < rules.upgrade_costs[level]:
		return false
	hero.gold -= rules.upgrade_costs[level]
	hero.upgrades[upgrade] += 1
	return true


func ticks_left() -> int:
	if phase == Phase.ENDED:
		return maxi(0, int(rules.restart_delay * TICK_RATE) - (tick - phase_tick))
	return maxi(0, int(rules.time_limit * TICK_RATE) - (tick - phase_tick))


func step() -> void:
	tick += 1
	if phase == Phase.ENDED:
		for hero: HeroState in heroes.values():
			_discard_inputs(hero)
		if ticks_left() == 0:
			restart()
		return
	var delta := 1.0 / TICK_RATE
	_update_effects()
	for peer_id: int in bots:
		var hero: HeroState = heroes[peer_id]
		var command: Array = bots[peer_id].decide(hero, heroes.values(), tick, powerups.values())
		push_input(peer_id, hero.last_input_seq + 1, command[0], command[1], command[2], command[3], command[4])
		if (tick + peer_id) % BOT_SHOPPING_INTERVAL == 0:
			_bot_shop(hero)
	for hero: HeroState in heroes.values():
		_consume_inputs(hero, delta)
	for hero: HeroState in heroes.values():
		_update_hook(hero, delta)
		_update_arrow(hero, delta)
		_update_trap_cast(hero)
	_update_traps()
	for hero: HeroState in heroes.values():
		if hero.life == HeroState.Life.DEAD and tick - hero.life_tick >= int(rules.respawn_time * TICK_RATE):
			_respawn(hero)
		if tick % TICK_RATE == 0:
			hero.gold += rules.gold_per_second
	_spawn_powerups()
	_check_end()


func restart() -> void:
	score = [0, 0]
	phase = Phase.PLAYING
	phase_tick = tick
	winner = -1
	overtime = false
	powerups.clear()
	traps.clear()
	_next_powerup_tick = tick + int(rules.powerup_interval * TICK_RATE)
	for hero: HeroState in heroes.values():
		_cancel_hook(hero)
		hero.gold = 0
		hero.upgrades = [0, 0, 0, 0]
		hero.cooldown_until = 0
		hero.arrow_cooldown_until = 0
		hero.arrow_flying = false
		hero.trap_cooldown_until = 0
		_respawn(hero)


static func apply_move(arena_geometry: Arena, hero: HeroState, move: Vector2, delta: float) -> void:
	hero.moving = move.length_squared() > 0.01 and hero.can_move()
	if not hero.moving:
		return
	hero.position = arena_geometry.move_circle(hero.position, move * hero.move_speed() * delta, hero.definition.radius)
	hero.facing = atan2(move.x, move.y)


func snapshot(viewer_team := -1) -> Array:
	var rows := []
	for hero: HeroState in heroes.values():
		rows.append(hero.to_row())
	var orb_rows := []
	for orb: PowerUpState in powerups.values():
		orb_rows.append(orb.to_row())
	var trap_rows := []
	for trap: TrapState in traps.values():
		if viewer_team < 0 or trap.team == viewer_team or trap.sprung:
			trap_rows.append(trap.to_row())
	return [tick, rows, score[0], score[1], phase, ticks_left(), winner, overtime, orb_rows, trap_rows]


func _add_hero(peer_id: int, definition: HeroDefinition, team: int) -> HeroState:
	var hero := HeroState.new()
	hero.peer_id = peer_id
	hero.definition = definition
	hero.team = team
	hero.slot = _count(team, true)
	heroes[peer_id] = hero
	_respawn(hero)
	return hero


func _consume_inputs(hero: HeroState, delta: float) -> void:
	var to_process := 1 if hero.pending_inputs.size() <= MAX_INPUT_BACKLOG / 2 else 2
	for i in to_process:
		var next_seq := hero.last_input_seq + 1
		if not hero.pending_inputs.has(next_seq):
			var queued := hero.pending_inputs.keys()
			if queued.is_empty():
				if i == 0:
					apply_move(arena, hero, hero.last_move, delta)
				return
			queued.sort()
			next_seq = queued[0]
		var input: Array = hero.pending_inputs[next_seq]
		hero.pending_inputs.erase(next_seq)
		hero.last_input_seq = next_seq
		hero.last_move = input[0]
		var hook_flags: int = input[1]
		hero.hook_held = hook_flags & HOOK_HELD != 0
		if input[2] != Vector2.ZERO:
			hero.hook_aim = input[2]
		if hook_flags & HOOK_PRESSED:
			_start_cast(hero, input[2])
		elif input[3] != Vector2.ZERO:
			_start_arrow(hero, input[3])
		elif hook_flags & TRAP_CAST:
			_start_trap(hero, input[4])
		apply_move(arena, hero, input[0], delta)


func _discard_inputs(hero: HeroState) -> void:
	for seq: int in hero.pending_inputs:
		hero.last_input_seq = maxi(hero.last_input_seq, seq)
	hero.pending_inputs.clear()
	hero.last_move = Vector2.ZERO


func _start_cast(hero: HeroState, aim: Vector2) -> void:
	if not hero.can_act() or tick < hero.cooldown_until:
		return
	hero.hook_aim = aim
	hero.hook_direction = aim.normalized() if aim != Vector2.ZERO else Vector2(sin(hero.facing), cos(hero.facing))
	hero.facing = atan2(hero.hook_direction.x, hero.hook_direction.y)
	hero.hook_is_big = hero.big_hook_ready
	hero.big_hook_ready = false
	_set_action(hero, HeroState.Action.CASTING)


func _feint(hero: HeroState) -> void:
	if hero.hook_is_big:
		hero.big_hook_ready = true
		hero.hook_is_big = false
	_set_action(hero, HeroState.Action.NONE)
	hook_feinted.emit(hero.peer_id)


func _start_arrow(hero: HeroState, direction: Vector2) -> void:
	if not hero.can_act() or tick < hero.arrow_cooldown_until or hero.arrow_flying:
		return
	hero.arrow_direction = direction.normalized()
	hero.facing = atan2(hero.arrow_direction.x, hero.arrow_direction.y)
	hero.arrow_cooldown_until = tick + int(hero.definition.arrow.cooldown * TICK_RATE)
	_set_action(hero, HeroState.Action.ARROW_CAST)


func _update_arrow(hero: HeroState, delta: float) -> void:
	var skill := hero.definition.arrow
	if hero.action == HeroState.Action.ARROW_CAST and tick - hero.action_tick >= int(skill.cast_time * TICK_RATE):
		hero.arrow_flying = true
		hero.arrow_position = hero.position + hero.arrow_direction * ARROW_SPAWN_OFFSET
		_set_action(hero, HeroState.Action.NONE)
	if not hero.arrow_flying:
		return
	var from := hero.arrow_position
	var to := from + hero.arrow_direction * skill.speed * delta
	if skill.blocked_by_rocks and arena.first_hook_blocker_hit(from, to, skill.hit_radius) <= 1.0:
		hero.arrow_flying = false
		return
	var victim: HeroState = null
	for other: HeroState in heroes.values():
		if other.team == hero.team or other.life != HeroState.Life.ALIVE:
			continue
		if Arena.distance_to_segment(other.position, from, to) <= skill.hit_radius + other.definition.radius:
			if victim == null or from.distance_to(other.position) < from.distance_to(victim.position):
				victim = other
	hero.arrow_position = to
	if victim:
		hero.arrow_flying = false
		_arrow_hit(hero, victim)
	elif not arena.bounds.grow(ARROW_EXIT_MARGIN).has_point(to):
		hero.arrow_flying = false


func _start_trap(hero: HeroState, target: Vector2) -> void:
	if not hero.can_act() or tick < hero.trap_cooldown_until:
		return
	var skill := hero.definition.trap
	var offset := (target - hero.position).limit_length(skill.max_distance)
	hero.trap_target = (hero.position + offset).clamp(arena.bounds.position, arena.bounds.end)
	if offset.length_squared() > 0.01:
		hero.facing = atan2(offset.x, offset.y)
	hero.trap_cooldown_until = tick + int(skill.cooldown * TICK_RATE)
	_set_action(hero, HeroState.Action.TRAP_CAST)


func _update_trap_cast(hero: HeroState) -> void:
	var skill := hero.definition.trap
	if hero.action != HeroState.Action.TRAP_CAST or tick - hero.action_tick < int(skill.cast_time * TICK_RATE):
		return
	var trap := TrapState.new()
	trap.id = _next_trap_id
	_next_trap_id += 1
	trap.team = hero.team
	trap.owner = hero.peer_id
	trap.position = hero.trap_target
	trap.radius = skill.radius
	trap.root_ticks = int(skill.root_time * TICK_RATE)
	trap.visible_ticks = int(skill.sprung_visible_time * TICK_RATE)
	trap.trigger_tick = tick + int(skill.delay * TICK_RATE)
	traps[trap.id] = trap
	_set_action(hero, HeroState.Action.NONE)


func _update_traps() -> void:
	for trap: TrapState in traps.values():
		if not trap.sprung and tick >= trap.trigger_tick:
			_spring(trap)
		elif trap.sprung and tick - trap.sprung_tick >= trap.visible_ticks:
			traps.erase(trap.id)


func _spring(trap: TrapState) -> void:
	trap.sprung = true
	trap.sprung_tick = tick
	for hero: HeroState in heroes.values():
		if hero.team == trap.team or hero.life != HeroState.Life.ALIVE:
			continue
		if hero.position.distance_to(trap.position) > trap.radius:
			continue
		if tick < hero.shield_until:
			hero.shield_until = 0
			hero.shielded = false
			shield_blocked.emit(hero.peer_id, trap.owner)
			continue
		hero.rooted_until = tick + trap.root_ticks
		hero.rooted = true
		hero.moving = false
		hero_trapped.emit(hero.peer_id, trap.owner)


func _arrow_hit(shooter: HeroState, victim: HeroState) -> void:
	if tick < victim.shield_until:
		victim.shield_until = 0
		victim.shielded = false
		shield_blocked.emit(victim.peer_id, shooter.peer_id)
		return
	victim.stunned_until = tick + int(shooter.definition.arrow.stun_time * TICK_RATE)
	victim.stunned = true
	victim.moving = false
	_cancel_hook(victim)
	hero_stunned.emit(victim.peer_id, shooter.peer_id)


func _update_hook(hero: HeroState, delta: float) -> void:
	var skill := hero.definition.hook
	match hero.action:
		HeroState.Action.CASTING:
			if not hero.hook_held:
				_feint(hero)
				return
			if hero.hook_aim != Vector2.ZERO:
				hero.hook_direction = hero.hook_aim.normalized()
				hero.facing = atan2(hero.hook_direction.x, hero.hook_direction.y)
			if tick - hero.action_tick >= int(skill.release_time * TICK_RATE):
				hero.hook_origin = hero.position + hero.hook_direction * skill.origin_offset
				hero.hook_head = hero.hook_origin
				hero.cooldown_until = tick + int(hero.hook_cooldown() * TICK_RATE)
				_set_action(hero, HeroState.Action.HOOK_OUT)
		HeroState.Action.HOOK_OUT:
			var from := hero.hook_head
			var to := from + hero.hook_direction * hero.hook_speed() * delta
			var traveled := hero.hook_origin.distance_to(to)
			if traveled >= hero.hook_range():
				to = hero.hook_origin + hero.hook_direction * hero.hook_range()
			var blocked := arena.first_hook_blocker_hit(from, to, hero.hook_radius())
			if blocked <= 1.0:
				to = from.lerp(to, blocked)
			var victim := _first_hero_hit(hero, from, to)
			var orb := _first_powerup_hit(hero, from, to)
			hero.hook_head = to
			if victim and (orb == null or from.distance_to(victim.position) <= from.distance_to(orb.position)):
				_catch(hero, victim)
			elif orb:
				orb.carried_by = hero.peer_id
				hero.hook_powerup = orb.id
				_set_action(hero, HeroState.Action.HOOK_BACK)
			elif blocked <= 1.0 or traveled >= hero.hook_range():
				_set_action(hero, HeroState.Action.HOOK_BACK)
		HeroState.Action.HOOK_BACK:
			var home := hero.position + hero.hook_direction * skill.origin_offset
			hero.hook_head = hero.hook_head.move_toward(home, hero.hook_return_speed() * delta)
			var target: HeroState = heroes.get(hero.hook_target)
			if target and target.caught_by == hero.peer_id:
				target.position = hero.hook_head
			var carried: PowerUpState = powerups.get(hero.hook_powerup)
			if carried:
				carried.position = hero.hook_head
			if hero.hook_head.is_equal_approx(home):
				_finish_hook(hero, target)


func _first_hero_hit(owner: HeroState, from: Vector2, to: Vector2) -> HeroState:
	var best: HeroState = null
	var best_distance := INF
	for other: HeroState in heroes.values():
		if other == owner or other.life != HeroState.Life.ALIVE:
			continue
		if Arena.distance_to_segment(other.position, from, to) <= owner.hook_radius() + other.definition.radius:
			var distance := from.distance_to(other.position)
			if distance < best_distance:
				best = other
				best_distance = distance
	return best


func _first_powerup_hit(owner: HeroState, from: Vector2, to: Vector2) -> PowerUpState:
	var best: PowerUpState = null
	for orb: PowerUpState in powerups.values():
		if orb.carried_by != 0:
			continue
		if Arena.distance_to_segment(orb.position, from, to) <= owner.hook_radius() + rules.powerup_radius:
			if best == null or from.distance_to(orb.position) < from.distance_to(best.position):
				best = orb
	return best


func _catch(hero: HeroState, victim: HeroState) -> void:
	if victim.team != hero.team and tick < victim.shield_until:
		victim.shield_until = 0
		victim.shielded = false
		shield_blocked.emit(victim.peer_id, hero.peer_id)
		_set_action(hero, HeroState.Action.HOOK_BACK)
		return
	hero.hook_target = victim.peer_id
	hero.hook_kills = victim.team != hero.team
	victim.caught_by = hero.peer_id
	victim.life = HeroState.Life.CAUGHT
	victim.life_tick = tick
	victim.moving = false
	_cancel_hook(victim)
	if hero.hook_kills:
		score[hero.team] += 1
		hero.gold += rules.gold_per_kill
		hero_killed.emit(victim.peer_id, hero.peer_id)
	_set_action(hero, HeroState.Action.HOOK_BACK)


func _finish_hook(hero: HeroState, target: HeroState) -> void:
	_set_action(hero, HeroState.Action.NONE)
	hero.hook_target = 0
	hero.hook_is_big = false
	var orb: PowerUpState = powerups.get(hero.hook_powerup)
	if orb and orb.carried_by == hero.peer_id:
		powerups.erase(orb.id)
		_apply_powerup(hero, orb.kind)
	hero.hook_powerup = 0
	if target == null or target.caught_by != hero.peer_id:
		return
	target.caught_by = 0
	target.life_tick = tick
	if hero.hook_kills:
		target.life = HeroState.Life.DEAD
	else:
		target.life = HeroState.Life.ALIVE
		target.position = arena.move_circle(target.position, Vector2.ZERO, target.definition.radius)


func _cancel_hook(hero: HeroState) -> void:
	var target: HeroState = heroes.get(hero.hook_target)
	if target and target.caught_by == hero.peer_id:
		target.caught_by = 0
		target.life_tick = tick
		target.life = HeroState.Life.DEAD if hero.hook_kills else HeroState.Life.ALIVE
	hero.hook_target = 0
	var orb: PowerUpState = powerups.get(hero.hook_powerup)
	if orb and orb.carried_by == hero.peer_id:
		orb.carried_by = 0
		orb.position.x = clampf(orb.position.x, -rules.powerup_lane_half_width, rules.powerup_lane_half_width)
	hero.hook_powerup = 0
	hero.hook_is_big = false
	if hero.action != HeroState.Action.NONE:
		_set_action(hero, HeroState.Action.NONE)


func _set_action(hero: HeroState, action: HeroState.Action) -> void:
	hero.action = action
	hero.action_tick = tick


func _respawn(hero: HeroState) -> void:
	var spawn := arena.spawn_point(hero.team, hero.slot)
	hero.position = spawn.position
	hero.facing = spawn.facing
	hero.life = HeroState.Life.ALIVE
	hero.life_tick = tick
	hero.caught_by = 0
	hero.moving = false
	hero.shield_until = 0
	hero.haste_until = 0
	hero.stunned_until = 0
	hero.stunned = false
	hero.rooted_until = 0
	hero.rooted = false
	hero.big_hook_ready = false
	_set_action(hero, HeroState.Action.NONE)


func _update_effects() -> void:
	for hero: HeroState in heroes.values():
		hero.shielded = tick < hero.shield_until
		hero.stunned = tick < hero.stunned_until
		hero.rooted = tick < hero.rooted_until
		hero.speed_multiplier = rules.haste_multiplier if tick < hero.haste_until else 1.0


func _spawn_powerups() -> void:
	if tick < _next_powerup_tick:
		return
	_next_powerup_tick = tick + int(rules.powerup_interval * TICK_RATE)
	if powerups.size() >= rules.max_powerups:
		return
	var orb := PowerUpState.new()
	orb.id = _next_powerup_id
	_next_powerup_id += 1
	orb.kind = _rng.randi_range(0, PowerUpState.Kind.size() - 1) as PowerUpState.Kind
	orb.position = Vector2(
		_rng.randf_range(-rules.powerup_lane_half_width, rules.powerup_lane_half_width),
		_rng.randf_range(-rules.powerup_lane_half_length, rules.powerup_lane_half_length),
	)
	powerups[orb.id] = orb


func _apply_powerup(hero: HeroState, kind: PowerUpState.Kind) -> void:
	match kind:
		PowerUpState.Kind.SHIELD:
			hero.shield_until = tick + int(rules.shield_time * TICK_RATE)
		PowerUpState.Kind.HASTE:
			hero.haste_until = tick + int(rules.haste_time * TICK_RATE)
		PowerUpState.Kind.GOLD:
			hero.gold += rules.gold_bag
		PowerUpState.Kind.BIG_HOOK:
			hero.big_hook_ready = true
	powerup_collected.emit(hero.peer_id, kind)


func _check_end() -> void:
	var leader := -1
	if score[0] != score[1]:
		leader = 0 if score[0] > score[1] else 1
	if score[0] >= rules.score_limit or score[1] >= rules.score_limit:
		_end(leader)
	elif tick - phase_tick >= int(rules.time_limit * TICK_RATE):
		if leader == -1:
			overtime = true
		else:
			_end(leader)


func _end(winning_team: int) -> void:
	phase = Phase.ENDED
	phase_tick = tick
	winner = winning_team
	for hero: HeroState in heroes.values():
		_cancel_hook(hero)
		hero.moving = false
		hero.arrow_flying = false


func _bot_shop(hero: HeroState) -> void:
	var lowest: int = hero.upgrades.min()
	var options := []
	for i in hero.upgrades.size():
		if hero.upgrades[i] == lowest:
			options.append(i)
	try_buy(hero.peer_id, options.pick_random())


func _count(team: int, include_bots: bool) -> int:
	var count := 0
	for hero: HeroState in heroes.values():
		if hero.team == team and (include_bots or not hero.is_bot):
			count += 1
	return count


func _bots_in(team: int) -> Array:
	var found := []
	for hero: HeroState in heroes.values():
		if hero.team == team and hero.is_bot:
			found.append(hero)
	return found


func _team_for(is_bot: bool) -> int:
	var first := _count(0, is_bot)
	var second := _count(1, is_bot)
	if first != second:
		return 0 if first < second else 1
	return 0 if _count(0, true) <= _count(1, true) else 1
