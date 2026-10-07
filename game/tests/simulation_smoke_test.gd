extends SceneTree

const SECONDS := 240

var _map: Node3D
var _failures: Array[String] = []
var _checks_finished := 0


func _initialize() -> void:
	_map = load("res://maps/river_arena/river_arena.tscn").instantiate()
	root.add_child(_map)


func _process(_delta: float) -> bool:
	var arena := Arena.from_map(_map)
	_check_geometry(arena)
	_check_bot_filling(arena)
	_check_full_matches(arena)
	_check_shield_and_powerup(arena)
	_check_reach_and_cooldown(arena)
	_check_ally_pull(arena)
	_check_stun_arrow(arena)
	_check_hesi(arena)
	_check_trap(arena)
	_check_snapshot_codec(arena)
	_check_name_filter()
	_check_arrow_through_rocks(arena)
	_check_upgrades(arena)
	_expect(_checks_finished == 13, "only %d of 13 checks ran to the end" % _checks_finished)
	for failure in _failures:
		print("  FAILED: " + failure)
	print("SMOKE TEST " + ("PASSED" if _failures.is_empty() else "FAILED"))
	quit(0 if _failures.is_empty() else 1)
	return true


func _check_arrow_through_rocks(arena: Arena) -> void:
	var rock := arena.hook_blockers[0]
	var center := Vector2(rock.x, rock.y)
	var from := center + Vector2(-(rock.z + 3.0), 0.0)
	var to := center + Vector2(rock.z + 3.0, 0.0)
	_expect(arena.first_hook_blocker_hit(from, to, 0.4) <= 1.0, "the test line should cross a rock")
	var simulation := MatchSimulation.new(arena, MatchRules.new())
	var shooter := simulation.add_player(1, HeroRoster.ALL[0], "Shooter")
	var enemy := simulation.add_player(2, HeroRoster.ALL[0], "Enemy")
	shooter.position = from
	enemy.position = to
	simulation.push_input(1, 1, Vector2.ZERO, 0, Vector2.ZERO, Vector2.RIGHT)
	_run(simulation, 2 * MatchSimulation.TICK_RATE)
	_expect(enemy.stunned, "the arrow should fly through rocks and stun the enemy behind one")
	var hook_simulation := MatchSimulation.new(arena, MatchRules.new())
	var hooker := hook_simulation.add_player(1, HeroRoster.ALL[0], "Hooker")
	var target := hook_simulation.add_player(2, HeroRoster.ALL[0], "Target")
	_expect(hooker.team != target.team, "the hook test needs two teams")
	hooker.position = from
	target.position = to
	_throw_hook(hook_simulation, hooker, Vector2.RIGHT, 2.0)
	_expect(target.life == HeroState.Life.ALIVE, "hooks should still be stopped by rocks")
	_checks_finished += 1


func _check_upgrades(arena: Arena) -> void:
	var rules := MatchRules.new()
	var simulation := MatchSimulation.new(arena, rules)
	var hero := simulation.add_player(1, HeroRoster.ALL[0], "Buyer")
	var definition := hero.definition
	var costs := rules.upgrade_costs
	_expect(Upgrades.quick_buy_target(hero.upgrades, costs, -1) == Upgrades.Kind.HOOK_RANGE, "quick buy should start with hook range")
	_expect(Upgrades.quick_buy_target(hero.upgrades, costs, Upgrades.Kind.ARROW_STUN) == Upgrades.Kind.ARROW_STUN, "quick buy should follow the starred upgrade")
	_expect(not simulation.try_buy(1, Upgrades.Kind.TRAP_SIZE), "buying without gold should fail")
	hero.gold = 100000
	for kind in Upgrades.COUNT:
		for level in costs.size():
			_expect(simulation.try_buy(1, kind), "buying %s level %d should work" % [Upgrades.FULL_NAMES[kind], level + 1])
		_expect(not simulation.try_buy(1, kind), "%s should stop at level %d" % [Upgrades.FULL_NAMES[kind], costs.size()])
	_expect(is_equal_approx(hero.stun_time(), definition.arrow.stun_time + 5 * definition.arrow.stun_time_per_level), "stun time should grow with upgrades")
	_expect(is_equal_approx(hero.arrow_speed(), definition.arrow.speed + 5 * definition.arrow.speed_per_level), "arrow speed should grow with upgrades")
	_expect(is_equal_approx(hero.trap_radius(), definition.trap.radius + 5 * definition.trap.radius_per_level), "trap size should grow with upgrades")
	_expect(hero.trap_cooldown() < definition.trap.cooldown, "trap cooldown should shrink with upgrades")
	_expect(Upgrades.quick_buy_target(hero.upgrades, costs, Upgrades.Kind.ARROW_STUN) == -1, "quick buy should stop when everything is maxed")
	var copy := HeroState.new().apply_row(hero.to_row())
	_expect(copy.upgrades == hero.upgrades, "all 8 upgrade levels should survive a snapshot")
	_checks_finished += 1


