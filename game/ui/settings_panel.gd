class_name SettingsPanel
extends PanelContainer

@onready var _sound: CheckButton = %Sound
@onready var _vibration: CheckButton = %Vibration


func _ready() -> void:
	_sound.button_pressed = Settings.sound_enabled
	_vibration.button_pressed = Settings.vibration_enabled
	_sound.toggled.connect(Settings.set_sound_enabled)
	_vibration.toggled.connect(func(enabled: bool) -> void:
		Settings.set_vibration_enabled(enabled)
		Settings.vibrate(30)
	)
	%Version.text = "Version %s  ·  protocol %d" % [Settings.app_version(), Net.PROTOCOL]
	%Close.pressed.connect(hide)
