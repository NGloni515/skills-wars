class_name MatchController
extends Node

signal local_cast_started(direction: Vector2)
signal local_cast_canceled
signal local_arrow_started(direction: Vector2)
signal local_trap_started(target: Vector2)
signal score_changed(red: int, blue: int)
signal kill_reported(killer_name: String, killer_team: int, victim_name: String, victim_team: int)

const SNAPSHOT_EVERY := 2
const INPUT_REDUNDANCY := 3
const INTERP_DELAY_TICKS := 6.0
const SNAPSHOT_BUFFER := 40
const PING_INTERVAL_MSEC := 1000

@export var map: Node3D
@export var rules: MatchRules

var arena: Arena
var simulation: MatchSimulation
var local_id := 0
var local_hero: HeroState
var remote_heroes := {}
var powerups := {}
var roster := {}
var ping_ms := -1
var hook_aim := Vector2.ZERO
var cast_direction := Vector2.ZERO
var phase := MatchSimulation.Phase.PLAYING
var ticks_left := 0
var winner := -1
var overtime := false

var _seq := 0
var _unacked: Array = []
var _queued_arrow := Vector2.ZERO
var _queued_trap := Vector2.INF
var _queued_hook := Vector2.ZERO
var _hook_cancel_pending := false
var _cast_started_msec := -1
var _cast_launched := false
var _lock_until_seq := 0
var _snapshots: Array = []
var _latest_tick := -1
var _latest_tick_msec := 0
var _delayed: Array = []
var _ready_peers := {}
var _next_ping_msec := 0
var _autopilot: BotBrain
var _predicted_cooldown_end_msec := 0
var _predicted_arrow_cooldown_end_msec := 0
var _predicted_trap_cooldown_end_msec := 0


func _ready() -> void:
	arena = Arena.from_map(map)
	local_id = multiplayer.get_unique_id()
	if Net.autopilot:
		_autopilot = BotBrain.new(arena)
	if multiplayer.is_server():
		_start_server()
	else:
		_client_ready.rpc_id(1, 0, Net.player_name)


func cast_hook(direction: Vector2) -> void:
	if not can_fire():
		return
	_queued_hook = direction if direction != Vector2.ZERO else Vector2(sin(local_hero.facing), cos(local_hero.facing))


func cancel_hook() -> void:
	if is_winding_up():
		_hook_cancel_pending = true


func is_winding_up() -> bool:
	return _cast_started_msec >= 0 and not _cast_launched


func local_cast_progress() -> float:
	if not is_winding_up():
		return 0.0
	return clampf((Time.get_ticks_msec() - _cast_started_msec) / (local_hero.definition.hook.release_time * 1000.0), 0.0, 1.0)


func can_fire() -> bool:
	return local_hero != null and _lock_until_seq == 0 and local_hero.can_act() and phase == MatchSimulation.Phase.PLAYING and hook_cooldown_left() <= 0.0


func hook_cooldown_left() -> float:
	return 0.0 if local_hero == null else _cooldown_left(local_hero.cooldown_until, _predicted_cooldown_end_msec)


func queue_arrow(direction: Vector2) -> void:
	if not can_shoot_arrow():
		return
	_queued_arrow = direction if direction != Vector2.ZERO else Vector2(sin(local_hero.facing), cos(local_hero.facing))


func can_shoot_arrow() -> bool:
	return local_hero != null and _lock_until_seq == 0 and local_hero.can_act() and phase == MatchSimulation.Phase.PLAYING and arrow_cooldown_left() <= 0.0 and not local_hero.arrow_flying


func queue_trap(target: Vector2) -> void:
	if can_cast_trap():
		_queued_trap = target


func trap_target_for(drag: Vector2) -> Vector2:
	var target := local_hero.position + drag * local_hero.definition.trap.max_distance
	return target.clamp(arena.bounds.position, arena.bounds.end)


