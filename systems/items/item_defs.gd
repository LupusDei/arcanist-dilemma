class_name ItemDefs
extends RefCounted
## Shared names for the item system: rarities, item kinds, equipment slots and
## the stat keys that gear and affixes write into.
##
## Rarities follow the mechanics doc (Gear and loot): common white with no
## random traits, magic blue with 1 or 2, rare yellow with 3 to 5, unique gold
## with a fixed set.

enum Rarity { COMMON, MAGIC, RARE, UNIQUE }

enum Kind {
	GEAR,  ## Equippable: hats, robes, staves, rings, off-hands and the rest.
	POTION,  ## Drinkable, stacks.
	SPELLBOOK,  ## A wizard studies it to add a spell (at a circle) to their Library.
	MATERIAL,  ## Trophies and reagents (bramble thorns, hex dust). Stack, sell.
	GOLD,  ## Only as a pickup; the inventory keeps gold as a number.
}

const RARITY_NAMES := {
	Rarity.COMMON: "Common",
	Rarity.MAGIC: "Magic",
	Rarity.RARE: "Rare",
	Rarity.UNIQUE: "Unique",
}

const RARITY_COLORS := {
	Rarity.COMMON: Color(0.92, 0.9, 0.86),
	Rarity.MAGIC: Color(0.42, 0.55, 1.0),
	Rarity.RARE: Color(1.0, 0.9, 0.35),
	Rarity.UNIQUE: Color(0.86, 0.66, 0.3),
}

## Random traits per rarity, inclusive.
const RARITY_AFFIX_COUNT := {
	Rarity.COMMON: Vector2i(0, 0),
	Rarity.MAGIC: Vector2i(1, 2),
	Rarity.RARE: Vector2i(3, 5),
	Rarity.UNIQUE: Vector2i(0, 0),
}

## Equipment slots. Two ring slots share the "ring" category.
const SLOTS: Array[StringName] = [
	&"hat", &"amulet", &"robe", &"main_hand", &"off_hand",
	&"gloves", &"belt", &"boots", &"ring_1", &"ring_2",
]

const SLOT_NAMES := {
	&"hat": "Hat", &"amulet": "Amulet", &"robe": "Robe", &"main_hand": "Staff or wand",
	&"off_hand": "Off-hand", &"gloves": "Gloves", &"belt": "Belt", &"boots": "Boots",
	&"ring_1": "Ring", &"ring_2": "Ring",
}

## Which slots a base's category can go in.
const CATEGORY_SLOTS := {
	&"hat": [&"hat"],
	&"amulet": [&"amulet"],
	&"robe": [&"robe"],
	&"staff": [&"main_hand"],
	&"wand": [&"main_hand"],
	&"grimoire": [&"off_hand"],
	&"lens": [&"off_hand"],
	&"focus": [&"off_hand"],
	&"gloves": [&"gloves"],
	&"belt": [&"belt"],
	&"boots": [&"boots"],
	&"ring": [&"ring_1", &"ring_2"],
}

## The path off-hand: a grimoire for wizards, a lens for mages, a focus stone for sorcerers.
const OFF_HAND_PATH := {&"grimoire": "wizard", &"lens": "mage", &"focus": "sorcerer"}

const ATTRIBUTES: Array[StringName] = [&"strength", &"vitality", &"dexterity", &"intelligence", &"wisdom"]

## Every stat key gear can carry, with how a tooltip shows it.
## "%" stats are stored as whole percents (12 means +12%).
const STAT_FORMAT := {
	&"strength": "+%d Strength",
	&"vitality": "+%d Vitality",
	&"dexterity": "+%d Dexterity",
	&"intelligence": "+%d Intelligence",
	&"wisdom": "+%d Wisdom",
	&"all_attributes": "+%d to all Attributes",
	&"max_health": "+%d Health",
	&"health_regen": "+%.1f Health per second",
	&"armor": "+%d Armor",
	&"spell_power": "+%d%% Spell Power",
	&"force_power": "+%d%% Force Damage",
	&"cast_speed": "+%d%% Cast Speed",
	&"crit_chance": "+%d%% Critical Chance",
	&"crit_damage": "+%d%% Critical Damage",
	&"max_resource": "+%d Maximum Arcana, Mana or Strain",
	&"resource_regen": "+%d%% Resource Regeneration",
	&"resist_fire": "+%d%% Fire Resistance",
	&"resist_cold": "+%d%% Cold Resistance",
	&"resist_lightning": "+%d%% Lightning Resistance",
	&"resist_arcane": "+%d%% Arcane Resistance",
	&"resist_mind": "+%d%% Mind Resistance",
	&"resist_all": "+%d%% to all Resistances",
	&"move_speed": "+%d%% Movement Speed",
	&"magic_find": "+%d%% Better Chance of Magic Items",
	&"gold_find": "+%d%% Extra Gold",
	&"plus_spell": "+%d to %s",
}

const RESISTANCE_STATS: Array[StringName] = [&"resist_fire", &"resist_cold", &"resist_lightning", &"resist_arcane", &"resist_mind"]


static func rarity_color(rarity: int) -> Color:
	return RARITY_COLORS.get(rarity, RARITY_COLORS[Rarity.COMMON])


static func rarity_name(rarity: int) -> String:
	return RARITY_NAMES.get(rarity, "Common")


static func rarity_from_name(text: String) -> int:
	match text.to_lower():
		"magic": return Rarity.MAGIC
		"rare": return Rarity.RARE
		"unique": return Rarity.UNIQUE
	return Rarity.COMMON


static func kind_from_name(text: String) -> int:
	match text.to_lower():
		"potion": return Kind.POTION
		"spellbook": return Kind.SPELLBOOK
		"material": return Kind.MATERIAL
		"gold": return Kind.GOLD
	return Kind.GEAR


## One tooltip line for a stat, e.g. "+12% Cast Speed" or "+1 to Fireball".
static func format_stat(stat: StringName, value: float, spell_name := "") -> String:
	var fmt: String = STAT_FORMAT.get(stat, "+%d " + String(stat).capitalize())
	if stat == &"plus_spell":
		return fmt % [roundi(value), spell_name]
	if fmt.contains("%.1f"):
		return fmt % value
	return fmt % roundi(value)
