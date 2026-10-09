class_name ItemDatabase
extends RefCounted
## Loads the item tables in res://data/items/ once and looks things up by id.
## Static and cached, so no autoload is needed.
##
## bases.json     item bases (gear, potions, spellbooks, materials, gold)
## affixes.json   prefixes and suffixes, plus the spell pools for "+N to a spell"
## uniques.json   named gold items
## loot.json      loot sources, biomes, rarity odds and gold, read by LootRoller
## Any ItemBase .tres saved under res://data/items/ is added too.

const ROOT := "res://data/items"

static var _bases: Dictionary = {}
static var _affixes: Dictionary = {}
static var _uniques: Dictionary = {}
static var _loot: Dictionary = {}
static var _spell_pools: Dictionary = {}
static var _rare_names: Dictionary = {}
static var _loaded := false
static var _spell_library: Script
static var _spell_library_checked := false


static func get_base(id: StringName) -> ItemBase:
	_ensure_loaded()
	return _bases.get(id)


static func has_base(id: StringName) -> bool:
	_ensure_loaded()
	return _bases.has(id)


static func all_bases() -> Array[ItemBase]:
	_ensure_loaded()
	var out: Array[ItemBase] = []
	for b in _bases.values():
		out.append(b)
	return out


static func bases_of_kind(kind: int) -> Array[ItemBase]:
	var out: Array[ItemBase] = []
	for b in all_bases():
		if b.kind == kind:
			out.append(b)
	return out


static func get_affix(id: StringName) -> AffixDef:
	_ensure_loaded()
	return _affixes.get(id)


static func all_affixes() -> Array[AffixDef]:
	_ensure_loaded()
	var out: Array[AffixDef] = []
	for a in _affixes.values():
		out.append(a)
	return out


static func get_unique(id: StringName) -> UniqueDef:
	_ensure_loaded()
	return _uniques.get(id)


static func all_uniques() -> Array[UniqueDef]:
	_ensure_loaded()
	var out: Array[UniqueDef] = []
	for u in _uniques.values():
		out.append(u)
	return out


static func loot_config() -> Dictionary:
	_ensure_loaded()
	return _loot


## Spell ids a "+N to a spell" affix or a spellbook can name for a path.
static func spell_pool(path: String) -> Array:
	_ensure_loaded()
	return _spell_pools.get(path, [])


static func rare_name_words() -> Dictionary:
	_ensure_loaded()
	return _rare_names


## A spell's display name from the combat SpellLibrary when it is in the
## project, else the id made readable ("frost_lance" -> "Frost Lance").
static func spell_display_name(spell_id: StringName) -> String:
	if spell_id == &"":
		return ""
	var lib := _spell_library_script()
	if lib:
		var spell = lib.get_spell(spell_id)
		if spell != null and not String(spell.get("display_name")).is_empty():
			return spell.display_name
	return String(spell_id).capitalize()


static func reload() -> void:
	_loaded = false
	_bases.clear()
	_affixes.clear()
	_uniques.clear()
	_ensure_loaded()


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var bases := _read_json(ROOT.path_join("bases.json"))
	for entry in bases.get("bases", []):
		var b := ItemBase.from_dict(entry)
		_bases[b.id] = b
	var affixes := _read_json(ROOT.path_join("affixes.json"))
	for entry in affixes.get("affixes", []):
		var a := AffixDef.from_dict(entry)
		_affixes[a.id] = a
	_spell_pools = affixes.get("spell_pools", {})
	_rare_names = affixes.get("rare_names", {})
	for entry in _read_json(ROOT.path_join("uniques.json")).get("uniques", []):
		var u := UniqueDef.from_dict(entry)
		_uniques[u.id] = u
	_loot = _read_json(ROOT.path_join("loot.json"))
	_scan_resources(ROOT)


static func _scan_resources(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_scan_resources(dir_path.path_join(sub))
	for file in dir.get_files():
		file = file.trim_suffix(".remap")
		if not file.ends_with(".tres"):
			continue
		var res := load(dir_path.path_join(file))
		if res is ItemBase:
			if res.id == &"":
				res.id = StringName(file.get_basename())
			_bases[res.id] = res
		elif res is AffixDef:
			_affixes[res.id] = res
		elif res is UniqueDef:
			_uniques[res.id] = res


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("ItemDatabase: missing %s" % path)
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		push_error("ItemDatabase: %s is not valid JSON" % path)
		return {}
	return data


## The combat system's SpellLibrary, looked up by class name so items do not
## break while combat is not in the project.
static func _spell_library_script() -> Script:
	if not _spell_library_checked:
		_spell_library_checked = true
		for entry in ProjectSettings.get_global_class_list():
			if entry["class"] == &"SpellLibrary":
				_spell_library = load(entry["path"])
	return _spell_library