func can_cast_trap() -> bool:
	return local_hero != null and _lock_until_seq == 0 and local_hero.can_act() and phase == MatchSimulation.Phase.PLAYING and trap_cooldown_left() <= 0.0


func trap_cooldown_left() -> float:
	return 0.0 if local_hero == null else _cooldown_left(local_hero.trap_cooldown_until, _predicted_trap_cooldown_end_msec)


func interpolated_traps() -> Array[TrapState]:
	var result: Array[TrapState] = []
	if _snapshots.is_empty():
		return result
	for row: Array in _render_bracket()[1][9]:
		result.append(TrapState.new().apply_row(row))
	return result


func arrow_cooldown_left() -> float:
	return 0.0 if local_hero == null else _cooldown_left(local_hero.arrow_cooldown_until, _predicted_arrow_cooldown_end_msec)


func _cooldown_left(server_until_tick: int, predicted_end_msec: int) -> float:
	var from_server := (server_until_tick - estimated_tick()) / MatchSimulation.TICK_RATE
	var predicted := (predicted_end_msec - Time.get_ticks_msec()) / 1000.0
	return maxf(0.0, maxf(from_server, predicted))


func buy(upgrade: int) -> void:
	if simulation:
		simulation.try_buy(local_id, upgrade)
	else:
		_after_lag(func() -> void: _buy.rpc_id(1, upgrade))


func display_name(peer_id: int) -> String:
	return roster.get(peer_id, "Player")


func estimated_tick() -> float:
	return _latest_tick + (Time.get_ticks_msec() - _latest_tick_msec) * MatchSimulation.TICK_RATE / 1000.0


func interpolated_heroes() -> Array[HeroState]:
	var result: Array[HeroState] = []
	if _snapshots.is_empty():
		return result
	var bracket := _render_bracket()
	var older: Array = bracket[0]
	var newer: Array = bracket[1]
	var alpha: float = bracket[2]
	var older_rows := {}
	for row: Array in older[1]:
		older_rows[row[0]] = row
	for row: Array in newer[1]:
		var hero := HeroState.new().apply_row(row)
		var from := HeroState.new().apply_row(older_rows.get(row[0], row))
		hero.hook_head = from.hook_head.lerp(hero.hook_head, alpha)
		if from.arrow_flying:
			hero.arrow_position = from.arrow_position.lerp(hero.arrow_position, alpha)
		if hero.peer_id == local_id and local_hero:
			hero.position = local_hero.position
			hero.facing = local_hero.facing
			hero.moving = local_hero.moving
		else:
			hero.position = from.position.lerp(hero.position, alpha)
			hero.facing = lerp_angle(from.facing, hero.facing, alpha)
		result.append(hero)
	return result


func interpolated_powerups() -> Array[PowerUpState]:
	var result: Array[PowerUpState] = []
	if _snapshots.is_empty():
		return result
	var bracket := _render_bracket()
	var older_rows := {}
	for row: Array in bracket[0][8]:
		older_rows[row[0]] = row
	for row: Array in bracket[1][8]:
		var orb := PowerUpState.new().apply_row(row)
		var from := PowerUpState.new().apply_row(older_rows.get(row[0], row))
		orb.position = from.position.lerp(orb.position, bracket[2])
		result.append(orb)
	return result


func _render_bracket() -> Array:
	var render_tick := estimated_tick() - INTERP_DELAY_TICKS
	var older: Array = _snapshots[0]
	var newer: Array = older
	for i in range(_snapshots.size() - 1, -1, -1):
		if _snapshots[i][0] <= render_tick:
			older = _snapshots[i]
			newer = _snapshots[mini(i + 1, _snapshots.size() - 1)]
			break
	var span: int = newer[0] - older[0]
	var alpha := 0.0 if span == 0 else clampf((render_tick - older[0]) / span, 0.0, 1.0)
	return [older, newer, alpha]


