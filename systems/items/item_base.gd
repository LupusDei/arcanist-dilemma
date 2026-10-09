class_name ItemBase
extends Resource
## One kind of item before any random rolls: "Oak Staff", "Silk Robe",
## "Minor Healing Draught", "Spellbook". Bases live in res://data/items/bases.json
## and load through ItemDatabase; a .tres saved under res://data/items/ works too.

@export var id := &""
@export var display_name := ""
@export_multiline var description := ""
@export var kind: ItemDefs.Kind = ItemDefs.Kind.GEAR
## Gear only: hat, robe, staff, wand, grimoire, lens, focus, gloves, belt, boots, amulet, ring.
@export var category := &""
## Lowest item level this base drops at; also the character level needed to wear it.
@export var level := 1
## Attribute requirements, e.g. {&"strength": 18}.
@export var requirements: Dictionary = {}
## Fixed stats every copy has (armor on a robe, spell power on a staff).
@export var implicit_stats: Dictionary = {}
## Cells it takes in the inventory grid.
@export var size := Vector2i.ONE
@export var max_stack := 1
## Sell value in gold; buying costs four times as much.
@export var value := 1
## Weight in loot rolls among bases of the same kind.
@export var drop_weight := 10.0
## Biomes it drops in. Empty means everywhere.
@export var biomes: PackedStringArray = []
## Draw color for the placeholder icon and the dropped mesh.
@export var color := Color(0.6, 0.55, 0.5)
@export var icon: Texture2D

@export_group("Potion")
@export var heal_amount := 0.0
## Restores mana or arcana, or cools this much strain for a sorcerer.
@export var resource_amount := 0.0

@export_group("Spellbook")
## Set on a fixed spellbook (a quest reward). Rolled spellbooks pick one at drop time.
@export var spell_id := &""
@export_range(1, 7) var circle := 1


func is_gear() -> bool:
	return kind == ItemDefs.Kind.GEAR


func is_stackable() -> bool:
	return max_stack > 1


## The path this base is limited to ("" for all), from the off-hand category.
func required_path() -> String:
	return ItemDefs.OFF_HAND_PATH.get(category, "")


func allowed_slots() -> Array:
	return ItemDefs.CATEGORY_SLOTS.get(category, [])


static func from_dict(data: Dictionary) -> ItemBase:
	var b := ItemBase.new()
	b.id = StringName(data.get("id", ""))
	b.display_name = data.get("name", String(b.id).capitalize())
	b.description = data.get("description", "")
	b.kind = ItemDefs.kind_from_name(data.get("kind", "gear"))
	b.category = StringName(data.get("category", ""))
	b.level = int(data.get("level", 1))
	b.requirements = _string_name_keys(data.get("requirements", {}))
	b.implicit_stats = _string_name_keys(data.get("stats", {}))
	var s: Array = data.get("size", [1, 1])
	b.size = Vector2i(int(s[0]), int(s[1]))
	b.max_stack = int(data.get("max_stack", 1))
	b.value = int(data.get("value", 1))
	b.drop_weight = float(data.get("weight", 10.0))
	b.biomes = PackedStringArray(data.get("biomes", []))
	if data.has("color"):
		b.color = Color(data["color"])
	b.heal_amount = float(data.get("heal", 0.0))
	b.resource_amount = float(data.get("restore", 0.0))
	b.spell_id = StringName(data.get("spell_id", ""))
	b.circle = int(data.get("circle", 1))
	return b


static func _string_name_keys(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[StringName(k)] = d[k]
	return out
