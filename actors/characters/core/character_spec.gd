class_name CharacterSpec
extends RefCounted
## Everything the builder needs to make one character model: the creation
## presets, the outfit, and a few extras NPCs use (age, height, beard, hat).
##
## [method from_any] accepts every shape the other systems hand around, so the
## model never has to know which one it got:
## - a progression CharacterAppearance (anything with to_dict()),
## - its dictionary form {body, name, face, skin, hair_style, hair_color, eyes, build},
## - the creation screen's UiSession.character {name, sex, face, skin, hair, ...} of indices,
## - another CharacterSpec, or null for the default boy.
## Unknown values fall back to the defaults instead of failing.

var body := "boy"
var character_name := ""
var face := "round"
var skin := "fair"
var hair_style := "tousled"
var hair_color := "brown"
var eyes := "brown"
var build := "average"

## "farm", "wizard", "mage" or "sorcerer"; NPC outfits use their own ids (see NpcCatalog).
var outfit := "farm"
## Shirt dye for the farm outfit (CharacterStyle.DYES).
var dye := "linen"
## Path specialization. Stored with the look; outfits don't vary by it yet.
var specialization := ""

## 0 child, 1 young adult (the player), 2 adult, 3 elder.
var age := 1
## Overall scale on top of age.
var height := 1.0
## "", "stubble", "full" or "long".
var beard := ""
## "" (none), "wizard", "top", "straw", "frayed_point" or "cap".
var hat := ""
## Held in the right hand: "", "storm_staff", "walking_stick", "pitchfork", "basket" or "book".
var prop := ""
## Colour overrides on top of the outfit's palette (keys as in CharacterStyle.PALETTES).
var palette: Dictionary = {}
## Outfit pieces added on top of the outfit's own list (see CharacterOutfits.PIECES).
var extra_pieces := PackedStringArray()


static func from_any(source = null) -> CharacterSpec:
	if source is CharacterSpec:
		return (source as CharacterSpec).duplicate_spec()
	var spec := CharacterSpec.new()
	if source == null:
		return spec
	if source is Object and source.has_method("to_dict"):
		source = source.to_dict()
	if source is Dictionary:
		if source.has("sex"):
			spec._apply_ui_dict(source)
		else:
			spec.apply_dict(source)
	return spec


## Default player appearance for a body, with the outfit for a path ("" = farm clothes).
static func player(p_body := "boy", path := "") -> CharacterSpec:
	var spec := CharacterSpec.new()
	spec.body = p_body if p_body in CharacterStyle.BODIES else "boy"
	if p_body == "girl":
		spec.hair_style = "braid"
	spec.set_path(path)
	return spec


## Switches the outfit to a path's clothes. Unknown or empty paths give farm clothes.
func set_path(path: String, p_specialization := "") -> void:
	outfit = path if path in CharacterStyle.OUTFITS else "farm"
	specialization = p_specialization
	if outfit == "wizard":
		hat = "wizard"
	elif outfit == "mage" and body == "girl":
		hat = "top"
	elif hat in ["wizard", "top"]:
		hat = ""


## Applies a dictionary of preset ids (progression's CharacterAppearance.to_dict()
## plus the optional keys of this class). Missing or unknown values keep the current one.
func apply_dict(d: Dictionary) -> void:
	body = _pick(d.get("body", body), CharacterStyle.BODIES, body)
	character_name = str(d.get("name", character_name))
	face = _pick(d.get("face", face), CharacterStyle.FACES, face)
	skin = _pick(d.get("skin", skin), CharacterStyle.SKINS, skin)
	hair_style = _pick(d.get("hair_style", d.get("hair", hair_style)), CharacterStyle.HAIR_STYLES, hair_style)
	hair_color = _pick(d.get("hair_color", hair_color), CharacterStyle.HAIR_COLORS, hair_color)
	eyes = _pick(d.get("eyes", eyes), CharacterStyle.EYES, eyes)
	build = _pick(d.get("build", build), CharacterStyle.BUILDS, build)
	dye = _pick(d.get("dye", dye), CharacterStyle.DYES, dye)
	for key in ["age", "height", "beard", "hat", "prop"]:
		if d.has(key):
			set(key, d[key])
	if d.has("palette"):
		palette = (d["palette"] as Dictionary).duplicate()
	if d.has("extra_pieces"):
		extra_pieces = PackedStringArray(d["extra_pieces"])
	if d.has("outfit"):
		outfit = str(d["outfit"])
		if d.has("specialization"):
			specialization = str(d["specialization"])
	elif d.has("path"):
		set_path(str(d["path"]), str(d.get("specialization", "")))


func to_dict() -> Dictionary:
	return {
		"body": body, "name": character_name, "face": face, "skin": skin,
		"hair_style": hair_style, "hair_color": hair_color, "eyes": eyes, "build": build,
		"outfit": outfit, "dye": dye, "specialization": specialization,
		"age": age, "height": height, "beard": beard, "hat": hat, "prop": prop,
		"palette": palette.duplicate(), "extra_pieces": extra_pieces.duplicate(),
	}


func duplicate_spec() -> CharacterSpec:
	var copy := CharacterSpec.new()
	copy.apply_dict(to_dict())
	return copy


func is_player_outfit() -> bool:
	return outfit in CharacterStyle.OUTFITS


## The creation screen's index dictionary (UiSession.character). Out-of-range indices clamp.
func _apply_ui_dict(d: Dictionary) -> void:
	body = CharacterStyle.BODIES[clampi(int(d.get("sex", 0)), 0, CharacterStyle.BODIES.size() - 1)]
	character_name = str(d.get("name", ""))
	face = _index(CharacterStyle.FACES, d.get("face", 0))
	skin = _index(CharacterStyle.SKINS, d.get("skin", 1))
	hair_style = _index(CharacterStyle.HAIR_STYLES, d.get("hair", 1))
	hair_color = _index(CharacterStyle.HAIR_COLORS, d.get("hair_color", 1))
	eyes = _index(CharacterStyle.EYES, d.get("eyes", 0))
	build = _index(CharacterStyle.BUILDS, d.get("build", 1))


static func _index(table, i) -> String:
	var keys := CharacterStyle.ids(table)
	return keys[clampi(int(i), 0, keys.size() - 1)]


static func _pick(value, table, fallback: String) -> String:
	var s := str(value)
	return s if s in CharacterStyle.ids(table) else fallback