func _start_server() -> void:
	simulation = MatchSimulation.new(arena, rules)
	simulation.fill_with_bots = Net.fill_bots
	simulation.hero_killed.connect(_on_hero_killed)
	simulation.hero_stunned.connect(func(victim: int, attacker: int) -> void: print("Stun: %s stunned %s" % [simulation.names.get(attacker, attacker), simulation.names.get(victim, victim)]))
	simulation.hero_trapped.connect(func(victim: int, owner: int) -> void: print("Trap: %s trapped %s" % [simulation.names.get(owner, owner), simulation.names.get(victim, victim)]))
	simulation.roster_changed.connect(_on_roster_changed)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if not Net.dedicated:
		simulation.add_player(local_id, HeroRoster.ALL[0], Net.player_name)
	if Net.fill_bots:
		simulation.balance_bots()
	else:
		for i in Net.bot_count:
			simulation.add_bot(HeroRoster.ALL[0])
	if not Net.room_code.is_empty():
		add_child(MatchHeartbeat.new(Net.backend_url, Net.room_code, OS.get_environment("MATCH_SECRET"), _room_stats))
	elif not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		var discovery := LanDiscovery.new()
		add_child(discovery)
		discovery.announce(_announcement)


func _announcement() -> Dictionary:
	var host_name := "Dedicated server" if Net.dedicated else "%s's game" % Net.player_name
	return {"name": host_name, "port": Net.port, "players": simulation.human_count()}


func _room_stats() -> Dictionary:
	var humans := simulation.human_count()
	return {"humans": humans, "bots": simulation.heroes.size() - humans}


func _physics_process(delta: float) -> void:
	_run_delayed()
	if local_hero and not Net.dedicated:
		_send_local_input(delta)
	if simulation:
		simulation.step()
		if simulation.tick % SNAPSHOT_EVERY == 0:
			var by_team := {}
			for peer: int in _ready_peers:
				var team := _team_of(peer)
				if not by_team.has(team):
					by_team[team] = SnapshotCodec.encode(simulation.snapshot(team))
				_receive_snapshot.rpc_id(peer, by_team[team])
			if not Net.dedicated:
				_accept_snapshot(simulation.snapshot(_team_of(local_id)))
	else:
		_update_ping()


func _team_of(peer_id: int) -> int:
	var hero: HeroState = simulation.heroes.get(peer_id)
	return hero.team if hero else -1


func _send_local_input(delta: float) -> void:
	_seq += 1
	var move := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var arrow := _queued_arrow
	var trap := _queued_trap
	_queued_trap = Vector2.INF
	var hook := _queued_hook
	var cancel := _hook_cancel_pending
	_queued_arrow = Vector2.ZERO
	_queued_hook = Vector2.ZERO
	_hook_cancel_pending = false
	if _autopilot:
		var command: Array = _autopilot.decide(local_hero, remote_heroes.values(), int(estimated_tick()), powerups.values())
		move = command[0]
		if command[1] & MatchSimulation.HOOK_CAST and hook == Vector2.ZERO and can_fire():
			hook = command[2]
		cancel = cancel or (command[1] & MatchSimulation.HOOK_CANCEL != 0 and is_winding_up())
		if arrow == Vector2.ZERO and can_shoot_arrow():
			arrow = command[3]
		if command[1] & MatchSimulation.TRAP_CAST and can_cast_trap():
			trap = command[4]
	if phase != MatchSimulation.Phase.PLAYING:
		move = Vector2.ZERO
		hook = Vector2.ZERO
		arrow = Vector2.ZERO
		trap = Vector2.INF
	if hook != Vector2.ZERO:
		arrow = Vector2.ZERO
		trap = Vector2.INF
		_lock_until_seq = _seq
		_cast_started_msec = Time.get_ticks_msec()
		_cast_launched = false
		cast_direction = hook
		local_hero.facing = atan2(hook.x, hook.y)
		local_cast_started.emit(hook)
	elif arrow != Vector2.ZERO:
		_lock_until_seq = _seq
		_predicted_arrow_cooldown_end_msec = Time.get_ticks_msec() + int(local_hero.definition.arrow.cooldown * 1000.0)
		local_hero.facing = atan2(arrow.x, arrow.y)
		local_arrow_started.emit(arrow)
		trap = Vector2.INF
	elif trap != Vector2.INF:
		_lock_until_seq = _seq
		_predicted_trap_cooldown_end_msec = Time.get_ticks_msec() + int(local_hero.trap_cooldown() * 1000.0)
		local_trap_started.emit(trap)
	if cancel:
		_cast_started_msec = -1
		local_cast_canceled.emit()
	_update_local_cast()
	if _lock_until_seq != 0:
		move = Vector2.ZERO
	var flags := (MatchSimulation.HOOK_CAST if hook != Vector2.ZERO else 0) | (MatchSimulation.HOOK_CANCEL if cancel else 0)
	var trap_target := Vector2.ZERO
	if trap != Vector2.INF:
		flags |= MatchSimulation.TRAP_CAST
		trap_target = trap
	_unacked.append([_seq, move, flags, hook, arrow, trap_target])
	MatchSimulation.apply_move(arena, local_hero, move, delta)
	if simulation:
		simulation.push_input(local_id, _seq, move, flags, hook, arrow, trap_target)
		return
	var packet := []
	for input: Array in _unacked.slice(-INPUT_REDUNDANCY):
		packet.append([input[0], input[1].x, input[1].y, input[2], input[3].x, input[3].y, input[4].x, input[4].y, input[5].x, input[5].y])
	_after_lag(func() -> void: _submit_inputs.rpc_id(1, packet))


