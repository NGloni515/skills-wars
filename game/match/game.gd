extends Node3D

const CAMERA_OFFSET := Vector3(0.0, 13.0, 9.1)
# The camera leads toward the enemy bank so everything inside hook range is on screen.
const CAMERA_LEAD_OF_RANGE := 0.42
const CAMERA_FOLLOW_SPEED := 6.0
const SHAKE_DECAY := 2.2
const SHAKE_MAX_OFFSET := 0.45
const VIBRATION_MSEC := [[0.9, 90], [0.6, 45]]
const PULSE_SPEED := 6.0
const PULSE_SCALE := 0.08
const PULSE_TINT := Color(1.35, 1.2, 0.7)

@onready var _match: MatchController = $Match
@onready var _view: MatchView = $View
@onready var _camera: Camera3D = $Camera3D
@onready var _score: RichTextLabel = $HUD/Score
@onready var _clock: Label = $HUD/Clock
@onready var _status: Label = $HUD/Status
@onready var _gold: Label = $HUD/Gold
@onready var _hook_button: AimButton = $HUD/HookButton
@onready var _arrow_button: AimButton = $HUD/ArrowButton
@onready var _trap_button: AimButton = $HUD/TrapButton
@onready var _shop: ShopPanel = $HUD/ShopPanel
@onready var _shop_button: Button = $HUD/Shop
@onready var _quick_buy: Button = $HUD/QuickBuy
@onready var _end_banner: Control = $HUD/EndBanner

var _camera_placed := false
var _shake := 0.0
var _shake_time := 0.0
var _last_levels: Array[int] = []
var _reported_ready := false
var _last_phase := MatchSimulation.Phase.PLAYING


func _ready() -> void:
	if Net.dedicated:
		_view.queue_free()
		$HUD.queue_free()
		_camera.queue_free()
		set_process(false)
		return
	_hook_button.fired.connect(_match.cast_hook)
	_hook_button.cancel_tapped.connect(_match.cancel_hook)
	_arrow_button.fired.connect(_match.queue_arrow)
	_trap_button.fired_vector.connect(func(drag: Vector2) -> void: _match.queue_trap(_match.trap_target_for(drag)))
	_match.score_changed.connect(_on_score_changed)
	_match.kill_reported.connect($HUD/KillFeed.add_kill)
	$HUD/Leave.pressed.connect(Net.leave)
	_shop_button.pressed.connect(_shop.toggle)
	_quick_buy.pressed.connect(_on_quick_buy)
	$HUD/Settings.pressed.connect($HUD/SettingsPanel.show)
	_shop.buy_requested.connect(_match.buy)
	_view.impact.connect(_on_impact)
	_view.powerup_collected.connect(func(_kind: PowerUpState.Kind, is_local: bool) -> void:
		if is_local:
			Settings.vibrate(25)
	)
	for button: BaseButton in find_children("*", "BaseButton", true, false):
		button.pressed.connect(Sfx.play.bind(self, &"ui_click", -8.0))
	_on_score_changed(0, 0)


func _process(delta: float) -> void:
	var hero := _match.local_hero
	if hero == null:
		return
	if not _reported_ready:
		_reported_ready = true
		Loading.scene_ready()
	_follow_camera(delta)
	_update_shake(delta)
	_play_progress_sounds(hero)
	_status.text = _status_text()
	_clock.text = _clock_text()
	_gold.text = "%d gold" % hero.gold
	_hook_button.cooldown_total = hero.hook_cooldown()
	_hook_button.cooldown_left = _match.hook_cooldown_left()
	_hook_button.cast_progress = _match.local_cast_progress()
	_hook_button.cancel_mode = _match.is_winding_up()
	_match.hook_aim = _hook_button.aim_direction() if _hook_button.is_aiming() and _match.can_fire() else Vector2.ZERO
	_arrow_button.cooldown_total = hero.definition.arrow.cooldown
	_arrow_button.cooldown_left = _match.arrow_cooldown_left()
	_trap_button.cooldown_total = hero.trap_cooldown()
	_trap_button.cooldown_left = _match.trap_cooldown_left()
	$HUD/Effects/Shield.visible = hero.shielded
	$HUD/Effects/Haste.visible = hero.speed_multiplier > 1.01
	$HUD/Effects/BigHook.visible = hero.big_hook_ready
	var playing := _match.phase == MatchSimulation.Phase.PLAYING
	if _shop.visible:
		_shop.refresh(hero.definition, hero.gold, hero.upgrades, _match.rules.upgrade_costs, playing)
	_update_shop_buttons(hero, playing)
	$HUD/KillFeed.visible = not _shop.visible
	_update_end_banner(hero.team)


func _follow_camera(delta: float) -> void:
	var side := 1.0 if _view.local_team() == 0 else -1.0
	var target := _view.local_position() + Vector3(side * _match.local_hero.hook_range() * CAMERA_LEAD_OF_RANGE, 0.0, 0.0)
	if not _camera_placed:
		_camera.global_position = target + CAMERA_OFFSET
		_camera.look_at(target)
		_camera_placed = true
	_camera.global_position = _camera.global_position.lerp(target + CAMERA_OFFSET, minf(1.0, CAMERA_FOLLOW_SPEED * delta))


