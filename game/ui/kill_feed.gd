class_name KillFeed
extends VBoxContainer

const TEAM_HEX: Array[String] = ["#ff7a6e", "#7fb0ff"]
const VISIBLE_SECONDS := 4.0
const FADE_SECONDS := 0.6
const MAX_ENTRIES := 5


func add_kill(killer_name: String, killer_team: int, victim_name: String, victim_team: int) -> void:
	var entry := RichTextLabel.new()
	entry.bbcode_enabled = true
	entry.fit_content = true
	entry.scroll_active = false
	entry.autowrap_mode = TextServer.AUTOWRAP_OFF
	entry.mouse_filter = Control.MOUSE_FILTER_IGNORE
	entry.add_theme_font_size_override("normal_font_size", 20)
	entry.add_theme_constant_override("outline_size", 6)
	entry.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.1))
	entry.text = "[right][color=%s]%s[/color] hooked [color=%s]%s[/color][/right]" % [
		TEAM_HEX[killer_team], _escape(killer_name), TEAM_HEX[victim_team], _escape(victim_name),
	]
	add_child(entry)
	while get_child_count() > MAX_ENTRIES:
		get_child(0).free()
	var tween := entry.create_tween()
	tween.tween_interval(VISIBLE_SECONDS)
	tween.tween_property(entry, "modulate:a", 0.0, FADE_SECONDS)
	tween.tween_callback(entry.queue_free)


static func _escape(text: String) -> String:
	return text.replace("[", "[lb]")
