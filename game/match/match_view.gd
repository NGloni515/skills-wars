class_name MatchView
extends Node3D

signal impact(strength: float)
signal powerup_collected(kind: PowerUpState.Kind, is_local: bool)

const TEAM_COLORS: Array[Color] = [Color(0.86, 0.24, 0.2), Color(0.22, 0.45, 0.92)]
const TAG_COLORS: Array[Color] = [Color(1.0, 0.62, 0.57), Color(0.62, 0.78, 1.0)]
const LOCAL_SMOOTHING := 20.0
const TURN_SMOOTHING := 18.0
const SNAP_DISTANCE := 2.5
const SPAWN_ANIMATION_MSEC := 600
const PREDICTED_CAST_GRACE_MSEC := 500
const NAME_TAG_HEIGHT := 2.75
const CHEST_HEIGHT := 1.2
const RIPPLE_INTERVAL_MSEC := 140
const ROCK_HIT_MARGIN := 0.4
const CATCH_MATCH_DISTANCE := 1.8
const SHIELD_COLOR := Color(0.45, 0.85, 1.0, 0.9)
const BUBBLE_SHADER := preload("res://fx/bubble.gdshader")
const STUN_COLOR := Color(0.6, 0.95, 1.0)
const DIZZY_HEIGHT := 2.35
const ARROW_STUN_MATCH_DISTANCE := 2.0

@export var match_controller: MatchController
@export var aim_button: AimButton
@export var aim_line: MeshInstance3D
@export var arrow_button: AimButton
@export var arrow_aim_line: MeshInstance3D
@export var trap_button: AimButton

var _presenters := {}
var _orbs := {}
var _traps := {}
var _trap_marker: MeshInstance3D
var _predicted_cast_msec := -100000
var _predicted_arrow_msec := -100000
var _catches_this_frame: Array[Vector2] = []
var _hook_stops: Array[HeroState] = []
var _stuns_this_frame: Array[Vector2] = []
var _arrow_ends: Array[Vector3] = []


class Presenter:
	var visual: HeroVisual
	var skill_visual: HookChain
	var name_tag: Label3D
	var dust: GPUParticles3D
	var shield_bubble: MeshInstance3D
	var haste_trail: GPUParticles3D
	var hook_glow: GPUParticles3D
	var arrow_visual: ArrowVisual
	var dizzy: DizzyStars
	var root_trap: TrapVisual
	var team := 0
	var shielded := false
	var stunned := false
	var arrow_flying := false
	var last_arrow_point := Vector3.ZERO
	var life := HeroState.Life.ALIVE
	var life_tick := -1
	var action := HeroState.Action.NONE
	var action_tick := -1
	var spawned_msec := -100000
	var placed := false
	var in_water := false
	var next_ripple_msec := 0


func _ready() -> void:
	match_controller.local_cast_started.connect(_on_local_cast_started)
	match_controller.local_arrow_started.connect(_on_local_arrow_started)
	match_controller.local_cast_canceled.connect(_on_local_cast_canceled)
	match_controller.local_trap_started.connect(_on_local_trap_started)
	_trap_marker = Fx.ground_ring(Color(1.0, 0.85, 0.3, 0.9), 1.0)
	_trap_marker.top_level = true
	_trap_marker.visible = false
	add_child(_trap_marker)
	for line in [aim_line, arrow_aim_line]:
		line.top_level = true
		line.visible = false
	Fx.warm_up(self)
	_warm_up_materials()


func _exit_tree() -> void:
	Fx.release()


func local_position() -> Vector3:
	var presenter: Presenter = _presenters.get(match_controller.local_id)
	return presenter.visual.global_position if presenter else Vector3.ZERO


func local_team() -> int:
	return match_controller.local_hero.team if match_controller.local_hero else 0


func _process(delta: float) -> void:
	_catches_this_frame.clear()
	_hook_stops.clear()
	_stuns_this_frame.clear()
	_arrow_ends.clear()
	var seen := {}
	for hero in match_controller.interpolated_heroes():
		seen[hero.peer_id] = true
		var presenter: Presenter = _presenters.get(hero.peer_id)
		if presenter == null:
			presenter = _create_presenter(hero)
			_presenters[hero.peer_id] = presenter
		_update_presenter(presenter, hero, delta)
	for peer_id: int in _presenters.keys():
		if not seen.has(peer_id):
			var presenter: Presenter = _presenters[peer_id]
			presenter.visual.queue_free()
			presenter.skill_visual.queue_free()
			presenter.arrow_visual.queue_free()
			_presenters.erase(peer_id)
	_resolve_hook_stops()
	_resolve_arrow_ends()
	_update_orbs()
	_update_traps()
	_update_aim_line()


