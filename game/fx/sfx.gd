class_name Sfx
extends RefCounted

const STREAMS := {
	&"hook_throw": preload("res://audio/sfx/hook_throw.wav"),
	&"chain_rattle": preload("res://audio/sfx/chain_rattle.wav"),
	&"hook_clank": preload("res://audio/sfx/hook_clank.wav"),
	&"hit_thwack": preload("res://audio/sfx/hit_thwack.wav"),
	&"splash": preload("res://audio/sfx/splash.wav"),
	&"poof": preload("res://audio/sfx/poof.wav"),
	&"spawn": preload("res://audio/sfx/spawn.wav"),
	&"coin": preload("res://audio/sfx/coin.wav"),
	&"victory": preload("res://audio/sfx/victory.wav"),
	&"defeat": preload("res://audio/sfx/defeat.wav"),
	&"kill_ding": preload("res://audio/sfx/kill_ding.wav"),
	&"ui_click": preload("res://audio/sfx/ui_click.wav"),
}
const PITCH_VARIATION := 0.07


static func play_at(parent: Node, sound: StringName, position: Vector3, volume_db := 0.0) -> void:
	var player := AudioStreamPlayer3D.new()
	player.stream = STREAMS[sound]
	player.volume_db = volume_db
	player.pitch_scale = randf_range(1.0 - PITCH_VARIATION, 1.0 + PITCH_VARIATION)
	player.unit_size = 14.0
	player.max_distance = 50.0
	player.finished.connect(player.queue_free)
	parent.add_child(player)
	player.global_position = position
	player.play()


static func play(parent: Node, sound: StringName, volume_db := 0.0) -> void:
	var player := AudioStreamPlayer.new()
	player.stream = STREAMS[sound]
	player.volume_db = volume_db
	player.finished.connect(player.queue_free)
	parent.add_child(player)
	player.play()
