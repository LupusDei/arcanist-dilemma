class_name EnemyData
extends Resource
## Tuning for one monster type. Each type scene in res://actors/enemies/types/
## points at one of these, so balance changes never touch the AI script.

enum AttackStyle { MELEE, RANGED }

@export var display_name := "Monster"

@export_group("Stats")
@export var max_health := 60.0
@export var armor := 0.0
@export var move_speed := 3.5
## Speed multiplier while fleeing or returning home.
@export var retreat_speed_multiplier := 1.2
@export var xp_value := 10

@export_group("Senses")
## Notices the player inside this distance.
@export var aggro_range := 10.0
## Gives up and walks home when the player is this far from the enemy's home.
@export var leash_range := 25.0
## Pause between noticing the player and moving, so the player sees it coming.
@export var aggro_delay := 0.4
## On aggro, wakes up packmates within this radius (0 = never).
@export var pack_alert_radius := 0.0

@export_group("Attack")
@export var attack_style: AttackStyle = AttackStyle.MELEE
@export var attack_range := 1.8
@export var attack_damage := 10.0
## Telegraph before the hit lands. Dodging during it avoids the hit.
@export var attack_windup := 0.45
@export var attack_recovery := 0.35
@export var attack_cooldown := 1.2
## Ranged only: backs away when the player is closer than this.
@export var keep_away_distance := 0.0
@export var projectile_scene: PackedScene
@export var projectile_speed := 14.0

@export_group("Flee")
## Flees once when health drops to this fraction (0 = never flees).
@export_range(0.0, 1.0) var flee_health_fraction := 0.0
@export var flee_duration := 2.5

@export_group("Idle")
## Wanders around home within this radius while idle (0 = stands still).
@export var wander_radius := 3.0
@export var wander_pause_min := 1.5
@export var wander_pause_max := 4.0

@export_group("Loot")
@export var loot_table: EnemyLootTable