func _create_presenter(hero: HeroState) -> Presenter:
	var presenter := Presenter.new()
	presenter.team = hero.team
	presenter.visual = hero.definition.visual_scene.instantiate()
	presenter.visual.team_color = TEAM_COLORS[hero.team]
	add_child(presenter.visual)
	presenter.skill_visual = hero.definition.skill_visual_scene.instantiate()
	add_child(presenter.skill_visual)
	presenter.name_tag = Label3D.new()
	presenter.name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	presenter.name_tag.no_depth_test = true
	presenter.name_tag.fixed_size = true
	presenter.name_tag.pixel_size = 0.0011
	presenter.name_tag.font_size = 30
	presenter.name_tag.outline_size = 10
	presenter.name_tag.outline_modulate = Color(0.05, 0.05, 0.1)
	presenter.name_tag.modulate = Color.WHITE if hero.peer_id == match_controller.local_id else TAG_COLORS[hero.team]
	presenter.name_tag.position.y = NAME_TAG_HEIGHT
	presenter.visual.add_child(presenter.name_tag)
	presenter.dust = Fx.emitter(&"dust")
	presenter.dust.emitting = false
	presenter.visual.add_child(presenter.dust)
	presenter.dust.position = Vector3(0.0, 0.1, -0.2)
	presenter.shield_bubble = _make_bubble()
	presenter.visual.add_child(presenter.shield_bubble)
	presenter.haste_trail = Fx.emitter(&"trail")
	presenter.haste_trail.emitting = false
	presenter.visual.add_child(presenter.haste_trail)
	presenter.haste_trail.position = Vector3(0.0, 0.6, 0.0)
	presenter.hook_glow = Fx.emitter(&"glow")
	presenter.hook_glow.emitting = false
	presenter.visual.hand_anchor().add_child(presenter.hook_glow)
	presenter.arrow_visual = ArrowVisual.new()
	add_child(presenter.arrow_visual)
	presenter.dizzy = DizzyStars.new()
	presenter.visual.add_child(presenter.dizzy)
	presenter.dizzy.position.y = DIZZY_HEIGHT
	presenter.root_trap = TrapVisual.new()
	presenter.root_trap.setup(0.0, Color.WHITE, 1.15)
	presenter.root_trap.spring(false)
	presenter.root_trap.visible = false
	presenter.visual.add_child(presenter.root_trap)
	return presenter


func _warm_up_materials() -> void:
	var probes: Array[Node3D] = [_make_bubble(), PowerUpVisual.new()]
	probes[1].setup(PowerUpState.Kind.SHIELD)
	for probe in probes:
		probe.visible = true
		add_child(probe)
		probe.position = Vector3(0.0, -50.0, 0.0)
		get_tree().create_timer(0.5).timeout.connect(probe.queue_free)


func _make_bubble() -> MeshInstance3D:
	var bubble := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.2
	sphere.height = 2.6
	bubble.mesh = sphere
	var material := ShaderMaterial.new()
	material.shader = BUBBLE_SHADER
	material.set_shader_parameter("color", SHIELD_COLOR)
	bubble.material_override = material
	bubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bubble.position.y = 1.15
	bubble.visible = false
	return bubble


