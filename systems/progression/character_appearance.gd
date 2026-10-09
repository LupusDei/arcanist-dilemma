class_name CharacterAppearance
extends RefCounted
## Who the player made at character creation: boy or girl, a name, and one
## preset for each look option. Preset ids come from
## res://data/progression/appearance_presets.json.

signal changed

var body := "boy"
var character_name := ""
var face := ""
var skin := ""
var hair_style := ""
var hair_color := ""
var eyes := ""
var build := ""

## Maps each field to its preset list in appearance_presets.json.
const PRESET_FIELDS := {
	"face": "faces",
	"skin": "skins",
	"hair_style": "hair_styles",
	"hair_color": "hair_colors",
	"eyes": "eyes",
	"build": "builds",
}


## A complete appearance with the first preset in every list.
static func create_default(p_body := "boy") -> CharacterAppearance:
	var a := CharacterAppearance.new()
	a.body = p_body
	a.character_name = ProgressionData.appearance()["default_names"][p_body][0]
	for field in PRESET_FIELDS:
		a.set(field, a.options_for(field)[0])
	return a


## A random but valid appearance, for the "randomize" button.
static func create_random(rng: RandomNumberGenerator) -> CharacterAppearance:
	var bodies := ProgressionData.preset_ids("bodies")
	var a := create_default(bodies[rng.randi_range(0, bodies.size() - 1)])
	var names: Array = ProgressionData.appearance()["default_names"][a.body]
	a.character_name = names[rng.randi_range(0, names.size() - 1)]
	for field in PRESET_FIELDS:
		var opts := a.options_for(field)
		a.set(field, opts[rng.randi_range(0, opts.size() - 1)])
	return a


## Preset ids allowed for [param field] given the current body (hair styles are body-specific).
func options_for(field: String) -> PackedStringArray:
	if field == "body":
		return ProgressionData.preset_ids("bodies")
	var out := PackedStringArray()
	for entry in ProgressionData.appearance().get(PRESET_FIELDS.get(field, ""), []):
		if entry.has("bodies") and not body in entry["bodies"]:
			continue
		out.append(entry["id"])
	return out


## Sets one field after checking it against the presets. Returns false if the value is not allowed.
func set_option(field: String, value: String) -> bool:
	if not value in options_for(field):
		return false
	set(field, value)
	if field == "body" and not hair_style in options_for("hair_style"):
		hair_style = options_for("hair_style")[0]
	changed.emit()
	return true


## Steps a field to the next (or previous) preset, wrapping around. For arrow buttons in the creator.
func cycle_option(field: String, step := 1) -> String:
	var opts := options_for(field)
	var i := opts.find(get(field))
	set_option(field, opts[posmod(i + step, opts.size())])
	return get(field)


func set_character_name(value: String) -> bool:
	var cleaned := value.strip_edges()
	if not is_valid_name(cleaned):
		return false
	character_name = cleaned
	changed.emit()
	return true


static func is_valid_name(value: String) -> bool:
	var cleaned := value.strip_edges()
	var max_len: int = ProgressionData.appearance()["name_max_length"]
	return not cleaned.is_empty() and cleaned.length() <= max_len


## Human-readable problems, empty when the appearance is ready to start a game.
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if not body in options_for("body"):
		problems.append("unknown body '%s'" % body)
	if not is_valid_name(character_name):
		problems.append("name must be 1 to %d characters" % ProgressionData.appearance()["name_max_length"])
	for field in PRESET_FIELDS:
		if not get(field) in options_for(field):
			problems.append("unknown %s '%s'" % [field, get(field)])
	return problems


## The preset entry (name, color, scale...) currently chosen for [param field].
func preset(field: String) -> Dictionary:
	for entry in ProgressionData.appearance().get(PRESET_FIELDS.get(field, ""), []):
		if entry["id"] == get(field):
			return entry
	return {}


func to_dict() -> Dictionary:
	var d := {"body": body, "name": character_name}
	for field in PRESET_FIELDS:
		d[field] = get(field)
	return d


## Maps between this class and the creation screen's UiSession.character
## ({name, sex, face, skin, hair, hair_color, eyes, build} as preset indices).
const UI_KEYS := {"face": "face", "skin": "skin", "hair": "hair_style", "hair_color": "hair_color", "eyes": "eyes", "build": "build"}


## Builds an appearance from the creation screen's index dictionary. Out-of-range indices are clamped.
static func from_ui_dict(d: Dictionary) -> CharacterAppearance:
	var bodies := ProgressionData.preset_ids("bodies")
	var a := create_default(bodies[clampi(int(d.get("sex", 0)), 0, bodies.size() - 1)])
	if is_valid_name(str(d.get("name", ""))):
		a.character_name = str(d["name"]).strip_edges()
	for ui_key in UI_KEYS:
		var opts := a.options_for(UI_KEYS[ui_key])
		a.set(UI_KEYS[ui_key], opts[clampi(int(d.get(ui_key, 0)), 0, opts.size() - 1)])
	return a


## The creation screen's index dictionary for this appearance, e.g. for UiSession.character after a load.
func to_ui_dict() -> Dictionary:
	var d := {"name": character_name, "sex": maxi(options_for("body").find(body), 0)}
	for ui_key in UI_KEYS:
		d[ui_key] = maxi(options_for(UI_KEYS[ui_key]).find(get(UI_KEYS[ui_key])), 0)
	return d


static func from_dict(d: Dictionary) -> CharacterAppearance:
	var a := CharacterAppearance.new()
	a.apply_dict(d)
	return a


## Replaces this instance's fields in place. Unknown presets fall back to the first option.
func apply_dict(d: Dictionary) -> void:
	var b: String = d.get("body", "boy")
	var defaults := create_default(b if b in ProgressionData.preset_ids("bodies") else "boy")
	body = defaults.body
	var saved_name: String = str(d.get("name", ""))
	character_name = saved_name.strip_edges() if is_valid_name(saved_name) else defaults.character_name
	for field in PRESET_FIELDS:
		var value: String = str(d.get(field, ""))
		set(field, value if value in options_for(field) else defaults.get(field))
	changed.emit()
