class_name EnemyLootEntry
extends Resource
## One possible drop in an EnemyLootTable.

## Placeholder item id until an item database exists, e.g. &"bramble_thorn".
@export var item_id: StringName
@export_range(0.0, 1.0) var chance := 0.5
@export var count_min := 1
@export var count_max := 1
