class_name ProgressionSave
extends RefCounted
## Saves and loads a character (appearance + progression) as JSON under user://saves/.
##
## Other systems can store their own state in the same file through the
## [code]extra[/code] dictionary, keyed by system name (e.g. "inventory").
## Files are written to a temp file first and then renamed, so a crash mid-save
## never leaves a half-written slot.

const SAVE_DIR := "user://saves"
const FORMAT_VERSION := 1


static func slot_path(slot: int) -> String:
	return "%s/slot_%d.json" % [SAVE_DIR, slot]


static func to_dict(appearance: CharacterAppearance, progression: CharacterProgression,
		play_time_seconds := 0.0, extra := {}) -> Dictionary:
	return {
		"version": FORMAT_VERSION,
		"saved_at": Time.get_datetime_string_from_system(true),
		"play_time_seconds": play_time_seconds,
		"appearance": appearance.to_dict(),
		"progression": progression.to_dict(),
		"extra": extra,
	}


static func save_to_file(path: String, appearance: CharacterAppearance,
		progression: CharacterProgression, play_time_seconds := 0.0, extra := {}) -> Error:
	var err := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if err != OK:
		return err
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(to_dict(appearance, progression, play_time_seconds, extra), "\t"))
	file.close()
	return DirAccess.rename_absolute(tmp, path)


## Reads a save file. Returns an empty dictionary if it is missing or unreadable;
## otherwise the raw save dictionary (see [method to_dict]), with the version checked.
static func read_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		push_error("ProgressionSave: %s is not valid JSON" % path)
		return {}
	if int(data.get("version", 0)) > FORMAT_VERSION:
		push_error("ProgressionSave: %s is from a newer version (%s)" % [path, data.get("version")])
		return {}
	return data


## Loads a save into existing objects in place, so their signal listeners stay connected.
## Returns the save's [code]extra[/code] dictionary, or null if the file could not be read.
static func load_into(path: String, appearance: CharacterAppearance, progression: CharacterProgression) -> Variant:
	var data := read_file(path)
	if data.is_empty():
		return null
	appearance.apply_dict(data.get("appearance", {}))
	progression.apply_dict(data.get("progression", {}))
	return data.get("extra", {})


## A short summary of each existing slot for a load menu: slot, name, level, path, saved_at.
static func list_slots(max_slots := 10) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for slot in max_slots:
		var data := read_file(slot_path(slot))
		if data.is_empty():
			continue
		var prog: Dictionary = data.get("progression", {})
		out.append({
			"slot": slot,
			"name": data.get("appearance", {}).get("name", ""),
			"level": int(prog.get("level", 1)),
			"path": prog.get("path", ""),
			"specialization": prog.get("specialization", ""),
			"saved_at": data.get("saved_at", ""),
			"play_time_seconds": float(data.get("play_time_seconds", 0.0)),
		})
	return out


static func delete_slot(slot: int) -> Error:
	if not FileAccess.file_exists(slot_path(slot)):
		return ERR_FILE_NOT_FOUND
	return DirAccess.remove_absolute(slot_path(slot))
