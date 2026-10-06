class_name MatchView
extends Node3D

signal impact(strength: float)

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

@export var match_controller: MatchController
@export var aim_button: AimButton
@export var aim_line: MeshInstance3D

var _presenters := {}
var _predicted_cast_msec := -100000
var _catches_this_frame: Array[Vector2] = []
var _hook_stops: Array[HeroState] = []


class Presenter:
	var visual: HeroVisual
	var skill_visual: HookChain
	var name_tag: Label3D
	var dust: GPUParticles3D
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
	aim_line.top_level = true
	aim_line.visible = false
	Fx.warm_up(self)


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
			_presenters.erase(peer_id)
	_resolve_hook_stops()
	_update_aim_line()


func _create_presenter(hero: HeroState) -> Presenter:
	var presenter := Presenter.new()
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
	return presenter


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
	if is_local and aim_button.is_aiming() and match_controller.can_fire():
		var aim := aim_button.aim_direction()
		facing = atan2(aim.x, aim.y)
	visual.rotation.y = lerp_angle(visual.rotation.y, facing, 1.0 - exp(-TURN_SMOOTHING * delta))
	presenter.name_tag.text = match_controller.display_name(hero.peer_id)
	presenter.name_tag.visible = hero.life == HeroState.Life.ALIVE
	presenter.dust.emitting = hero.moving and hero.life == HeroState.Life.ALIVE
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
	if idle_allowed and not recently_cast and Time.get_ticks_msec() - presenter.spawned_msec > SPAWN_ANIMATION_MSEC:
		visual.play(&"run" if hero.moving else &"idle")
	visual.set_hook_in_hand(hero.action == HeroState.Action.NONE or hero.action == HeroState.Action.CASTING)
	_update_skill_visual(presenter, hero)
	_update_water(presenter, hero)


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
	var chest := at + Vector3.UP * CHEST_HEIGHT
	Fx.burst(self, chest, &"impact")
	Fx.shockwave(self, chest, Color(1.0, 0.95, 0.7), 1.3, 0.3)
	Sfx.play_at(self, &"hit_thwack", at)
	var local := match_controller.local_hero
	var latest_victim: HeroState = match_controller.remote_heroes.get(victim.peer_id)
	var local_caught_it := local != null and latest_victim != null and local.hook_visible() and latest_victim.position.distance_to(local.hook_head) < 0.6
	if victim.peer_id == match_controller.local_id:
		impact.emit(1.0)
	elif local_caught_it:
		impact.emit(0.7)
		if victim.team != local.team:
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
		presenter.visual.rotation.y = atan2(direction.x, direction.y)


func _update_aim_line() -> void:
	var presenter: Presenter = _presenters.get(match_controller.local_id)
	var show := presenter != null and aim_button.is_aiming() and match_controller.can_fire()
	aim_line.visible = show
	if not show:
		return
	var aim := aim_button.aim_direction()
	var direction := Vector3(aim.x, 0.0, aim.y)
	var length := match_controller.local_hero.hook_range()
	var basis := Basis.looking_at(direction)
	basis.z *= length
	aim_line.global_transform = Transform3D(basis, presenter.visual.position + direction * length * 0.5 + Vector3.UP * 0.05)