func _on_impact(strength: float) -> void:
	_shake = minf(1.0, _shake + strength)
	for step: Array in VIBRATION_MSEC:
		if strength >= step[0]:
			Settings.vibrate(step[1])
			return


func _update_shake(delta: float) -> void:
	_shake = maxf(0.0, _shake - SHAKE_DECAY * delta)
	_shake_time += delta * 40.0
	var amount := _shake * _shake * SHAKE_MAX_OFFSET
	_camera.h_offset = sin(_shake_time * 1.3) * amount
	_camera.v_offset = cos(_shake_time * 1.7) * amount


func _unhandled_input(event: InputEvent) -> void:
	if not _shop.visible:
		return
	var pressed := (event is InputEventScreenTouch or event is InputEventMouseButton) and event.is_pressed()
	# The left half is the floating joystick, so walking away while shopping keeps the shop open.
	if pressed and event.position.x > get_viewport().get_visible_rect().size.x * 0.5:
		_shop.hide()


func _update_shop_buttons(hero: HeroState, playing: bool) -> void:
	var costs := _match.rules.upgrade_costs
	var target := Upgrades.quick_buy_target(hero.upgrades, costs, _shop.starred)
	_quick_buy.visible = target >= 0
	var can_quick_buy := false
	if target >= 0:
		var cost := Upgrades.next_cost(hero.upgrades, costs, target)
		_quick_buy.icon = ShopPanel.ICONS[target]
		_quick_buy.text = str(cost)
		can_quick_buy = playing and hero.gold >= cost
		_quick_buy.disabled = not can_quick_buy
	_pulse(_quick_buy, can_quick_buy)
	_pulse(_shop_button, playing and not _shop.visible and Upgrades.any_affordable(hero.upgrades, costs, hero.gold))


func _pulse(button: Control, active: bool) -> void:
	var wave := (sin(Time.get_ticks_msec() / 1000.0 * PULSE_SPEED) + 1.0) / 2.0 if active else 0.0
	button.pivot_offset = button.size / 2.0
	button.scale = Vector2.ONE * (1.0 + PULSE_SCALE * wave)
	button.modulate = Color.WHITE.lerp(PULSE_TINT, wave)


func _on_quick_buy() -> void:
	var hero := _match.local_hero
	var target := Upgrades.quick_buy_target(hero.upgrades, _match.rules.upgrade_costs, _shop.starred)
	if target >= 0:
		_match.buy(target)


func _play_progress_sounds(hero: HeroState) -> void:
	if _last_levels.size() == hero.upgrades.size():
		var shown := 0
		for kind in hero.upgrades.size():
			if hero.upgrades[kind] > _last_levels[kind]:
				_celebrate_upgrade(kind, shown)
				shown += 1
	_last_levels = hero.upgrades.duplicate()
	if _match.phase != _last_phase and _match.phase == MatchSimulation.Phase.ENDED:
		Sfx.play(self, &"victory" if _match.winner == hero.team else &"defeat", -3.0)
	_last_phase = _match.phase


func _celebrate_upgrade(kind: int, stack: int) -> void:
	var at := _view.local_position()
	Fx.floating_text(_view, at + Vector3.UP * (2.6 + stack * 0.6), "+" + Upgrades.FULL_NAMES[kind], Color(1.0, 0.9, 0.5), 26)
	if stack > 0:
		return
	Sfx.play(self, &"level_up", -4.0)
	Settings.vibrate(20)
	Fx.burst(_view, at + Vector3.UP, &"sparkles", Color(1.0, 0.85, 0.35))


func _status_text() -> String:
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return "Practice"
	if multiplayer.is_server():
		return "Hosting on %s" % Net.local_address()
	var ping := "Ping %d ms" % _match.ping_ms if _match.ping_ms >= 0 else "Connecting…"
	return ping if Net.room_code.is_empty() else "Room %s  ·  %s" % [Net.room_code, ping]


func _clock_text() -> String:
	if _match.phase == MatchSimulation.Phase.ENDED:
		return ""
	if _match.overtime:
		return "OVERTIME"
	var seconds := ceili(_match.ticks_left / float(MatchSimulation.TICK_RATE))
	return "%d:%02d" % [seconds / 60, seconds % 60]


func _update_end_banner(my_team: int) -> void:
	var ended := _match.phase == MatchSimulation.Phase.ENDED
	_end_banner.visible = ended
	if not ended:
		return
	var title: Label = _end_banner.get_node("Title")
	if _match.winner == -1:
		title.text = "DRAW"
		title.modulate = Color.WHITE
	elif _match.winner == my_team:
		title.text = "VICTORY!"
		title.modulate = Color(1.0, 0.85, 0.3)
	else:
		title.text = "DEFEAT"
		title.modulate = Color(0.75, 0.8, 0.9)
	var seconds := ceili(_match.ticks_left / float(MatchSimulation.TICK_RATE))
	_end_banner.get_node("Subtitle").text = "Next match in %d" % seconds


func _on_score_changed(red: int, blue: int) -> void:
	_score.text = "[center][color=#ff6b5e]RED %d[/color]  [color=#ffffff]:[/color]  [color=#6fa2ff]%d BLUE[/color][/center]" % [red, blue]
