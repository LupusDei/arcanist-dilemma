class_name ProgressionData
extends RefCounted
## Read-only access to the tuning tables in res://data/progression/.
##
## Each JSON file is parsed once and cached. Everything a designer might tune
## (XP curve, points per level, paths, talents, appearance presets) lives in
## those files, not in code.

const LEVELING_PATH := "res://data/progression/leveling.json"
const ATTRIBUTES_PATH := "res://data/progression/attributes.json"
const PATHS_PATH := "res://data/progression/paths.json"
const APPEARANCE_PATH := "res://data/progression/appearance_presets.json"

const ATTRIBUTES: Array[StringName] = [&"strength", &"vitality", &"dexterity", &"intelligence", &"wisdom"]

static var _cache: Dictionary = {}


static func leveling() -> Dictionary:
	return _load(LEVELING_PATH)


static func attributes() -> Dictionary:
	return _load(ATTRIBUTES_PATH)


static func paths() -> Dictionary:
	return _load(PATHS_PATH)


static func appearance() -> Dictionary:
	return _load(APPEARANCE_PATH)


static func max_level(replay_unlocked: bool) -> int:
	return int(leveling()["replay_max_level" if replay_unlocked else "max_level"])


## XP needed to go from [param level] to the next level, or 0 past the table.
static func xp_to_next(level: int) -> int:
	var table: Array = leveling()["xp_to_next"]
	if level < 1 or level > table.size():
		return 0
	return int(table[level - 1])


static func talent_row_levels() -> Array[int]:
	var out: Array[int] = []
	for l in leveling()["talent_row_levels"]:
		out.append(int(l))
	return out


static func base_attribute() -> int:
	return int(attributes()["base_value"])


static func path_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for p in paths()["paths"]:
		out.append(p["id"])
	return out


## The path entry for [param path_id], or an empty dictionary.
static func get_path_data(path_id: String) -> Dictionary:
	for p in paths()["paths"]:
		if p["id"] == path_id:
			return p
	return {}


## The specialization entry for [param spec_id] within [param path_id], or an empty dictionary.
static func get_specialization(path_id: String, spec_id: String) -> Dictionary:
	for s in get_path_data(path_id).get("specializations", []):
		if s["id"] == spec_id:
			return s
	return {}


## The talent row unlocked at [param row_level] for a specialization, or an empty dictionary.
static func get_talent_row(path_id: String, spec_id: String, row_level: int) -> Dictionary:
	for row in get_specialization(path_id, spec_id).get("talent_rows", []):
		if int(row["level"]) == row_level:
			return row
	return {}


## Suggested attribute weights for auto-assign: the specialization's, else the path's, else even.
static func suggested_weights(path_id: String, spec_id: String) -> Dictionary:
	var spec := get_specialization(path_id, spec_id)
	if spec.has("suggested_weights"):
		return spec["suggested_weights"]
	var path := get_path_data(path_id)
	if path.has("suggested_weights"):
		return path["suggested_weights"]
	return paths()["unpathed"]["suggested_weights"]


## Ids of one appearance preset list ("faces", "skins", "hair_styles", ...).
static func preset_ids(category: String) -> PackedStringArray:
	var out := PackedStringArray()
	for entry in appearance().get(category, []):
		out.append(entry["id"])
	return out


static func _load(path: String) -> Dictionary:
	if _cache.has(path):
		return _cache[path]
	var text := FileAccess.get_file_as_string(path)
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("ProgressionData: could not parse %s" % path)
		data = {}
	_cache[path] = data
	return data