func _update_presenter(presenter: Presenter, hero: HeroState, delta: float) -> void:
	var visual := presenter.visual
	var target := Vector3(hero.position.x, 0.0, hero.position.y)
	var is_local := hero.peer_id == match_controller.local_id
	var first_update := not presenter.placed
	if first_update or not is_local or visual.position.distance_to(target) > SNAP_DISTANCE:
		visual.position = target
		presenter.placed = true
	else:
		visual.position = visual.position.lerp(target, 1.0 - exp(-LOCAL_SMOOTHING * delta))
	var facing := hero.facing
	if is_local and match_controller.is_winding_up() and match_controller.hook_aim != Vector2.ZERO:
		var aim := match_controller.hook_aim
		facing = atan2(aim.x, aim.y)
	elif is_local and arrow_button.is_aiming() and match_controller.can_shoot_arrow():
		var aim := arrow_button.aim_direction()
		facing = atan2(aim.x, aim.y)
	visual.rotation.y = lerp_angle(visual.rotation.y, facing, 1.0 - exp(-TURN_SMOOTHING * delta))
	presenter.name_tag.text = match_controller.display_name(hero.peer_id)
	presenter.name_tag.visible = hero.life == HeroState.Life.ALIVE
	presenter.dust.emitting = hero.moving and hero.life == HeroState.Life.ALIVE
	_update_status_effects(presenter, hero)
	_update_stun(presenter, hero, is_local)
	_update_arrow(presenter, hero)
	if hero.life != presenter.life or hero.life_tick != presenter.life_tick:
		_on_life_changed(presenter, hero, presenter.life, first_update)
		presenter.life = hero.life
		presenter.life_tick = hero.life_tick
	if hero.action != presenter.action or hero.action_tick != presenter.action_tick:
		_on_action_changed(presenter, hero, presenter.action, is_local)
		presenter.action = hero.action
		presenter.action_tick = hero.action_tick
	var recently_cast := is_local and Time.get_ticks_msec() - _predicted_cast_msec < PREDICTED_CAST_GRACE_MSEC
	var idle_allowed := hero.life == HeroState.Life.ALIVE and hero.action == HeroState.Action.NONE
	if idle_allowed and hero.stunned:
		visual.play(&"stunned")
	elif idle_allowed and not recently_cast and Time.get_ticks_msec() - presenter.spawned_msec > SPAWN_ANIMATION_MSEC:
		visual.play(&"run" if hero.moving else &"idle")
	visual.set_hook_in_hand(hero.action == HeroState.Action.NONE or hero.action == HeroState.Action.CASTING)
	_update_skill_visual(presenter, hero)
	_update_water(presenter, hero)


func _update_stun(presenter: Presenter, hero: HeroState, is_local: bool) -> void:
	var alive := hero.life == HeroState.Life.ALIVE
	if hero.stunned and not presenter.stunned and alive:
		var head := presenter.visual.global_position + Vector3.UP * 2.0
		Fx.burst(self, head, &"impact", STUN_COLOR)
		Fx.shockwave(self, head, STUN_COLOR, 1.2, 0.3)
		Sfx.play_at(self, &"stun_hit", head)
		_stuns_this_frame.append(hero.position)
		impact.emit(0.8 if is_local else 0.15)
	presenter.stunned = hero.stunned
	presenter.dizzy.visible = hero.stunned and alive
	presenter.root_trap.visible = hero.rooted and alive


func _update_arrow(presenter: Presenter, hero: HeroState) -> void:
	if hero.arrow_flying:
		var point := Vector3(hero.arrow_position.x, hero.definition.arrow.height, hero.arrow_position.y)
		if not presenter.arrow_flying:
			Sfx.play_at(self, &"arrow_shot", point)
		presenter.arrow_visual.show_at(point, Vector3(hero.arrow_direction.x, 0.0, hero.arrow_direction.y))
		presenter.last_arrow_point = point
	elif presenter.arrow_flying:
		presenter.arrow_visual.hide_arrow()
		_arrow_ends.append(presenter.last_arrow_point)
	presenter.arrow_flying = hero.arrow_flying


func _resolve_arrow_ends() -> void:
	var inside := match_controller.arena.bounds.grow(-0.5)
	for point in _arrow_ends:
		var flat := Vector2(point.x, point.z)
		var stunned_someone := false
		for stunned in _stuns_this_frame:
			if stunned.distance_to(flat) < ARROW_STUN_MATCH_DISTANCE:
				stunned_someone = true
		if not stunned_someone and inside.has_point(flat):
			Fx.burst(self, point, &"sparks", STUN_COLOR)
			Sfx.play_at(self, &"hook_clank", point, -6.0)


func _update_status_effects(presenter: Presenter, hero: HeroState) -> void:
	var alive := hero.life == HeroState.Life.ALIVE
	if presenter.shielded and not hero.shielded and alive:
		var at := presenter.shield_bubble.global_position
		Fx.burst(self, at, &"splash", SHIELD_COLOR)
		Fx.shockwave(self, at, SHIELD_COLOR, 1.6, 0.35)
		Sfx.play_at(self, &"shield_pop", at)
	presenter.shielded = hero.shielded
	presenter.shield_bubble.visible = hero.shielded and alive
	presenter.haste_trail.emitting = alive and hero.moving and hero.speed_multiplier > 1.01
	presenter.hook_glow.emitting = alive and hero.big_hook_ready
	presenter.skill_visual.set_big(hero.hook_is_big)


