class_name EnemySpawnRequest
extends Resource
## What a world, village or dungeon generator asks for when populating an area.
## The same request with the same seed always produces the same monsters.

@export var area_seed := 0
@export var biome: StringName = &"meadow"
## Monster levels are picked in this range (inclusive).
@export_range(1, 60) var level_min := 1
@export_range(1, 60) var level_max := 1
## Area to fill, centred on area_center, size in metres along X and Z.
@export var area_center := Vector3.ZERO
@export var area_size := Vector2(60, 60)
## Monster groups per 1000 square metres.
@export var density := 1.0
## Hard cap on groups regardless of area and density (0 = no cap).
@export var max_groups := 0
## Minimum distance between two groups.
@export var min_spacing := 10.0
## Circles kept monster-free, e.g. the player spawn, a village or a quest NPC.
## Each Vector3 is (x, z, radius).
@export var exclusion_zones := PackedVector3Array()
@export_range(0.0, 1.0) var elite_chance := 0.05
## Seconds before a killed monster comes back (0 = never).
@export var respawn_delay := 0.0
