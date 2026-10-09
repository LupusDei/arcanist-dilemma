class_name StoryState
extends RefCounted
## Everything the story remembers: flags, alignment and faction standing.
##
## Flags are a flat id -> value store (bool, number or string). Quests, dialogue
## and the world read and write them, e.g. "hat_hidden" or "wolves_killed".
## Standing is a number per faction (-100 to 100), e.g. "wardens" or "unbound".

signal flag_changed(flag: StringName, value: Variant, previous: Variant)
signal standing_changed(faction: StringName, value: float, delta: float)

const STANDING_LIMIT := 100.0

var flags: Dictionary = {}
var standing: Dictionary = {}
var alignment := Alignment.new()


func has_flag(flag: StringName) -> bool:
	return flags.has(flag)


func get_flag(flag: StringName, default: Variant = null) -> Variant:
	return flags.get(flag, default)


## True when the flag is set to something truthy (true, non-zero, non-empty).
func is_set(flag: StringName) -> bool:
	return is_truthy(flags.get(flag))


func set_flag(flag: StringName, value: Variant = true) -> void:
	var previous: Variant = flags.get(flag)
	if flags.has(flag) and typeof(previous) == typeof(value) and previous == value:
		return
	flags[flag] = value
	flag_changed.emit(flag, value, previous)


func clear_flag(flag: StringName) -> void:
	if not flags.has(flag):
		return
	var previous: Variant = flags[flag]
	flags.erase(flag)
	flag_changed.emit(flag, null, previous)


## Adds to a numeric flag (missing counts as 0) and returns the new value.
func add_to_flag(flag: StringName, amount: float) -> float:
	var value := float(flags.get(flag, 0)) + amount
	set_flag(flag, int(value) if is_equal_approx(value, roundf(value)) else value)
	return value


func get_standing(faction: StringName) -> float:
	return float(standing.get(faction, 0.0))


func change_standing(faction: StringName, delta: float) -> void:
	if is_zero_approx(delta):
		return
	var value := clampf(get_standing(faction) + delta, -STANDING_LIMIT, STANDING_LIMIT)
	standing[faction] = value
	standing_changed.emit(faction, value, delta)


func reset() -> void:
	var old := flags.duplicate()
	flags.clear()
	for flag in old:
		flag_changed.emit(flag, null, old[flag])
	standing.clear()
	alignment.reset()


func to_dict() -> Dictionary:
	var flag_data := {}
	for flag in flags:
		flag_data[String(flag)] = flags[flag]
	var standing_data := {}
	for faction in standing:
		standing_data[String(faction)] = standing[faction]
	return {"flags": flag_data, "standing": standing_data, "alignment": alignment.to_dict()}


func from_dict(data: Dictionary) -> void:
	flags.clear()
	var flag_data: Dictionary = data.get("flags", {})
	for flag in flag_data:
		flags[StringName(flag)] = _from_json(flag_data[flag])
	standing.clear()
	var standing_data: Dictionary = data.get("standing", {})
	for faction in standing_data:
		standing[StringName(faction)] = float(standing_data[faction])
	alignment.from_dict(data.get("alignment", {}))
	for flag in flags:
		flag_changed.emit(flag, flags[flag], null)


static func is_truthy(value: Variant) -> bool:
	match typeof(value):
		TYPE_NIL:
			return false
		TYPE_BOOL:
			return value
		TYPE_INT, TYPE_FLOAT:
			return value != 0
		TYPE_STRING, TYPE_STRING_NAME:
			return not String(value).is_empty()
	return true


## JSON turns every number into a float; whole numbers come back as ints.
static func _from_json(value: Variant) -> Variant:
	if typeof(value) == TYPE_FLOAT and is_equal_approx(value, roundf(value)):
		return int(value)
	return value