func _update_orbs() -> void:
	var water_level: float = match_controller.map.get("water_level") if "water_level" in match_controller.map else 0.0
	var seen := {}
	for orb in match_controller.interpolated_powerups():
		seen[orb.id] = true
		var entry: Array = _orbs.get(orb.id, [])
		if entry.is_empty():
			var visual := PowerUpVisual.new()
			add_child(visual)
			visual.water_level = water_level
			visual.setup(orb.kind)
			entry = [visual, 0]
			_orbs[orb.id] = entry
		entry[0].place(orb.position, orb.carried_by != 0)
		entry[1] = orb.carried_by
	for id: int in _orbs.keys():
		if seen.has(id):
			continue
		var visual: PowerUpVisual = _orbs[id][0]
		var collector: int = _orbs[id][1]
		if collector != 0 and _presenters.has(collector):
			_on_powerup_collected(visual.kind, collector)
		visual.queue_free()
		_orbs.erase(id)


func _on_powerup_collected(kind: PowerUpState.Kind, collector: int) -> void:
	var presenter: Presenter = _presenters[collector]
	var at := presenter.visual.global_position
	var color := PowerUpState.COLORS[kind]
	Fx.burst(self, at + Vector3.UP * 1.2, &"impact", color)
	Fx.shockwave(self, at + Vector3.UP * 0.05, color, 1.5)
	Sfx.play_at(self, &"powerup", at, -2.0)
	var is_local := collector == match_controller.local_id
	var label := "+%d" % match_controller.rules.gold_bag if kind == PowerUpState.Kind.GOLD else PowerUpState.NAMES[kind] + "!"
	Fx.floating_text(self, at + Vector3.UP * 2.4, label, color.lerp(Color.WHITE, 0.3))
	powerup_collected.emit(kind, is_local)


func _on_life_changed(presenter: Presenter, hero: HeroState, previous: HeroState.Life, first_update: bool) -> void:
	var visual := presenter.visual
	var at := visual.global_position
	match hero.life:
		HeroState.Life.CAUGHT:
			visual.restart(&"dragged")
			if not first_update:
				_on_caught(hero, at)
		HeroState.Life.DEAD:
			visual.restart(&"death")
			if not first_update:
				Fx.burst(self, at + Vector3.UP * 0.6, &"poof")
				Sfx.play_at(self, &"poof", at)
		HeroState.Life.ALIVE:
			if previous == HeroState.Life.DEAD:
				visual.restart(&"spawn")
				presenter.spawned_msec = Time.get_ticks_msec()
				Fx.burst(self, at + Vector3.UP * 0.1, &"sparkles", TAG_COLORS[hero.team])
				Fx.shockwave(self, at + Vector3.UP * 0.05, TAG_COLORS[hero.team], 1.4)
				Sfx.play_at(self, &"spawn", at, -4.0)
			elif previous == HeroState.Life.CAUGHT:
				Fx.shockwave(self, at + Vector3.UP * 0.05, TAG_COLORS[hero.team], 1.0)


func _on_caught(victim: HeroState, at: Vector3) -> void:
	_catches_this_frame.append(victim.position)
	var catcher: Presenter = _presenters.get(victim.caught_by)
	if catcher and catcher.team == victim.team:
		Fx.shockwave(self, at + Vector3.UP * 0.05, TAG_COLORS[victim.team], 1.3)
		Sfx.play_at(self, &"chain_rattle", at)
		return
	var chest := at + Vector3.UP * CHEST_HEIGHT
	Fx.burst(self, chest, &"impact")
	Fx.shockwave(self, chest, Color(1.0, 0.95, 0.7), 1.3, 0.3)
	Sfx.play_at(self, &"hit_thwack", at)
	if victim.peer_id == match_controller.local_id:
		impact.emit(1.0)
	elif victim.caught_by == match_controller.local_id:
		impact.emit(0.7)
		Sfx.play(self, &"kill_ding", -6.0)
		Fx.floating_text(self, local_position() + Vector3.UP * 2.2, "+%d" % match_controller.rules.gold_per_kill, Color(1.0, 0.85, 0.3))
	else:
		impact.emit(0.25)