func _check_name_filter() -> void:
	for blocked in ["FuCk", "f u c k", "fuuuck", "sh1t", "B!tch", "xXpussyXx", "Hijo de puta", "HijoDePuta", "BigAss",
			"PENDEJO", "p3nd3j0", "Cabrón", "ass", "Mr Dick", "nazi", "kys"]:
		_expect(not NameFilter.is_allowed(blocked), "the name filter should block %s" % blocked)
	for allowed in ["Gaff", "Ángel", "Cassandra", "Dickens", "Hancock", "Peacock", "Computadora", "Sexto", "Grape",
			"Therapist", "Ignazio", "Concha", "Classic", "Bass Pro", "Matías", "Player 7", "xX_Ninja_Xx"]:
		_expect(NameFilter.is_allowed(allowed), "the name filter should allow %s" % allowed)
	_checks_finished += 1


func _check_snapshot_codec(arena: Arena) -> void:
	var simulation := MatchSimulation.new(arena, MatchRules.new())
	simulation.fill_with_bots = true
	simulation.balance_bots()
	var largest := 0
	var mismatches := 0
	var saw_traps := false
	for i in 40 * MatchSimulation.TICK_RATE:
		simulation.step()
		if i % 15 != 0:
			continue
		var snapshot := simulation.snapshot()
		var bytes := SnapshotCodec.encode(snapshot)
		largest = maxi(largest, bytes.size())
		saw_traps = saw_traps or not snapshot[9].is_empty()
		if not _same_values(SnapshotCodec.decode(bytes), snapshot):
			mismatches += 1
	print("largest snapshot=%d bytes" % largest)
	_expect(mismatches == 0, "%d snapshots changed after encoding" % mismatches)
	_expect(saw_traps, "the codec check should cover traps")
	_expect(largest < 1000, "snapshots should fit one packet, largest was %d bytes" % largest)
	_checks_finished += 1


func _same_values(a: Variant, b: Variant) -> bool:
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not _same_values(a[i], b[i]):
				return false
		return true
	if a is float or b is float:
		return absf(float(a) - float(b)) < 0.001
	return a == b


func _check_geometry(arena: Arena) -> void:
	_expect(arena.hero_walls.size() == 6, "expected 6 hero walls, got %d" % arena.hero_walls.size())
	_expect(arena.hook_blockers.size() == 8, "expected 8 rocks, got %d" % arena.hook_blockers.size())
	_expect(arena.spawns[0].size() == 3 and arena.spawns[1].size() == 3, "expected 3 spawns per team")
	_expect(arena.play_area.size.is_equal_approx(Vector2(28.8, 24.0)), "the play area should be 28.8 x 24 m, got %s" % arena.play_area.size)
	_expect(is_equal_approx(arena.river_edge, 2.45), "each bank should start 2.45 m from the river's center, got %.2f" % arena.river_edge)
	_checks_finished += 1


func _check_bot_filling(arena: Arena) -> void:
	var simulation := MatchSimulation.new(arena, MatchRules.new())
	simulation.fill_with_bots = true
	simulation.add_player(1, HeroRoster.ALL[0], "Human")
	_expect(simulation.heroes.size() == 6, "one human should be joined by 5 bots, got %d heroes" % simulation.heroes.size())
	simulation.add_player(2, HeroRoster.ALL[0], "Friend")
	_expect(simulation.heroes.size() == 6 and simulation.human_count() == 2, "a second human should replace a bot")
	_expect(simulation.heroes[1].team != simulation.heroes[2].team, "two humans should land on different teams")
	simulation.remove_hero(2)
	_expect(simulation.heroes.size() == 6 and simulation.human_count() == 1, "a bot should take the leaving human's slot")
	_checks_finished += 1


