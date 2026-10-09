class_name UniqueDef
extends Resource
## A named gold item with a fixed set of stats (mechanics doc: "named items with
## a build-changing effect, often tied to the story"). Loaded from
## res://data/items/uniques.json.

@export var id := &""
@export var display_name := ""
@export_multiline var flavor := ""
## The base it is built on (its slot, size and implicit stats).
@export var base_id := &""
@export var level := 1
## Fixed stats. A "+N to a spell" is listed under spell_bonuses instead.
@export var stats: Dictionary = {}
## Spell id -> extra ranks.
@export var spell_bonuses: Dictionary = {}
@export var weight := 1.0
## Story uniques never drop at random; quests hand them out with ItemGenerator.make_unique().
@export var quest_only := false


static func from_dict(data: Dictionary) -> UniqueDef:
	var u := UniqueDef.new()
	u.id = StringName(data.get("id", ""))
	u.display_name = data.get("name", String(u.id).capitalize())
	u.flavor = data.get("flavor", "")
	u.base_id = StringName(data.get("base", ""))
	u.level = int(data.get("level", 1))
	u.stats = ItemBase._string_name_keys(data.get("stats", {}))
	u.spell_bonuses = ItemBase._string_name_keys(data.get("spells", {}))
	u.weight = float(data.get("weight", 1.0))
	u.quest_only = bool(data.get("quest_only", false))
	return u
