class_name UiCharacterPresets
extends RefCounted
## Look presets for character creation. Kept short on purpose (boy or girl,
## a name, and a handful of presets), per the design doc. The chosen indices
## are stored in UiSession.character for the player model to read.

const SEXES := ["Boy", "Girl"]

const FACES := [
	{"name": "Round", "width": 1.0, "height": 0.98, "jaw": 0.0},
	{"name": "Oval", "width": 0.88, "height": 1.06, "jaw": 0.0},
	{"name": "Heart", "width": 0.95, "height": 1.02, "jaw": 0.18},
	{"name": "Square", "width": 1.0, "height": 1.0, "jaw": -0.12},
]

const SKINS := [
	{"name": "Porcelain", "color": Color(0.97, 0.85, 0.76)},
	{"name": "Fair", "color": Color(0.93, 0.76, 0.62)},
	{"name": "Olive", "color": Color(0.8, 0.62, 0.45)},
	{"name": "Tan", "color": Color(0.7, 0.5, 0.34)},
	{"name": "Brown", "color": Color(0.52, 0.34, 0.22)},
	{"name": "Deep", "color": Color(0.33, 0.21, 0.14)},
]

const HAIR_STYLES := ["Short", "Tousled", "Long", "Braid", "Topknot", "Shaved"]

const HAIR_COLORS := [
	{"name": "Black", "color": Color(0.08, 0.07, 0.07)},
	{"name": "Brown", "color": Color(0.33, 0.2, 0.11)},
	{"name": "Auburn", "color": Color(0.55, 0.22, 0.1)},
	{"name": "Blond", "color": Color(0.86, 0.7, 0.4)},
	{"name": "Ash", "color": Color(0.7, 0.68, 0.64)},
	{"name": "Ember", "color": Color(0.85, 0.32, 0.12)},
]

const EYES := [
	{"name": "Brown", "color": Color(0.38, 0.23, 0.12)},
	{"name": "Hazel", "color": Color(0.5, 0.42, 0.2)},
	{"name": "Green", "color": Color(0.25, 0.55, 0.3)},
	{"name": "Blue", "color": Color(0.25, 0.48, 0.8)},
	{"name": "Grey", "color": Color(0.55, 0.58, 0.62)},
	{"name": "Violet", "color": Color(0.55, 0.35, 0.8)},
]

const BUILDS := [
	{"name": "Slight", "shoulders": 0.82},
	{"name": "Average", "shoulders": 1.0},
	{"name": "Sturdy", "shoulders": 1.18},
]

## Selector rows on the creation screen: key in the character dictionary,
## label, and how many options it has.
const SELECTORS := [
	["face", "Face"],
	["skin", "Skin"],
	["hair", "Hair"],
	["hair_color", "Hair colour"],
	["eyes", "Eyes"],
	["build", "Build"],
]


static func option_count(key: String) -> int:
	match key:
		"sex":
			return SEXES.size()
		"face":
			return FACES.size()
		"skin":
			return SKINS.size()
		"hair":
			return HAIR_STYLES.size()
		"hair_color":
			return HAIR_COLORS.size()
		"eyes":
			return EYES.size()
		"build":
			return BUILDS.size()
	return 1


static func option_name(key: String, index: int) -> String:
	match key:
		"sex":
			return SEXES[index]
		"face":
			return FACES[index].name
		"skin":
			return SKINS[index].name
		"hair":
			return HAIR_STYLES[index]
		"hair_color":
			return HAIR_COLORS[index].name
		"eyes":
			return EYES[index].name
		"build":
			return BUILDS[index].name
	return ""


static func default_character() -> Dictionary:
	return {"name": "", "sex": 0, "face": 0, "skin": 1, "hair": 1, "hair_color": 1, "eyes": 0, "build": 1}


static func random_character(rng: RandomNumberGenerator, keep_name := "") -> Dictionary:
	var c := {"name": keep_name}
	for key in ["sex", "face", "skin", "hair", "hair_color", "eyes", "build"]:
		c[key] = rng.randi_range(0, option_count(key) - 1)
	return c
