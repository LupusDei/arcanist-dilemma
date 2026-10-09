class_name Alignment
extends RefCounted
## The arcanist's place on the classic alignment grid, built from choices.
##
## Two axes from -100 to 100:
##   law   +lawful / -chaotic
##   good  +good   / -evil
## Nobody picks an alignment; it is the sum of quest choices. Key quests move it
## by 10 to 15, small choices by 2 to 5, so one bad night doesn't make a villain.

signal changed(law: float, good: float, source: String)

const LIMIT := 100.0
## Beyond this on an axis the arcanist leans that way; inside it they are neutral.
const LEAN_THRESHOLD := 25.0
const AXES: Array[StringName] = [&"law", &"good"]

var law := 0.0
var good := 0.0
## Every shift, oldest first: {law, good, source}. Saved, for the epilogue and debugging.
var history: Array[Dictionary] = []


## Moves the arcanist on the grid. [param source] names what caused it (a quest choice id).
func shift(d_law: float, d_good: float, source := "") -> void:
	if is_zero_approx(d_law) and is_zero_approx(d_good):
		return
	law = clampf(law + d_law, -LIMIT, LIMIT)
	good = clampf(good + d_good, -LIMIT, LIMIT)
	history.append({"law": d_law, "good": d_good, "source": source})
	changed.emit(law, good, source)


func reset() -> void:
	law = 0.0
	good = 0.0
	history.clear()
	changed.emit(law, good, "reset")


func get_axis(axis: StringName) -> float:
	return law if axis == &"law" else good


## &"lawful", &"neutral" or &"chaotic".
func law_lean() -> StringName:
	return lean_for(law, &"lawful", &"chaotic")


## &"good", &"neutral" or &"evil".
func good_lean() -> StringName:
	return lean_for(good, &"good", &"evil")


## One of the nine grid cells, e.g. &"lawful_good" or &"true_neutral".
func archetype() -> StringName:
	return archetype_for(law, good)


func archetype_name() -> String:
	return archetype_display_name(archetype())


func to_dict() -> Dictionary:
	return {"law": law, "good": good, "history": history.duplicate(true)}


func from_dict(data: Dictionary) -> void:
	law = clampf(float(data.get("law", 0.0)), -LIMIT, LIMIT)
	good = clampf(float(data.get("good", 0.0)), -LIMIT, LIMIT)
	history.clear()
	for entry in data.get("history", []):
		if entry is Dictionary:
			history.append(entry)
	changed.emit(law, good, "load")


static func lean_for(value: float, positive: StringName, negative: StringName) -> StringName:
	if value >= LEAN_THRESHOLD:
		return positive
	if value <= -LEAN_THRESHOLD:
		return negative
	return &"neutral"


static func archetype_for(p_law: float, p_good: float) -> StringName:
	var l := lean_for(p_law, &"lawful", &"chaotic")
	var g := lean_for(p_good, &"good", &"evil")
	if l == &"neutral" and g == &"neutral":
		return &"true_neutral"
	return StringName("%s_%s" % [l, g])


static func archetype_display_name(id: StringName) -> String:
	if id == &"true_neutral":
		return "True Neutral"
	var parts := String(id).split("_")
	if parts[0] == "neutral":
		return "Neutral %s" % parts[1].capitalize()
	if parts[1] == "neutral":
		return "%s Neutral" % parts[0].capitalize()
	return "%s %s" % [parts[0].capitalize(), parts[1].capitalize()]


## Short hint of where a choice leans, shown before the player commits,
## e.g. "Lawful", "Chaotic, Good" or "" for no shift.
static func describe_shift(d_law: float, d_good: float) -> String:
	var words: PackedStringArray = []
	if d_law > 0.0:
		words.append("Lawful")
	elif d_law < 0.0:
		words.append("Chaotic")
	if d_good > 0.0:
		words.append("Good")
	elif d_good < 0.0:
		words.append("Evil")
	return ", ".join(words)
