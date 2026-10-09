class_name CharacterStyle
extends RefCounted
## Look tables for the character models: what each creation preset means in
## geometry and colour, the outfit palettes, and the toon material every part
## uses.
##
## The preset lists use the ids from res://data/progression/appearance_presets.json
## and are in the same order as ui/data/ui_character_presets.gd, so a creation
## screen index, a saved preset id and a model part all line up. Colours match
## both files. This file adds the shape numbers the model needs.

const BODIES := ["boy", "girl"]

## width/height scale the skull, jaw > 0 narrows the chin, jaw < 0 squares it.
const FACES := {
	"round": {"width": 1.0, "height": 0.98, "jaw": 0.0},
	"oval": {"width": 0.9, "height": 1.06, "jaw": 0.06},
	"heart": {"width": 0.96, "height": 1.02, "jaw": 0.2},
	"square": {"width": 1.0, "height": 1.0, "jaw": -0.14},
}

const SKINS := {
	"porcelain": Color("#f7d9c2"),
	"fair": Color("#edc29e"),
	"olive": Color("#cc9e73"),
	"tan": Color("#b28057"),
	"brown": Color("#855738"),
	"deep": Color("#543624"),
}

const HAIR_STYLES := ["short", "tousled", "long", "braid", "topknot", "shaved"]

const HAIR_COLORS := {
	"black": Color("#141212"),
	"brown": Color("#54331c"),
	"auburn": Color("#8c381a"),
	"blond": Color("#dbb266"),
	"ash": Color("#b2ada3"),
	"ember": Color("#d9521f"),
}

const EYES := {
	"brown": Color("#613b1f"),
	"hazel": Color("#806b33"),
	"green": Color("#408c4c"),
	"blue": Color("#407acc"),
	"grey": Color("#8c949e"),
	"violet": Color("#8c59cc"),
}

## shoulders scales shoulder span and chest width; limbs scales arm and leg thickness.
const BUILDS := {
	"slight": {"shoulders": 0.86, "limbs": 0.88, "waist": 0.92},
	"average": {"shoulders": 1.0, "limbs": 1.0, "waist": 1.0},
	"sturdy": {"shoulders": 1.16, "limbs": 1.14, "waist": 1.12},
}

## Outfits. "farm" is the level 1 look from the concept turnaround; the three
## paths follow the batch 2 lineup (blue robe with gold runes, Wayfarer mage with
## frost and a clock ripple, red and gold sorcerer with violet lightning).
const OUTFITS := ["farm", "wizard", "mage", "sorcerer"]

## Shirt dyes for the farm outfit (the concept sheet's linen, blue, green and red).
const DYES := {
	"linen": Color("#c9ad7f"),
	"blue": Color("#5b7fa8"),
	"green": Color("#6f8a55"),
	"red": Color("#a8493a"),
}

const PALETTES := {
	"farm": {
		"top": Color("#c9ad7f"), "bottom": Color("#6b6a58"), "boots": Color("#6e4428"),
		"leather": Color("#5a3820"), "metal": Color("#c9a24f"), "accent": Color("#9fd4ff"),
	},
	"wizard": {
		"top": Color("#2b2f5c"), "bottom": Color("#24264a"), "boots": Color("#1f2038"),
		"leather": Color("#4a3426"), "metal": Color("#e8c25a"), "accent": Color("#ffd466"),
		"hat": Color("#272a52"),
	},
	"mage": {
		"top": Color("#55705f"), "bottom": Color("#4f5646"), "boots": Color("#5b3b25"),
		"leather": Color("#6b4528"), "metal": Color("#b98a4a"), "accent": Color("#8ff0ff"),
		"hat": Color("#3f6a45"), "pack": Color("#4d5a3c"),
	},
	"sorcerer": {
		"top": Color("#8e2a22"), "bottom": Color("#5b3622"), "boots": Color("#4a2c1c"),
		"leather": Color("#3d2618"), "metal": Color("#d9a845"), "accent": Color("#b77cff"),
	},
}

## Magic colour per path, used by the cast effect and hand glow.
const MAGIC := {
	"farm": Color("#9fd4ff"),
	"wizard": Color("#ffd466"),
	"mage": Color("#8ff0ff"),
	"sorcerer": Color("#b77cff"),
}


## A toon-shaded material in the same style as the enemies (toon diffuse and
## specular with a soft rim). Every part gets its own copy so a rig can flash
## or tint without touching other characters.
static func material(color: Color, emission := 0.0, rim := 0.2) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.82
	# Low specular: broad toon highlights wash cloth out to white under the meadow's bright sun.
	m.metallic_specular = 0.12
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_TOON
	m.rim_enabled = rim > 0.0
	m.rim = rim
	m.rim_tint = 0.6
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	return m


## Unshaded glowing material for runes, sparks and lightning.
static func glow(color: Color, energy := 3.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if color.a < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func ids(table) -> PackedStringArray:
	if table is Array:
		return PackedStringArray(table)
	return PackedStringArray((table as Dictionary).keys())