func _update_local_cast() -> void:
	if not is_winding_up():
		return
	if Time.get_ticks_msec() - _cast_started_msec >= local_hero.definition.hook.release_time * 1000.0:
		_cast_launched = true
		_predicted_cooldown_end_msec = Time.get_ticks_msec() + int(local_hero.hook_cooldown() * 1000.0)


func _accept_snapshot(snap: Array) -> void:
	if snap[0] <= _latest_tick:
		return
	_latest_tick = snap[0]
	_latest_tick_msec = Time.get_ticks_msec()
	_snapshots.append(snap)
	if _snapshots.size() > SNAPSHOT_BUFFER:
		_snapshots.pop_front()
	score_changed.emit(snap[2], snap[3])
	phase = snap[4]
	ticks_left = snap[5]
	winner = snap[6]
	overtime = snap[7]
	powerups.clear()
	for row: Array in snap[8]:
		var orb := PowerUpState.new().apply_row(row)
		powerups[orb.id] = orb
	var seen := {}
	for row: Array in snap[1]:
		seen[row[0]] = true
		if row[0] == local_id:
			_reconcile(row)
		else:
			remote_heroes[row[0]] = (remote_heroes.get(row[0]) if remote_heroes.has(row[0]) else HeroState.new()).apply_row(row)
	for peer_id: int in remote_heroes.keys():
		if not seen.has(peer_id):
			remote_heroes.erase(peer_id)


func _reconcile(row: Array) -> void:
	var predicted_facing := local_hero.facing if local_hero else 0.0
	local_hero = (local_hero if local_hero else HeroState.new()).apply_row(row)
	var acknowledged := local_hero.last_input_seq
	while not _unacked.is_empty() and _unacked[0][0] <= acknowledged:
		_unacked.pop_front()
	if _lock_until_seq != 0 and acknowledged >= _lock_until_seq and local_hero.action == HeroState.Action.NONE:
		_lock_until_seq = 0
		if local_hero.cooldown_until <= _latest_tick:
			_predicted_cooldown_end_msec = 0
		if local_hero.arrow_cooldown_until <= _latest_tick:
			_predicted_arrow_cooldown_end_msec = 0
		if local_hero.trap_cooldown_until <= _latest_tick:
			_predicted_trap_cooldown_end_msec = 0
		if is_winding_up():
			_cast_started_msec = -1
			local_cast_canceled.emit()
	if _lock_until_seq != 0 or not _unacked.is_empty():
		local_hero.facing = predicted_facing
	for input: Array in _unacked:
		MatchSimulation.apply_move(arena, local_hero, input[1], 1.0 / MatchSimulation.TICK_RATE)


