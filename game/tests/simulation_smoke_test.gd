extends SceneTree

const SECONDS := 150

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
	_expect(_checks_finished == 3, "only %d of 3 checks ran to the end" % _checks_finished)
	for failure in _failures:
		print("  FAILED: " + failure)
	print("SMOKE TEST " + ("PASSED" if _failures.is_empty() else "FAILED"))
	quit(0 if _failures.is_empty() else 1)
	return true


func _check_geometry(arena: Arena) -> void:
	_expect(arena.hero_walls.size() == 6, "expected 6 hero walls, got %d" % arena.hero_walls.size())
	_expect(arena.hook_blockers.size() == 8, "expected 8 rocks, got %d" % arena.hook_blockers.size())
	_expect(arena.spawns[0].size() == 3 and arena.spawns[1].size() == 3, "expected 3 spawns per team")
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
	rules.score_limit = 8
	rules.restart_delay = 1.0
	var simulation := MatchSimulation.new(arena, rules)
	simulation.fill_with_bots = true
	simulation.balance_bots()
	var kills := [0]
	simulation.hero_killed.connect(func(_victim: int, _killer: int) -> void: kills[0] += 1)
	var matches_ended := 0
	var upgrades_bought := 0
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
	print("kills=%d matches_ended=%d most_upgrades=%d score=%s" % [kills[0], matches_ended, upgrades_bought, simulation.score])
	_expect(kills[0] > 0, "bots should score kills")
	_expect(matches_ended >= 1, "at least one match should end")
	_expect(upgrades_bought > 0, "bots should buy upgrades")
	_expect(crossed_river == 0, "no living hero should ever stand on the enemy bank")
	_checks_finished += 1


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
