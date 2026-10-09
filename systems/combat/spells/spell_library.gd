class_name SpellLibrary
extends RefCounted
## Loads every SpellData under res://data/spells/ once and looks them up by id.
## No autoload needed: everything is static and cached.

const ROOT := "res://data/spells"

static var _by_id: Dictionary = {}
static var _loaded := false


static func get_spell(id: StringName) -> SpellData:
	_ensure_loaded()
	return _by_id.get(id)


static func has_spell(id: StringName) -> bool:
	_ensure_loaded()
	return _by_id.has(id)


static func all_spells() -> Array[SpellData]:
	_ensure_loaded()
	var result: Array[SpellData] = []
	for spell in _by_id.values():
		result.append(spell)
	return result


static func spells_for_path(path: SpellData.PathTag) -> Array[SpellData]:
	var result: Array[SpellData] = []
	for spell in all_spells():
		if spell.path == path:
			result.append(spell)
	return result


## The authored spell for a mage verb + noun pair, or null.
static func find_pair(verb: StringName, noun: StringName) -> SpellData:
	for spell in all_spells():
		if spell.verb == verb and spell.noun == noun:
			return spell
	return null


## Adds a spell at runtime (tests, generated mage pairs). Replaces one with the same id.
static func register(spell: SpellData) -> void:
	_ensure_loaded()
	_by_id[spell.id] = spell


static func reload() -> void:
	_by_id.clear()
	_loaded = false
	_ensure_loaded()


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_scan(ROOT)


static func _scan(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_scan(dir_path.path_join(sub))
	for file in dir.get_files():
		# Exported builds list "x.tres.remap"; load by the original name.
		file = file.trim_suffix(".remap")
		if not (file.ends_with(".tres") or file.ends_with(".res")):
			continue
		var spell := load(dir_path.path_join(file)) as SpellData
		if spell == null:
			continue
		if spell.id == &"":
			spell.id = StringName(file.get_basename())
		_by_id[spell.id] = spell