func _on_hero_killed(victim: int, killer: int) -> void:
	print("Kill: %s hooked %s" % [simulation.names.get(killer, killer), simulation.names.get(victim, victim)])
	var event := [killer, simulation.heroes[killer].team, victim, simulation.heroes[victim].team]
	for peer: int in _ready_peers:
		_receive_kill.rpc_id(peer, event)
	if not Net.dedicated:
		_report_kill(event)


func _on_roster_changed() -> void:
	roster = simulation.names.duplicate()
	for peer: int in _ready_peers:
		_receive_roster.rpc_id(peer, roster)


func _report_kill(event: Array) -> void:
	kill_reported.emit(display_name(event[0]), event[1], display_name(event[2]), event[3])


func _after_lag(callback: Callable) -> void:
	if Net.simulated_lag_ms <= 0 or simulation:
		callback.call()
		return
	_delayed.append([Time.get_ticks_msec() + Net.simulated_lag_ms / 2, callback])


func _run_delayed() -> void:
	var now := Time.get_ticks_msec()
	while not _delayed.is_empty() and _delayed[0][0] <= now:
		_delayed.pop_front()[1].call()


func _update_ping() -> void:
	var now := Time.get_ticks_msec()
	if now < _next_ping_msec or multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return
	_next_ping_msec = now + PING_INTERVAL_MSEC
	_after_lag(func() -> void: _ping.rpc_id(1, now))


func _on_peer_disconnected(peer_id: int) -> void:
	_ready_peers.erase(peer_id)
	simulation.remove_hero(peer_id)
	print("Peer %d left" % peer_id)


@rpc("any_peer", "call_remote", "reliable")
func _client_ready(hero_index: int, requested_name: String) -> void:
	var peer_id := multiplayer.get_remote_sender_id()
	if simulation == null or simulation.heroes.has(peer_id):
		return
	_ready_peers[peer_id] = true
	var definition := HeroRoster.ALL[clampi(hero_index, 0, HeroRoster.ALL.size() - 1)]
	var hero := simulation.add_player(peer_id, definition, Net.clean_name(requested_name))
	print("%s (peer %d) joined team %d" % [simulation.names[peer_id], peer_id, hero.team])


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _submit_inputs(packet: Array) -> void:
	if simulation == null:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	for input: Array in packet:
		if input.size() < 10:
			continue
		simulation.push_input(peer_id, input[0], Vector2(input[1], input[2]), int(input[3]), Vector2(input[4], input[5]), Vector2(input[6], input[7]), Vector2(input[8], input[9]))


@rpc("any_peer", "call_remote", "reliable")
func _buy(upgrade: int) -> void:
	if simulation:
		simulation.try_buy(multiplayer.get_remote_sender_id(), upgrade)


@rpc("authority", "call_remote", "unreliable_ordered", 2)
func _receive_snapshot(packet: PackedByteArray) -> void:
	_after_lag(_accept_snapshot.bind(SnapshotCodec.decode(packet)))


@rpc("authority", "call_remote", "reliable")
func _receive_roster(names: Dictionary) -> void:
	roster = names


@rpc("authority", "call_remote", "reliable")
func _receive_kill(event: Array) -> void:
	_after_lag(_report_kill.bind(event))


@rpc("any_peer", "call_remote", "unreliable", 3)
func _ping(sent_msec: int) -> void:
	_pong.rpc_id(multiplayer.get_remote_sender_id(), sent_msec)


@rpc("authority", "call_remote", "unreliable", 3)
func _pong(sent_msec: int) -> void:
	_after_lag(func() -> void: ping_ms = Time.get_ticks_msec() - sent_msec)
