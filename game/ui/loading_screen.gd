class_name LoadingScreen
extends CanvasLayer

signal cancel_pressed

const SPIN_SPEED := 3.5
const BAR_SMOOTHING := 10.0
const FADE_SECONDS := 0.25
const TIPS: Array[String] = [
	"Drag HOOK to aim, release to throw. Tap it again during the wind-up to fake the throw.",
	"Stun them with the arrow, then hook them. It's the classic combo.",
	"Enemies can't see your trap until it snaps shut.",
	"Hook a teammate to pull them out of danger.",
	"Hook the orbs floating down the river for a shield, speed, gold or a Big Hook.",
	"Star an upgrade in the shop, then buy it with one tap using Quick buy.",
	"Your hook reaches all the way to the enemy's back wall. Nowhere is safe.",
	"Arrows fly through rocks, but hooks don't. Use rocks as cover.",
]

@onready var _root: Control = $Root
@onready var _spinner: TextureRect = %Spinner
@onready var _status: Label = %Status
@onready var _bar: ProgressBar = %Bar
@onready var _cancel: Button = %Cancel
@onready var _tip: Label = %Tip

var _target_progress := 0.0
var _fade: Tween


func _ready() -> void:
	_cancel.pressed.connect(cancel_pressed.emit)
	_root.visible = false
	set_process(false)


func open(message: String, show_progress: bool, cancellable: bool) -> void:
	if _fade:
		_fade.kill()
	if not _root.visible:
		_tip.text = "Tip: " + TIPS.pick_random()
	_root.visible = true
	_root.modulate.a = 1.0
	_status.text = message
	_bar.visible = show_progress
	_bar.value = 0.0
	_target_progress = 0.0
	_cancel.visible = cancellable
	set_process(true)


func set_progress(fraction: float) -> void:
	_target_progress = maxf(_target_progress, fraction * 100.0)


func close() -> void:
	if not _root.visible:
		return
	_target_progress = 100.0
	_cancel.visible = false
	if _fade:
		_fade.kill()
	_fade = create_tween()
	_fade.tween_property(_root, "modulate:a", 0.0, FADE_SECONDS)
	_fade.tween_callback(func() -> void:
		_root.visible = false
		set_process(false)
	)


func is_open() -> bool:
	return _root.visible


func _process(delta: float) -> void:
	_spinner.rotation += SPIN_SPEED * delta
	_bar.value = lerpf(_bar.value, _target_progress, 1.0 - exp(-BAR_SMOOTHING * delta))
