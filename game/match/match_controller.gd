class_name MatchController
extends Node

signal local_cast_started(direction: Vector2)
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
var roster := {}
var ping_ms := -1
var phase := MatchSimulation.Phase.PLAYING
var ticks_left := 0
var winner := -1
var overtime := false

var _seq := 0
var _unacked: Array = []
var _queued_fire := Vector2.ZERO
var _lock_until_seq := 0
var _snapshots: Array = []
var _latest_tick := -1
var _latest_tick_msec := 0
var _delayed: Array = []
var _ready_peers := {}
var _next_ping_msec := 0
var _autopilot: BotBrain


func _ready() -> void:
	arena = Arena.from_map(map)
	local_id = multiplayer.get_unique_id()
	if Net.autopilot:
		_autopilot = BotBrain.new()
	if multiplayer.is_server():
		_start_server()
	else:
		_client_ready.rpc_id(1, 0, Net.player_name)


func queue_fire(direction: Vector2) -> void:
	if not can_fire():
		return
	_queued_fire = direction if direction != Vector2.ZERO else Vector2(sin(local_hero.facing), cos(local_hero.facing))


func can_fire() -> bool:
	return local_hero != null and _lock_until_seq == 0 and local_hero.can_act() and phase == MatchSimulation.Phase.PLAYING


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
	var older_rows := {}
	for row: Array in older[1]:
		older_rows[row[0]] = row
	for row: Array in newer[1]:
		var hero := HeroState.new().apply_row(row)
		if hero.peer_id == local_id and local_hero:
			hero.position = local_hero.position
			hero.facing = local_hero.facing
			hero.moving = local_hero.moving
		else:
			var from := HeroState.new().apply_row(older_rows.get(row[0], row))
			hero.position = from.position.lerp(hero.position, alpha)
			hero.facing = lerp_angle(from.facing, hero.facing, alpha)
			hero.hook_head = from.hook_head.lerp(hero.hook_head, alpha)
		result.append(hero)
	return result


func _start_server() -> void:
	simulation = MatchSimulation.new(arena, rules)
	simulation.fill_with_bots = Net.fill_bots
	simulation.hero_killed.connect(_on_hero_killed)
	simulation.roster_changed.connect(_on_roster_changed)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if not Net.dedicated:
		simulation.add_player(local_id, HeroRoster.ALL[0], Net.player_name)
	if Net.fill_bots:
		simulation.balance_bots()
	else:
		for i in Net.bot_count:
			simulation.add_bot(HeroRoster.ALL[0])
	if not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		var discovery := LanDiscovery.new()
		add_child(discovery)
		discovery.announce(_announcement)


func _announcement() -> Dictionary:
	var host_name := "Dedicated server" if Net.dedicated else "%s's game" % Net.player_name
	return {"name": host_name, "port": Net.port, "players": simulation.human_count()}


func _physics_process(delta: float) -> void:
	_run_delayed()
	if local_hero and not Net.dedicated:
		_send_local_input(delta)
	if simulation:
		simulation.step()
		if simulation.tick % SNAPSHOT_EVERY == 0:
			var snap := simulation.snapshot()
			for peer: int in _ready_peers:
				_receive_snapshot.rpc_id(peer, snap)
			if not Net.dedicated:
				_accept_snapshot(snap)
	else:
		_update_ping()


func _send_local_input(delta: float) -> void:
	_seq += 1
	var move := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var fire := _queued_fire
	_queued_fire = Vector2.ZERO
	if _autopilot:
		var command: Array = _autopilot.decide(local_hero, remote_heroes.values(), int(estimated_tick()))
		move = command[0]
		if fire == Vector2.ZERO and can_fire():
			fire = command[1]
	if phase != MatchSimulation.Phase.PLAYING:
		move = Vector2.ZERO
		fire = Vector2.ZERO
	if fire != Vector2.ZERO:
		_lock_until_seq = _seq
		local_hero.facing = atan2(fire.x, fire.y)
		local_cast_started.emit(fire)
	if _lock_until_seq != 0:
		move = Vector2.ZERO
	_unacked.append([_seq, move, fire])
	MatchSimulation.apply_move(arena, local_hero, move, delta)
	if simulation:
		simulation.push_input(local_id, _seq, move, fire)
		return
	var packet := []
	for input: Array in _unacked.slice(-INPUT_REDUNDANCY):
		packet.append([input[0], input[1].x, input[1].y, input[2].x, input[2].y])
	_after_lag(func() -> void: _submit_inputs.rpc_id(1, packet))


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
		simulation.push_input(peer_id, input[0], Vector2(input[1], input[2]), Vector2(input[3], input[4]))


@rpc("any_peer", "call_remote", "reliable")
func _buy(upgrade: int) -> void:
	if simulation:
		simulation.try_buy(multiplayer.get_remote_sender_id(), upgrade)


@rpc("authority", "call_remote", "unreliable_ordered", 2)
func _receive_snapshot(snap: Array) -> void:
	_after_lag(_accept_snapshot.bind(snap))


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