func _check_full_matches(arena: Arena) -> void:
	var rules := MatchRules.new()
	rules.score_limit = 6
	rules.restart_delay = 1.0
	var simulation := MatchSimulation.new(arena, rules)
	simulation.fill_with_bots = true
	simulation.balance_bots()
	var kills := [0]
	simulation.hero_killed.connect(func(_victim: int, _killer: int) -> void: kills[0] += 1)
	var matches_ended := 0
	var upgrades_bought := 0
	var powerups_collected := [0]
	simulation.powerup_collected.connect(func(_peer: int, _kind: PowerUpState.Kind) -> void: powerups_collected[0] += 1)
	var crossed_river := 0
	var previous_phase := simulation.phase
	for i in SECONDS * MatchSimulation.TICK_RATE:
		simulation.step()
		if simulation.phase == MatchSimulation.Phase.ENDED and previous_phase == MatchSimulation.Phase.PLAYING:
			matches_ended += 1
			_expect(simulation.winner != -1 and simulation.score.max() == rules.score_limit, "match should end with a winner at the score limit")
		previous_phase = simulation.phase
		for hero: HeroState in simulation.heroes.values():
			upgrades_bought = maxi(upgrades_bought, hero.upgrades.reduce(func(sum: int, level: int) -> int: return sum + level, 0))
			if hero.life == HeroState.Life.ALIVE and signf(hero.position.x) != (-1.0 if hero.team == 0 else 1.0):
				crossed_river += 1
	print("kills=%d matches_ended=%d most_upgrades=%d powerups=%d score=%s" % [kills[0], matches_ended, upgrades_bought, powerups_collected[0], simulation.score])
	_expect(powerups_collected[0] > 0, "bots should collect power-ups")
	_expect(kills[0] > 0, "bots should score kills")
	_expect(matches_ended >= 1, "at least one match should end")
	_expect(upgrades_bought > 0, "bots should buy upgrades")
	_expect(crossed_river == 0, "no living hero should ever stand on the enemy bank")
	_checks_finished += 1


func _check_shield_and_powerup(arena: Arena) -> void:
	var rules := MatchRules.new()
	var simulation := MatchSimulation.new(arena, rules)
	var blocks := [0]
	var collected := []
	simulation.shield_blocked.connect(func(_victim: int, _attacker: int) -> void: blocks[0] += 1)
	simulation.powerup_collected.connect(func(_peer: int, kind: PowerUpState.Kind) -> void: collected.append(kind))
	var thrower := simulation.add_player(1, HeroRoster.ALL[0], "Thrower")
	var target := simulation.add_player(2, HeroRoster.ALL[0], "Target")
	thrower.position = Vector2(-5, 0)
	target.position = Vector2(5, 0)
	target.shield_until = 100000
	_throw_hook(simulation, thrower, Vector2.RIGHT, thrower.hook_cooldown() + 1.0)
	_expect(blocks[0] == 1, "a shield should block exactly one hook, blocked %d" % blocks[0])
	_expect(target.life == HeroState.Life.ALIVE and not target.shielded, "the shielded target should survive and lose its shield")
	var orb := PowerUpState.new()
	orb.id = 999
	orb.kind = PowerUpState.Kind.GOLD
	orb.position = Vector2(0, 0)
	simulation.powerups[orb.id] = orb
	var gold_before := thrower.gold
	_throw_hook(simulation, thrower, Vector2.RIGHT, 2.0)
	_expect(collected == [PowerUpState.Kind.GOLD], "hooking the gold orb should collect it, collected %s" % [collected])
	_expect(thrower.gold - gold_before >= rules.gold_bag, "the gold bag should pay out")
	_expect(not simulation.powerups.has(999), "a collected orb should leave the river")
	_checks_finished += 1


