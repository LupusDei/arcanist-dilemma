class_name ItemInstance
extends Resource
## One actual item: a base plus its rolls. This is what sits in the inventory,
## in an equipment slot or on the ground. Saves to a plain dictionary.

## Fires when the stack count changes.
signal quantity_changed(quantity: int)

@export var base_id := &""
@export var rarity: ItemDefs.Rarity = ItemDefs.Rarity.COMMON
## Level of the monster, chest or area it came from. Gates which affixes it could roll.
@export var item_level := 1
## Rolled traits: [{"id": &"pre_int_1", "value": 4.0}], plus "spell" for "+N to a spell".
@export var affixes: Array[Dictionary] = []
@export var unique_id := &""
## A rare's two-word name, such as "Grim Whisper".
@export var rare_name := ""
@export var quantity := 1:
	set(value):
		quantity = value
		quantity_changed.emit(quantity)
## Spellbooks: the spell inside and its circle.
@export var spell_id := &""
@export var circle := 1


static func create(p_base_id: StringName, p_quantity := 1) -> ItemInstance:
	var item := ItemInstance.new()
	item.base_id = p_base_id
	item.quantity = p_quantity
	var base := item.get_base()
	if base:
		item.item_level = base.level
		if base.kind == ItemDefs.Kind.SPELLBOOK and base.spell_id != &"":
			item.spell_id = base.spell_id
			item.circle = base.circle
	return item


func get_base() -> ItemBase:
	return ItemDatabase.get_base(base_id)


func get_unique() -> UniqueDef:
	return ItemDatabase.get_unique(unique_id) if unique_id != &"" else null


func is_gear() -> bool:
	var base := get_base()
	return base != null and base.is_gear()


func get_kind() -> int:
	var base := get_base()
	return base.kind if base else ItemDefs.Kind.MATERIAL


func get_size() -> Vector2i:
	var base := get_base()
	return base.size if base else Vector2i.ONE


func get_max_stack() -> int:
	var base := get_base()
	return base.max_stack if base else 1


func can_stack_with(other: ItemInstance) -> bool:
	return other != null and other != self and get_max_stack() > 1 and other.base_id == base_id \
			and other.spell_id == spell_id and other.circle == circle and affixes.is_empty() and other.affixes.is_empty()


func get_color() -> Color:
	if get_kind() == ItemDefs.Kind.SPELLBOOK:
		return ItemDefs.rarity_color(ItemDefs.Rarity.MAGIC if circle < 3 else ItemDefs.Rarity.RARE)
	return ItemDefs.rarity_color(rarity)


func get_display_name() -> String:
	var base := get_base()
	var base_name := base.display_name if base else String(base_id).capitalize()
	match get_kind():
		ItemDefs.Kind.SPELLBOOK:
			return "Spellbook: %s (Circle %s)" % [ItemDatabase.spell_display_name(spell_id), _roman(circle)]
		ItemDefs.Kind.GEAR:
			pass
		_:
			return base_name
	if rarity == ItemDefs.Rarity.UNIQUE and get_unique():
		return get_unique().display_name
	if rarity == ItemDefs.Rarity.RARE and not rare_name.is_empty():
		return rare_name
	if rarity == ItemDefs.Rarity.MAGIC:
		var prefix := ""
		var suffix := ""
		for roll in affixes:
			var def := ItemDatabase.get_affix(roll.get("id", &""))
			if def == null:
				continue
			if def.type == AffixDef.Type.PREFIX and prefix.is_empty():
				prefix = def.text
			elif def.type == AffixDef.Type.SUFFIX and suffix.is_empty():
				suffix = def.text
		return " ".join(PackedStringArray([prefix, base_name, suffix])).strip_edges().replace("  ", " ")
	return base_name


