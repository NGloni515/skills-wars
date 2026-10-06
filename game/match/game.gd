extends Node3D

const CAMERA_OFFSET := Vector3(0.0, 11.0, 7.7)
const CAMERA_LEAD := 3.5
const CAMERA_FOLLOW_SPEED := 6.0
const SHAKE_DECAY := 2.2
const SHAKE_MAX_OFFSET := 0.45
const VIBRATION_MSEC := [[0.9, 90], [0.6, 45]]

@onready var _match: MatchController = $Match
@onready var _view: MatchView = $View
@onready var _camera: Camera3D = $Camera3D
@onready var _score: RichTextLabel = $HUD/Score
@onready var _clock: Label = $HUD/Clock
@onready var _status: Label = $HUD/Status
@onready var _gold: Label = $HUD/Gold
@onready var _hook_button: AimButton = $HUD/HookButton
@onready var _shop: ShopPanel = $HUD/ShopPanel
@onready var _end_banner: Control = $HUD/EndBanner

var _camera_placed := false
var _shake := 0.0
var _shake_time := 0.0
var _upgrade_total := 0
var _last_phase := MatchSimulation.Phase.PLAYING


func _ready() -> void:
	if Net.dedicated:
		_view.queue_free()
		$HUD.queue_free()
		_camera.queue_free()
		set_process(false)
		return
	_hook_button.fired.connect(_match.queue_fire)
	_match.score_changed.connect(_on_score_changed)
	_match.kill_reported.connect($HUD/KillFeed.add_kill)
	$HUD/Leave.pressed.connect(Net.leave)
	$HUD/Shop.pressed.connect(_shop.show)
	_shop.buy_requested.connect(_match.buy)
	_view.impact.connect(_on_impact)
	for button: BaseButton in find_children("*", "BaseButton", true, false):
		button.pressed.connect(Sfx.play.bind(self, &"ui_click", -8.0))
	_on_score_changed(0, 0)


func _process(delta: float) -> void:
	var hero := _match.local_hero
	if hero == null:
		return
	_follow_camera(delta)
	_update_shake(delta)
	_play_progress_sounds(hero)
	_status.text = _status_text()
	_clock.text = _clock_text()
	_gold.text = "%d gold" % hero.gold
	if _shop.visible:
		_shop.refresh(hero.gold, hero.upgrades, _match.rules.upgrade_costs, _match.phase == MatchSimulation.Phase.PLAYING)
	_update_end_banner(hero.team)


func _follow_camera(delta: float) -> void:
	var lead := CAMERA_LEAD if _view.local_team() == 0 else -CAMERA_LEAD
	var target := _view.local_position() + Vector3(lead, 0.0, 0.0)
	if not _camera_placed:
		_camera.global_position = target + CAMERA_OFFSET
		_camera.look_at(target)
		_camera_placed = true
	_camera.global_position = _camera.global_position.lerp(target + CAMERA_OFFSET, minf(1.0, CAMERA_FOLLOW_SPEED * delta))


func _on_impact(strength: float) -> void:
	_shake = minf(1.0, _shake + strength)
	for step: Array in VIBRATION_MSEC:
		if strength >= step[0]:
			Input.vibrate_handheld(step[1])
			return


func _update_shake(delta: float) -> void:
	_shake = maxf(0.0, _shake - SHAKE_DECAY * delta)
	_shake_time += delta * 40.0
	var amount := _shake * _shake * SHAKE_MAX_OFFSET
	_camera.h_offset = sin(_shake_time * 1.3) * amount
	_camera.v_offset = cos(_shake_time * 1.7) * amount


func _play_progress_sounds(hero: HeroState) -> void:
	var total: int = hero.upgrades.reduce(func(sum: int, level: int) -> int: return sum + level, 0)
	if total > _upgrade_total:
		Sfx.play(self, &"coin", -4.0)
		Input.vibrate_handheld(15)
	_upgrade_total = total
	if _match.phase != _last_phase and _match.phase == MatchSimulation.Phase.ENDED:
		Sfx.play(self, &"victory" if _match.winner == hero.team else &"defeat", -3.0)
	_last_phase = _match.phase


func _status_text() -> String:
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return "Practice"
	if multiplayer.is_server():
		return "Hosting on %s" % Net.local_address()
	return "Ping %d ms" % _match.ping_ms if _match.ping_ms >= 0 else "Connecting…"


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