func _check_reach_and_cooldown(arena: Arena) -> void:
	var simulation := MatchSimulation.new(arena, MatchRules.new())
	var thrower := simulation.add_player(1, HeroRoster.ALL[0], "Front")
	var target := simulation.add_player(2, HeroRoster.ALL[0], "Back")
	var radius := thrower.definition.radius
	thrower.position = Vector2(-(arena.river_edge + radius), 0.0)
	target.position = Vector2(arena.play_area.end.x - radius, 0.0)
	_throw_hook(simulation, thrower, Vector2.RIGHT, 3.0)
	_expect(simulation.score[thrower.team] == 1, "a hook from the river edge (x=%.1f) should reach an enemy at the far wall (x=%.1f)" % [thrower.hook_origin.x - 0.7, target.position.x])
	var casts := 0
	for second in 12:
		casts += _throw_hook(simulation, thrower, Vector2.UP, 1.0)
	_expect(casts == 1, "with a %.0f s cooldown only one throw should happen in 12 s, got %d" % [thrower.hook_cooldown(), casts])
	_checks_finished += 1


func _check_ally_pull(arena: Arena) -> void:
	var simulation := MatchSimulation.new(arena, MatchRules.new())
	var puller := simulation.add_player(1, HeroRoster.ALL[0], "Puller")
	simulation.add_player(2, HeroRoster.ALL[0], "Enemy").position = Vector2(12, 12)
	var ally := simulation.add_player(3, HeroRoster.ALL[0], "Ally")
	_expect(ally.team == puller.team, "player 3 should join the puller's team")
	puller.position = Vector2(-14, 0)
	ally.position = Vector2(-7, 0)
	var was_caught := [false]
	_throw_hook(simulation, puller, Vector2.RIGHT, 3.0, -1.0, func() -> void: was_caught[0] = was_caught[0] or ally.life == HeroState.Life.CAUGHT)
	_expect(was_caught[0], "hooking an ally should catch them")
	_expect(ally.life == HeroState.Life.ALIVE, "a pulled ally should stay alive")
	_expect(simulation.score == [0, 0], "pulling an ally should not score")
	_expect(ally.position.distance_to(puller.position) < 2.5, "the ally should end up next to the puller")
	_checks_finished += 1


func _check_stun_arrow(arena: Arena) -> void:
	var simulation := MatchSimulation.new(arena, MatchRules.new())
	var stuns := [0]
	simulation.hero_stunned.connect(func(_victim: int, _attacker: int) -> void: stuns[0] += 1)
	var shooter := simulation.add_player(1, HeroRoster.ALL[0], "Shooter")
	var enemy := simulation.add_player(2, HeroRoster.ALL[0], "Enemy")
	var ally := simulation.add_player(3, HeroRoster.ALL[0], "Ally")
	shooter.position = Vector2(arena.play_area.position.x + 0.6, 0.0)
	ally.position = Vector2(-(arena.river_edge + 4.0), 0.0)
	enemy.position = Vector2(arena.play_area.end.x - 0.6, 0.0)
	simulation.push_input(1, 1, Vector2.ZERO, 0, Vector2.ZERO, Vector2.RIGHT)
	var hit_tick := -1
	for i in 4 * MatchSimulation.TICK_RATE:
		simulation.step()
		if enemy.stunned:
			hit_tick = simulation.tick
			break
	_expect(stuns[0] == 1 and hit_tick > 0, "the arrow should cross the whole map (%.1f m) and stun the enemy" % shooter.position.distance_to(enemy.position))
	_expect(not ally.stunned, "the arrow should pass through allies")
	var stuck_at := enemy.position
	simulation.push_input(2, 1, Vector2.LEFT, MatchSimulation.HOOK_CAST, Vector2.LEFT)
	var stun_ticks := 0
	while enemy.stunned and stun_ticks < 10 * MatchSimulation.TICK_RATE:
		simulation.push_input(2, enemy.last_input_seq + 1, Vector2.LEFT)
		simulation.step()
		stun_ticks += 1
	var stun_seconds := (simulation.tick - hit_tick) / float(MatchSimulation.TICK_RATE)
	_expect(absf(stun_seconds - shooter.stun_time()) < 0.1, "stun should last %.1f s, lasted %.2f s" % [shooter.stun_time(), stun_seconds])
	_expect(enemy.action == HeroState.Action.NONE, "a stunned hero should not be able to throw")
	_expect(enemy.position.distance_to(stuck_at) < 0.2, "a stunned hero should not move")
	simulation.push_input(1, shooter.last_input_seq + 1, Vector2.ZERO, 0, Vector2.ZERO, Vector2.RIGHT)
	simulation.step()
	_expect(shooter.action != HeroState.Action.ARROW_CAST, "the arrow should be on its %.0f s cooldown" % shooter.definition.arrow.cooldown)
	for i in int(shooter.definition.arrow.cooldown * MatchSimulation.TICK_RATE):
		simulation.push_input(1, shooter.last_input_seq + 1, Vector2.ZERO)
		simulation.step()
	simulation.push_input(1, shooter.last_input_seq + 1, Vector2.ZERO, 0, Vector2.ZERO, Vector2.RIGHT)
	simulation.step()
	_expect(shooter.action == HeroState.Action.ARROW_CAST, "the arrow should be ready again after its cooldown")
	_checks_finished += 1


