extends Node

const PATH := "user://settings.cfg"

var sound_enabled := true
var vibration_enabled := true

var _file := ConfigFile.new()


func _ready() -> void:
	_file.load(PATH)
	sound_enabled = _file.get_value("options", "sound", true)
	vibration_enabled = _file.get_value("options", "vibration", true)
	_apply_sound()


func get_value(section: String, key: String, default: Variant) -> Variant:
	return _file.get_value(section, key, default)


func set_value(section: String, key: String, value: Variant) -> void:
	_file.set_value(section, key, value)
	_file.save(PATH)


func set_sound_enabled(enabled: bool) -> void:
	sound_enabled = enabled
	set_value("options", "sound", enabled)
	_apply_sound()


func set_vibration_enabled(enabled: bool) -> void:
	vibration_enabled = enabled
	set_value("options", "vibration", enabled)


func vibrate(duration_ms: int) -> void:
	if vibration_enabled:
		Input.vibrate_handheld(duration_ms)


func app_version() -> String:
	return ProjectSettings.get_setting("application/config/version", "dev")


func _apply_sound() -> void:
	AudioServer.set_bus_mute(0, not sound_enabled)
