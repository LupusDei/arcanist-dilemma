class_name EnemySpawnEntry
extends Resource
## One kind of monster group a spawn table can place.

@export var enemy_scene: PackedScene
## Relative chance among the entries that fit the request.
@export var weight := 1.0
## Biome tags this group appears in. Empty means any biome.
@export var biomes: Array[StringName] = []
## Area levels this group appears at.
@export_range(1, 60) var min_level := 1
@export_range(1, 60) var max_level := 60
@export var group_min := 1
@export var group_max := 1
@export var spawn_radius := 2.5