func _check_hesi(arena: Arena) -> void:
	var simulation := MatchSimulation.new(arena, MatchRules.new())
	var feints := [0]
	simulation.hook_feinted.connect(func(_peer: int) -> void: feints[0] += 1)
	var thrower := simulation.add_player(1, HeroRoster.ALL[0], "Faker")
	var target := simulation.add_player(2, HeroRoster.ALL[0], "Target")
	thrower.position = Vector2(-5, 0)
	target.position = Vector2(5, 0)
	thrower.big_hook_ready = true
	var launched := [false]
	var moved_while_casting := [0.0]
	var stood_at := thrower.position
	var watch := func() -> void:
		launched[0] = launched[0] or thrower.hook_visible()
		if thrower.action == HeroState.Action.CASTING:
			moved_while_casting[0] = maxf(moved_while_casting[0], thrower.position.distance_to(stood_at))
	_throw_hook(simulation, thrower, Vector2.RIGHT, 1.0, 0.4, watch, Vector2.UP)
	_expect(feints[0] == 1 and not launched[0], "tapping HOOK again 0.4 s into the cast should cancel it (hesi)")
	_expect(moved_while_casting[0] < 0.05, "a hero should not move while casting the hook")
	_expect(thrower.position.distance_to(stood_at) > 1.0, "a hero should walk again right after cancelling")
	thrower.position = stood_at
	_expect(simulation.tick >= thrower.cooldown_until, "a hesi should leave the cooldown ready")
	_expect(thrower.big_hook_ready, "a hesi should keep a Big Hook for the next real throw")
	_expect(target.life == HeroState.Life.ALIVE, "a hesi should not catch anyone")
	var press_tick := simulation.tick + 1
	var launch_tick := [-1]
	_throw_hook(simulation, thrower, Vector2.RIGHT, 2.0, -1.0, func() -> void:
		if launch_tick[0] < 0 and thrower.hook_visible():
			launch_tick[0] = simulation.tick
	)
	var cast_seconds: float = (launch_tick[0] - press_tick) / float(MatchSimulation.TICK_RATE)
	_expect(launch_tick[0] > 0 and absf(cast_seconds - thrower.definition.hook.release_time) < 0.05, "the hook should launch %.1f s after the cast starts, launched after %.2f s" % [thrower.definition.hook.release_time, cast_seconds])
	_expect(simulation.score[thrower.team] == 1, "the real throw right after a hesi should catch the target")
	_expect(thrower.cooldown_until - launch_tick[0] == int(thrower.hook_cooldown() * MatchSimulation.TICK_RATE), "the cooldown should start when the hook launches")
	_checks_finished += 1