func _on_action_changed(presenter: Presenter, hero: HeroState, previous: HeroState.Action, is_local: bool) -> void:
	var at := presenter.visual.global_position
	match hero.action:
		HeroState.Action.CASTING:
			if not (is_local and Time.get_ticks_msec() - _predicted_cast_msec < PREDICTED_CAST_GRACE_MSEC):
				presenter.visual.restart(&"hook_cast")
		HeroState.Action.HOOK_OUT:
			Sfx.play_at(self, &"hook_throw", at)
			Sfx.play_at(self, &"chain_rattle", at, -6.0)
		HeroState.Action.HOOK_BACK:
			presenter.visual.play(&"reel")
			if previous == HeroState.Action.HOOK_OUT:
				_hook_stops.append(hero)
		HeroState.Action.ARROW_CAST:
			if not (is_local and Time.get_ticks_msec() - _predicted_arrow_msec < PREDICTED_CAST_GRACE_MSEC):
				presenter.visual.restart(&"throw")
		HeroState.Action.TRAP_CAST:
			if not (is_local and Time.get_ticks_msec() - _predicted_arrow_msec < PREDICTED_CAST_GRACE_MSEC):
				presenter.visual.restart(&"trap_cast")
			Fx.shockwave(self, at + Vector3.UP * 0.05, TAG_COLORS[presenter.team], 1.2, hero.definition.trap.cast_time)
			Fx.burst(self, at + Vector3.UP * 1.0, &"sparkles", TAG_COLORS[presenter.team])
			Sfx.play_at(self, &"trap_set", at)


func _resolve_hook_stops() -> void:
	for hero in _hook_stops:
		var near_catch := false
		for caught in _catches_this_frame:
			if caught.distance_to(hero.hook_head) < CATCH_MATCH_DISTANCE:
				near_catch = true
		var origin := hero.position + hero.hook_direction * hero.definition.hook.origin_offset
		var stopped_early := origin.distance_to(hero.hook_head) < hero.hook_range() - ROCK_HIT_MARGIN
		if near_catch or not stopped_early:
			continue
		var head := Vector3(hero.hook_head.x, hero.definition.hook.height, hero.hook_head.y)
		var back := Vector3(-hero.hook_direction.x, 0.4, -hero.hook_direction.y).normalized()
		Fx.burst(self, head, &"sparks", Color.WHITE, back)
		Sfx.play_at(self, &"hook_clank", head)


func _update_water(presenter: Presenter, hero: HeroState) -> void:
	var map := match_controller.map
	var in_water: bool = hero.life == HeroState.Life.CAUGHT and map.has_method("is_water") and map.call("is_water", hero.position)
	var at := presenter.visual.global_position
	var surface := Vector3(at.x, map.get("water_level") if "water_level" in map else 0.0, at.z)
	var now := Time.get_ticks_msec()
	if in_water != presenter.in_water:
		Fx.burst(self, surface, &"splash")
		Fx.shockwave(self, surface + Vector3.UP * 0.02, Color(0.9, 1.0, 1.0, 0.8), 1.2, 0.5)
		Sfx.play_at(self, &"splash", surface, -3.0)
		presenter.in_water = in_water
	elif in_water and now >= presenter.next_ripple_msec:
		presenter.next_ripple_msec = now + RIPPLE_INTERVAL_MSEC
		Fx.shockwave(self, surface + Vector3.UP * 0.02, Color(0.9, 1.0, 1.0, 0.6), 0.7, 0.6)


func _update_skill_visual(presenter: Presenter, hero: HeroState) -> void:
	if hero.life != HeroState.Life.ALIVE or not hero.hook_visible():
		presenter.skill_visual.hide_chain()
		return
	var head := Vector3(hero.hook_head.x, hero.definition.hook.height, hero.hook_head.y)
	var direction := Vector3(hero.hook_direction.x, 0.0, hero.hook_direction.y)
	presenter.skill_visual.show_chain(presenter.visual.chain_origin(), head, direction)


func _on_local_cast_started(direction: Vector2) -> void:
	_predicted_cast_msec = Time.get_ticks_msec()
	var presenter: Presenter = _presenters.get(match_controller.local_id)
	if presenter:
		presenter.visual.restart(&"hook_cast")
		if direction != Vector2.ZERO:
			presenter.visual.rotation.y = atan2(direction.x, direction.y)


func _on_local_cast_canceled() -> void:
	_predicted_cast_msec = -100000
	var presenter: Presenter = _presenters.get(match_controller.local_id)
	if presenter:
		presenter.visual.play(&"idle", 0.1)


