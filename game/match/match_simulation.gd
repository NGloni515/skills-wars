class_name MatchSimulation
extends RefCounted

signal hero_killed(victim: int, killer: int)
signal roster_changed

enum Phase { PLAYING, ENDED }

const TICK_RATE := 60
const MAX_INPUT_BACKLOG := 8
const BOT_SHOPPING_INTERVAL := 2 * TICK_RATE

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
var _next_bot_id := -1


func _init(match_arena: Arena, match_rules: MatchRules) -> void:
	arena = match_arena
	rules = match_rules


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


func push_input(peer_id: int, seq: int, move: Vector2, fire: Vector2) -> void:
	var hero: HeroState = heroes.get(peer_id)
	if hero == null or seq <= hero.last_input_seq or hero.pending_inputs.has(seq):
		return
	hero.pending_inputs[seq] = [move.limit_length(1.0), fire]


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
	for peer_id: int in bots:
		var hero: HeroState = heroes[peer_id]
		var command: Array = bots[peer_id].decide(hero, heroes.values(), tick)
		push_input(peer_id, hero.last_input_seq + 1, command[0], command[1])
		if (tick + peer_id) % BOT_SHOPPING_INTERVAL == 0:
			_bot_shop(hero)
	for hero: HeroState in heroes.values():
		_consume_inputs(hero, delta)
	for hero: HeroState in heroes.values():
		_update_hook(hero, delta)
	for hero: HeroState in heroes.values():
		if hero.life == HeroState.Life.DEAD and tick - hero.life_tick >= int(rules.respawn_time * TICK_RATE):
			_respawn(hero)
		if tick % TICK_RATE == 0:
			hero.gold += rules.gold_per_second
	_check_end()


func restart() -> void:
	score = [0, 0]
	phase = Phase.PLAYING
	phase_tick = tick
	winner = -1
	overtime = false
	for hero: HeroState in heroes.values():
		_cancel_hook(hero)
		hero.gold = 0
		hero.upgrades = [0, 0, 0, 0]
		hero.cooldown_until = 0
		_respawn(hero)


static func apply_move(arena_geometry: Arena, hero: HeroState, move: Vector2, delta: float) -> void:
	hero.moving = move.length_squared() > 0.01 and hero.can_act()
	if not hero.moving:
		return
	hero.position = arena_geometry.move_circle(hero.position, move * hero.definition.move_speed * delta, hero.definition.radius)
	hero.facing = atan2(move.x, move.y)


func snapshot() -> Array:
	var rows := []
	for hero: HeroState in heroes.values():
		rows.append(hero.to_row())
	return [tick, rows, score[0], score[1], phase, ticks_left(), winner, overtime]


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
		if input[1] != Vector2.ZERO:
			_start_cast(hero, input[1])
		apply_move(arena, hero, input[0], delta)


func _discard_inputs(hero: HeroState) -> void:
	for seq: int in hero.pending_inputs:
		hero.last_input_seq = maxi(hero.last_input_seq, seq)
	hero.pending_inputs.clear()
	hero.last_move = Vector2.ZERO


func _start_cast(hero: HeroState, direction: Vector2) -> void:
	if not hero.can_act() or tick < hero.cooldown_until:
		return
	hero.hook_direction = direction.normalized()
	hero.facing = atan2(hero.hook_direction.x, hero.hook_direction.y)
	_set_action(hero, HeroState.Action.CASTING)


func _update_hook(hero: HeroState, delta: float) -> void:
	var skill := hero.definition.hook
	match hero.action:
		HeroState.Action.CASTING:
			if tick - hero.action_tick >= int(skill.release_time * TICK_RATE):
				hero.hook_origin = hero.position + hero.hook_direction * skill.origin_offset
				hero.hook_head = hero.hook_origin
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
			hero.hook_head = to
			if victim:
				_catch(hero, victim)
			elif blocked <= 1.0 or traveled >= hero.hook_range():
				_set_action(hero, HeroState.Action.HOOK_BACK)
		HeroState.Action.HOOK_BACK:
			var home := hero.position + hero.hook_direction * skill.origin_offset
			hero.hook_head = hero.hook_head.move_toward(home, hero.hook_return_speed() * delta)
			var target: HeroState = heroes.get(hero.hook_target)
			if target and target.caught_by == hero.peer_id:
				target.position = hero.hook_head
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


func _catch(hero: HeroState, victim: HeroState) -> void:
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
	hero.cooldown_until = tick + int(hero.hook_cooldown() * TICK_RATE)
	hero.hook_target = 0
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
	_set_action(hero, HeroState.Action.NONE)


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
