class_name MatchRules
extends Resource

@export var team_size := 3
@export var score_limit := 20
@export var time_limit := 360.0
@export var respawn_time := 3.0
@export var restart_delay := 8.0
@export var gold_per_kill := 100
@export var gold_per_second := 5
@export var upgrade_costs: PackedInt32Array = [100, 150, 200, 250, 300]

@export_group("Power-ups")
@export var powerup_interval := 12.0
@export var max_powerups := 2
@export var powerup_lane_half_width := 0.8
@export var powerup_lane_fraction := 0.8
@export var powerup_radius := 0.55
@export var shield_time := 15.0
@export var haste_time := 8.0
@export var haste_multiplier := 1.4
@export var gold_bag := 150