func _check_trap(arena: Arena) -> void:
	var simulation := MatchSimulation.new(arena, MatchRules.new())
	var trapped := []
	simulation.hero_trapped.connect(func(victim: int, _owner: int) -> void: trapped.append(victim))
	var caster := simulation.add_player(1, HeroRoster.ALL[0], "Trapper")
	var enemy := simulation.add_player(2, HeroRoster.ALL[0], "Target")
	var ally := simulation.add_player(3, HeroRoster.ALL[0], "Ally")
	var escaper := simulation.add_player(4, HeroRoster.ALL[0], "Escaper")
	_expect(ally.team == caster.team and escaper.team == enemy.team, "the trap test needs an ally and two enemies")
	var skill := caster.definition.trap
	caster.position = Vector2(-12, 0)
	ally.position = Vector2(-10, 6)
	enemy.position = Vector2(8, 0)
	escaper.position = Vector2(8, 1.0)
	simulation.push_input(1, 1, Vector2.ZERO, MatchSimulation.TRAP_CAST, Vector2.ZERO, Vector2.ZERO, Vector2(8, 0.5))
	simulation.step()
	var cast_tick := simulation.tick
	_expect(caster.action == HeroState.Action.TRAP_CAST, "the trap should start with a visible casting animation")
	_expect(simulation.traps.is_empty(), "the trap should not exist before the cast finishes")
	_run(simulation, int(skill.cast_time * MatchSimulation.TICK_RATE))
	_expect(simulation.traps.size() == 1, "the trap should be armed when the cast finishes")
	_expect(_trap_rows(simulation, caster.team) == 1 and _trap_rows(simulation, enemy.team) == 0, "only the caster's team should receive the armed trap")
	for i in int(skill.delay * MatchSimulation.TICK_RATE) - 2:
		simulation.push_input(4, escaper.last_input_seq + 1, Vector2(0, 1))
		simulation.step()
	_expect(trapped.is_empty(), "nobody should be trapped before the delay ends")
	_run(simulation, 4)
	_expect(trapped == [2], "the enemy in the circle should be trapped, and the one who walked away should escape (trapped %s)" % [trapped])
	_expect(_trap_rows(simulation, enemy.team) == 1, "enemies should see the trap once it has sprung")
	_expect(simulation.tick - cast_tick <= int((skill.cast_time + skill.delay) * MatchSimulation.TICK_RATE) + 4, "the trap should spring %.1f s after the cast ends" % skill.delay)
	var stuck_at := enemy.position
	_run(simulation, MatchSimulation.TICK_RATE, Vector2(-1, 0), 2)
	_expect(enemy.position.distance_to(stuck_at) < 0.05, "a trapped hero should not move")
	simulation.push_input(2, enemy.last_input_seq + 1, Vector2.ZERO, MatchSimulation.HOOK_CAST, Vector2.LEFT)
	simulation.step()
	_expect(enemy.action == HeroState.Action.CASTING, "a trapped hero should still be able to throw")
	_run(simulation, int(skill.root_time * MatchSimulation.TICK_RATE), Vector2(-1, 0), 2)
	_expect(not enemy.rooted, "the root should wear off after %.1f s" % skill.root_time)
	_run(simulation, 2 * MatchSimulation.TICK_RATE, Vector2(-1, 0), 2)
	_expect(enemy.position.distance_to(stuck_at) > 0.5, "a freed hero should walk again once their hook is back")
	_expect(caster.trap_cooldown_until - cast_tick == int(skill.cooldown * MatchSimulation.TICK_RATE), "the trap cooldown should be %.0f s" % skill.cooldown)
	caster.trap_cooldown_until = 0
	simulation.push_input(1, caster.last_input_seq + 1, Vector2.ZERO, MatchSimulation.TRAP_CAST, Vector2.ZERO, Vector2.ZERO, ally.position)
	_run(simulation, int((skill.cast_time + skill.delay) * MatchSimulation.TICK_RATE) + 4)
	_expect(not ally.rooted and trapped.size() == 1, "a trap should never catch allies")
	_checks_finished += 1


func _run(simulation: MatchSimulation, ticks: int, move := Vector2.ZERO, mover := 0) -> void:
	for i in ticks:
		if mover != 0:
			simulation.push_input(mover, simulation.heroes[mover].last_input_seq + 1, move)
		simulation.step()


func _trap_rows(simulation: MatchSimulation, viewer_team: int) -> int:
	return simulation.snapshot(viewer_team)[9].size()


func _throw_hook(simulation: MatchSimulation, hero: HeroState, aim: Vector2, total_seconds: float, cancel_after := -1.0, each_tick := Callable(), move := Vector2.ZERO) -> int:
	var casts := 0
	var cancel_tick := int(cancel_after * MatchSimulation.TICK_RATE) if cancel_after >= 0.0 else -1
	for i in int(total_seconds * MatchSimulation.TICK_RATE):
		var flags := MatchSimulation.HOOK_CAST if i == 0 else (MatchSimulation.HOOK_CANCEL if i == cancel_tick else 0)
		simulation.push_input(hero.peer_id, hero.last_input_seq + 1, move, flags, aim if i == 0 else Vector2.ZERO)
		simulation.step()
		if hero.action == HeroState.Action.CASTING and hero.action_tick == simulation.tick:
			casts += 1
		if each_tick.is_valid():
			each_tick.call()
	return casts


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