## Every stat this item gives when worn: implicit, unique and rolled, summed.
## all_attributes and resist_all are spread over their parts.
func get_stats() -> Dictionary:
	var out := {}
	var base := get_base()
	if base == null or not base.is_gear():
		return out
	for k in base.implicit_stats:
		_add_stat(out, k, float(base.implicit_stats[k]))
	var unique := get_unique()
	if unique:
		for k in unique.stats:
			_add_stat(out, k, float(unique.stats[k]))
	for roll in affixes:
		var def := ItemDatabase.get_affix(roll.get("id", &""))
		if def and def.stat != &"plus_spell":
			_add_stat(out, def.stat, float(roll.get("value", 0.0)))
	return out


## Gear "+N to a spell": spell id -> ranks.
func get_spell_bonuses() -> Dictionary:
	var out := {}
	var unique := get_unique()
	if unique:
		for k in unique.spell_bonuses:
			out[k] = int(out.get(k, 0)) + int(unique.spell_bonuses[k])
	for roll in affixes:
		var def := ItemDatabase.get_affix(roll.get("id", &""))
		if def and def.stat == &"plus_spell" and roll.has("spell"):
			var id := StringName(roll["spell"])
			out[id] = int(out.get(id, 0)) + int(roll.get("value", 1))
	return out


## Character level needed: the base's, the unique's, or the highest rolled affix's.
func get_required_level() -> int:
	var base := get_base()
	var lvl := base.level if base else 1
	var unique := get_unique()
	if unique:
		lvl = maxi(lvl, unique.level)
	for roll in affixes:
		var def := ItemDatabase.get_affix(roll.get("id", &""))
		if def:
			lvl = maxi(lvl, def.level)
	return lvl


func get_requirements() -> Dictionary:
	var base := get_base()
	return base.requirements.duplicate() if base else {}


func get_required_path() -> String:
	var base := get_base()
	return base.required_path() if base else ""


func get_sell_value() -> int:
	var base := get_base()
	var v := base.value if base else 1
	match rarity:
		ItemDefs.Rarity.MAGIC: v *= 3
		ItemDefs.Rarity.RARE: v *= 8
		ItemDefs.Rarity.UNIQUE: v *= 20
	if get_kind() == ItemDefs.Kind.SPELLBOOK:
		v *= circle * circle
	return maxi(v, 1) * quantity


## Tooltip lines, each {"text": String, "color": Color}. Requirements the
## [param character] (see ItemRules.character_snapshot) misses are shown in red.
func tooltip_lines(character := {}) -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	var base := get_base()
	var white := ItemDefs.rarity_color(ItemDefs.Rarity.COMMON)
	var muted := Color(0.62, 0.58, 0.52)
	var red := Color(0.92, 0.36, 0.3)
	var blue := ItemDefs.rarity_color(ItemDefs.Rarity.MAGIC)
	lines.append({"text": get_display_name(), "color": get_color()})
	if base == null:
		return lines
	if rarity == ItemDefs.Rarity.RARE or rarity == ItemDefs.Rarity.UNIQUE:
		lines.append({"text": base.display_name, "color": get_color()})
	if base.is_gear():
		var slot_text: String = ItemDefs.SLOT_NAMES.get(base.allowed_slots()[0] if not base.allowed_slots().is_empty() else &"", "")
		var path := get_required_path()
		lines.append({"text": slot_text + ("" if path.is_empty() else " (%s only)" % path.capitalize()), "color": muted})
		for k in base.implicit_stats:
			lines.append({"text": ItemDefs.format_stat(k, float(base.implicit_stats[k])), "color": white})
	elif base.kind == ItemDefs.Kind.POTION:
		if base.heal_amount > 0.0:
			lines.append({"text": "Restores %d health" % roundi(base.heal_amount), "color": white})
		if base.resource_amount > 0.0:
			lines.append({"text": "Restores %d mana or arcana, or cools %d strain" % [roundi(base.resource_amount), roundi(base.resource_amount)], "color": white})
		lines.append({"text": "Right click to drink", "color": muted})
	elif base.kind == ItemDefs.Kind.SPELLBOOK:
		lines.append({"text": "Wizards study this to add %s to their Library at Circle %s." % [ItemDatabase.spell_display_name(spell_id), _roman(circle)], "color": white})
		lines.append({"text": "Right click to study", "color": muted})
	if not base.description.is_empty():
		lines.append({"text": base.description, "color": muted})

	var unique := get_unique()
	if unique:
		for k in unique.stats:
			lines.append({"text": ItemDefs.format_stat(k, float(unique.stats[k])), "color": blue})
		for k in unique.spell_bonuses:
			lines.append({"text": ItemDefs.format_stat(&"plus_spell", float(unique.spell_bonuses[k]), ItemDatabase.spell_display_name(k)), "color": blue})
	for roll in affixes:
		var def := ItemDatabase.get_affix(roll.get("id", &""))
		if def:
			lines.append({"text": ItemDefs.format_stat(def.stat, float(roll.get("value", 0.0)), ItemDatabase.spell_display_name(StringName(roll.get("spell", "")))), "color": blue})
	if unique and not unique.flavor.is_empty():
		lines.append({"text": unique.flavor, "color": ItemDefs.rarity_color(ItemDefs.Rarity.UNIQUE)})

	if base.is_gear():
		var req_level := get_required_level()
		if req_level > 1:
			var ok: bool = int(character.get("level", 99)) >= req_level
			lines.append({"text": "Requires level %d" % req_level, "color": white if ok else red})
		var attrs: Dictionary = character.get("attributes", {})
		for k in get_requirements():
			var need := int(get_requirements()[k])
			var ok: bool = attrs.is_empty() or int(attrs.get(StringName(k), 0)) >= need
			lines.append({"text": "Requires %d %s" % [need, String(k).capitalize()], "color": white if ok else red})
	if get_max_stack() > 1 and quantity > 1:
		lines.append({"text": "Quantity %d" % quantity, "color": muted})
	lines.append({"text": "Sells for %d gold" % get_sell_value(), "color": muted})
	return lines


