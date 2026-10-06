class_name HookSkill
extends Resource

enum Upgrade { RANGE, SPEED, SIZE, COOLDOWN }

const UPGRADE_NAMES: Array[String] = ["Range", "Speed", "Size", "Cooldown"]

@export var release_time := 0.3
@export var speed := 24.0
@export var return_speed := 26.0
@export var max_range := 13.0
@export var hit_radius := 0.35
@export var cooldown := 1.2
@export var origin_offset := 0.7
@export var height := 0.9

@export_group("Per upgrade level")
@export var range_per_level := 1.5
@export var speed_per_level := 3.0
@export var hit_radius_per_level := 0.08
@export var cooldown_per_level := -0.15