func _on_local_arrow_started(direction: Vector2) -> void:
	_predicted_arrow_msec = Time.get_ticks_msec()
	var presenter: Presenter = _presenters.get(match_controller.local_id)
	if presenter:
		presenter.visual.restart(&"throw")
		presenter.visual.rotation.y = atan2(direction.x, direction.y)


func _update_traps() -> void:
	var now_tick := match_controller.estimated_tick()
	var seen := {}
	for trap in match_controller.interpolated_traps():
		seen[trap.id] = true
		var visual: TrapVisual = _traps.get(trap.id)
		if visual == null:
			visual = TrapVisual.new()
			add_child(visual)
			visual.setup(trap.radius, TAG_COLORS[trap.team], 1.3)
			visual.position = Vector3(trap.position.x, 0.02, trap.position.y)
			visual.total_ticks = maxf(1.0, trap.trigger_tick - now_tick)
			_traps[trap.id] = visual
		if trap.sprung and not visual.sprung:
			visual.spring()
			_on_trap_sprung(trap)
		elif not trap.sprung:
			visual.show_countdown(trap.trigger_tick - now_tick)
	for id: int in _traps.keys():
		if not seen.has(id):
			_traps[id].vanish()
			_traps.erase(id)


func _on_trap_sprung(trap: TrapState) -> void:
	var at := Vector3(trap.position.x, 0.1, trap.position.y)
	Fx.burst(self, at, &"poof", Color(0.85, 0.78, 0.62))
	Fx.burst(self, at + Vector3.UP * 0.4, &"sparks")
	Fx.shockwave(self, at, Color(1.0, 0.9, 0.7), trap.radius * 1.2, 0.35)
	Sfx.play_at(self, &"trap_snap", at)
	var local := match_controller.local_hero
	if local and local.position.distance_to(trap.position) <= trap.radius * 1.5:
		impact.emit(0.6 if local.team != trap.team else 0.2)


func _on_local_trap_started(_target: Vector2) -> void:
	_predicted_arrow_msec = Time.get_ticks_msec()
	var presenter: Presenter = _presenters.get(match_controller.local_id)
	if presenter:
		presenter.visual.restart(&"trap_cast")


func _update_aim_line() -> void:
	var trap_aiming := trap_button.is_aiming() and match_controller.can_cast_trap()
	_trap_marker.visible = trap_aiming
	if trap_aiming:
		var target := match_controller.trap_target_for(trap_button.aim_vector())
		_trap_marker.global_position = Vector3(target.x, 0.06, target.y)
		_trap_marker.scale = Vector3.ONE * match_controller.local_hero.definition.trap.radius * 2.5
	var presenter: Presenter = _presenters.get(match_controller.local_id)
	var hook_aiming := presenter != null and match_controller.is_winding_up()
	var arrow_aiming := presenter != null and arrow_button.is_aiming() and match_controller.can_shoot_arrow()
	aim_line.visible = hook_aiming
	arrow_aim_line.visible = arrow_aiming
	if hook_aiming:
		var hook_aim := match_controller.hook_aim
		if hook_aim == Vector2.ZERO:
			hook_aim = Vector2(sin(presenter.visual.rotation.y), cos(presenter.visual.rotation.y))
		_place_aim_line(aim_line, presenter, hook_aim, match_controller.local_hero.hook_range())
	if arrow_aiming:
		var aim := arrow_button.aim_direction()
		_place_aim_line(arrow_aim_line, presenter, aim, _distance_to_bounds(match_controller.local_hero.position, aim))


func _place_aim_line(line: MeshInstance3D, presenter: Presenter, aim: Vector2, length: float) -> void:
	var direction := Vector3(aim.x, 0.0, aim.y)
	var basis := Basis.looking_at(direction)
	basis.z *= length
	line.global_transform = Transform3D(basis, presenter.visual.position + direction * length * 0.5 + Vector3.UP * 0.05)


func _distance_to_bounds(from: Vector2, direction: Vector2) -> float:
	var bounds := match_controller.arena.bounds
	var distance := INF
	if absf(direction.x) > 0.001:
		distance = minf(distance, ((bounds.end.x if direction.x > 0.0 else bounds.position.x) - from.x) / direction.x)
	if absf(direction.y) > 0.001:
		distance = minf(distance, ((bounds.end.y if direction.y > 0.0 else bounds.position.y) - from.y) / direction.y)
	return clampf(distance, 1.0, 60.0)