func to_dict() -> Dictionary:
	var d := {"base": String(base_id)}
	if rarity != ItemDefs.Rarity.COMMON:
		d["rarity"] = ItemDefs.rarity_name(rarity).to_lower()
	if item_level != 1:
		d["ilvl"] = item_level
	if not affixes.is_empty():
		var rolls := []
		for roll in affixes:
			var r := {"id": String(roll.get("id", "")), "value": roll.get("value", 0.0)}
			if roll.has("spell"):
				r["spell"] = String(roll["spell"])
			rolls.append(r)
		d["affixes"] = rolls
	if unique_id != &"":
		d["unique"] = String(unique_id)
	if not rare_name.is_empty():
		d["rare_name"] = rare_name
	if quantity != 1:
		d["qty"] = quantity
	if spell_id != &"":
		d["spell"] = String(spell_id)
		d["circle"] = circle
	return d


static func from_dict(d: Dictionary) -> ItemInstance:
	var item := ItemInstance.new()
	item.base_id = StringName(d.get("base", ""))
	item.rarity = ItemDefs.rarity_from_name(d.get("rarity", "common"))
	item.item_level = int(d.get("ilvl", 1))
	var rolls: Array[Dictionary] = []
	for r in d.get("affixes", []):
		var roll := {"id": StringName(r.get("id", "")), "value": float(r.get("value", 0.0))}
		if r.has("spell"):
			roll["spell"] = StringName(r["spell"])
		rolls.append(roll)
	item.affixes = rolls
	item.unique_id = StringName(d.get("unique", ""))
	item.rare_name = d.get("rare_name", "")
	item.quantity = int(d.get("qty", 1))
	item.spell_id = StringName(d.get("spell", ""))
	item.circle = int(d.get("circle", 1))
	return item


static func _add_stat(out: Dictionary, stat: StringName, value: float) -> void:
	match stat:
		&"all_attributes":
			for a in ItemDefs.ATTRIBUTES:
				out[a] = float(out.get(a, 0.0)) + value
		&"resist_all":
			for r in ItemDefs.RESISTANCE_STATS:
				out[r] = float(out.get(r, 0.0)) + value
		_:
			out[stat] = float(out.get(stat, 0.0)) + value


static func _roman(n: int) -> String:
	return ["", "I", "II", "III", "IV", "V", "VI", "VII"][clampi(n, 0, 7)]
