class_name AffixDef
extends Resource
## One random trait a magic or rare item can roll, Diablo 2 style:
## a prefix ("Sparking Oak Staff") or a suffix ("Oak Staff of the Fox").
## Stronger tiers of the same trait are separate affixes in the same group,
## so an item never rolls two of a group.

enum Type { PREFIX, SUFFIX }

@export var id := &""
@export var type: Type = Type.PREFIX
## The word in the item's name: "Sparking" or "of the Fox".
@export var text := ""
## Affixes in one group exclude each other (all "+Intelligence" tiers share one).
@export var group := &""
@export var stat := &""
@export var value_min := 1.0
@export var value_max := 1.0
## Lowest item level it can roll on.
@export var level := 1
@export var weight := 10.0
## Base categories it can roll on. Empty means any gear.
@export var categories: PackedStringArray = []
## plus_spell only: which path's spells it can name.
@export var spell_path := ""


func fits(category: StringName, item_level: int) -> bool:
	if item_level < level:
		return false
	return categories.is_empty() or categories.has(String(category))


func roll_value(rng: RandomNumberGenerator) -> float:
	if is_equal_approx(value_min, value_max):
		return value_min
	if value_max - value_min >= 1.0 and is_equal_approx(value_min, roundf(value_min)):
		return float(rng.randi_range(int(value_min), int(value_max)))
	return snappedf(rng.randf_range(value_min, value_max), 0.1)


static func from_dict(data: Dictionary) -> AffixDef:
	var a := AffixDef.new()
	a.id = StringName(data.get("id", ""))
	a.type = Type.SUFFIX if data.get("type", "prefix") == "suffix" else Type.PREFIX
	a.text = data.get("text", "")
	a.group = StringName(data.get("group", data.get("stat", "")))
	a.stat = StringName(data.get("stat", ""))
	var v: Array = data.get("value", [1, 1])
	a.value_min = float(v[0])
	a.value_max = float(v[1] if v.size() > 1 else v[0])
	a.level = int(data.get("level", 1))
	a.weight = float(data.get("weight", 10.0))
	a.categories = PackedStringArray(data.get("categories", []))
	a.spell_path = data.get("spell_path", "")
	return a
