class_name Equipment
extends RefCounted
## What the arcanist wears: hat, amulet, robe, main hand, path off-hand, gloves,
## belt, boots and two rings. Sums the worn items' stats for progression and combat.
##
## A "character" here is a plain dictionary so this works with or without the
## progression system: {"level": 7, "path": "wizard", "attributes": {&"strength": 14, ...}}.
## Items.character_snapshot() builds it from the Progression autoload.

signal changed
signal equipped(slot: StringName, item: ItemInstance)
signal unequipped(slot: StringName, item: ItemInstance)

## Slot name -> ItemInstance (missing when empty).
var slots: Dictionary = {}


func get_item(slot: StringName) -> ItemInstance:
	return slots.get(slot)


func is_equipped(item: ItemInstance) -> bool:
	return slot_of(item) != &""


func slot_of(item: ItemInstance) -> StringName:
	for s in slots:
		if slots[s] == item:
			return s
	return &""


## The slot an item would go to: its only slot, or the first empty ring slot.
func best_slot_for(item: ItemInstance) -> StringName:
	var base := item.get_base() if item else null
	if base == null or not base.is_gear():
		return &""
	var allowed := base.allowed_slots()
	if allowed.is_empty():
		return &""
	for s in allowed:
		if not slots.has(s):
			return s
	return allowed[0]


## Empty if [param item] can go in [param slot] for [param character], otherwise
## a reason: &"not_gear", &"wrong_slot", &"level", &"path", &"strength" (or another attribute).
func check_equip(item: ItemInstance, slot: StringName, character := {}) -> StringName:
	var base := item.get_base() if item else null
	if base == null or not base.is_gear():
		return &"not_gear"
	if not base.allowed_slots().has(slot):
		return &"wrong_slot"
	return check_requirements(item, character, slot)


## Level, path and attribute checks. Attributes count gear bonuses from the other
## worn items (not the one in [param replacing_slot]), as in Diablo 2.
func check_requirements(item: ItemInstance, character := {}, replacing_slot := &"") -> StringName:
	if character.is_empty():
		return &""
	if int(character.get("level", 1)) < item.get_required_level():
		return &"level"
	var path := item.get_required_path()
	if not path.is_empty() and String(character.get("path", "")) != path:
		return &"path"
	var attrs: Dictionary = character.get("attributes", {})
	var gear := total_stats(slots.get(replacing_slot) if replacing_slot != &"" else null)
	for k in item.get_requirements():
		var have := int(attrs.get(StringName(k), 10)) + int(gear.get(StringName(k), 0.0))
		if have < int(item.get_requirements()[k]):
			return StringName(k)
	return &""


## Puts [param item] in [param slot] and returns what was there (or null).
## Does not check requirements; call check_equip first.
func equip(item: ItemInstance, slot: StringName) -> ItemInstance:
	var previous: ItemInstance = slots.get(slot)
	if previous:
		slots.erase(slot)
		unequipped.emit(slot, previous)
	slots[slot] = item
	equipped.emit(slot, item)
	changed.emit()
	return previous


func unequip(slot: StringName) -> ItemInstance:
	var item: ItemInstance = slots.get(slot)
	if item == null:
		return null
	slots.erase(slot)
	unequipped.emit(slot, item)
	changed.emit()
	return item


## Every stat from worn gear, summed. [param exclude] leaves one item out
## (for requirement checks and compare tooltips).
func total_stats(exclude: ItemInstance = null) -> Dictionary:
	var out := {}
	for s in slots:
		var item: ItemInstance = slots[s]
		if item == exclude:
			continue
		var stats := item.get_stats()
		for k in stats:
			out[k] = float(out.get(k, 0.0)) + float(stats[k])
	return out


## Gear "+N to a spell" from every worn item: spell id -> ranks.
func spell_bonuses() -> Dictionary:
	var out := {}
	for s in slots:
		var bonus: Dictionary = slots[s].get_spell_bonuses()
		for k in bonus:
			out[k] = int(out.get(k, 0)) + int(bonus[k])
	return out


## Worn items that no longer meet [param character]'s requirements (after a
## respec, say). They stay worn; the UI can show them in red.
func unmet_items(character: Dictionary) -> Array[ItemInstance]:
	var out: Array[ItemInstance] = []
	for s in slots:
		if check_requirements(slots[s], character, s) != &"":
			out.append(slots[s])
	return out


func clear() -> void:
	slots.clear()
	changed.emit()


func to_dict() -> Dictionary:
	var d := {}
	for s in slots:
		d[String(s)] = slots[s].to_dict()
	return d


func apply_dict(d: Dictionary) -> void:
	slots.clear()
	for s in d:
		var item := ItemInstance.from_dict(d[s])
		if item.get_base() != null and ItemDefs.SLOTS.has(StringName(s)):
			slots[StringName(s)] = item
	changed.emit()
