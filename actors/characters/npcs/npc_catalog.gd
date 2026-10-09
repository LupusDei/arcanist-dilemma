class_name NpcCatalog
extends RefCounted
## Looks for the story's characters and Millbrook's villagers, as CharacterSpecs.
##
##   CharacterBuilder.build(NpcCatalog.old_man())
##   CharacterBuilder.build(NpcCatalog.tam(Progression.appearance))   # Tam looks like a sibling
##   CharacterBuilder.build(NpcCatalog.villager(seed, "farmer"))

const ROLES := ["farmer", "baker", "elder", "child", "militia", "merchant", "miller"]

const NAMES := {
	"boy": ["Hob", "Edric", "Pell", "Corin", "Bram", "Willem", "Joss", "Aldo"],
	"girl": ["Mira", "Tilda", "Bess", "Agnes", "Nell", "Rosa", "Ivy", "Hesper"],
}


static func ids() -> PackedStringArray:
	return PackedStringArray(["old_man", "tam", "villager"])


## Builds a spec by id: "old_man", "tam" or "villager" (seeded).
static func spec_for(id: String, seed_value := 0, role := "", player_source = null) -> CharacterSpec:
	match id:
		"old_man":
			return old_man()
		"tam":
			return tam(player_source)
		_:
			return villager(seed_value, role)


## The old man in grey (concept take A, the storm-keeper): rune-stitched grey
## cloak, frayed pointed hat, white beard, and a copper-wrapped driftwood
## staff with a storm cloud trapped in its fork. Unnamed until the Greycloak reveal.
static func old_man() -> CharacterSpec:
	var s := CharacterSpec.new()
	s.character_name = "The old man in grey"
	s.body = "boy"
	s.face = "oval"
	s.skin = "fair"
	s.eyes = "blue"
	s.hair_style = "short"
	s.hair_color = "ash"
	s.build = "slight"
	s.age = 3
	s.height = 1.06
	s.beard = "full"
	s.hat = "frayed_point"
	s.outfit = "grey_cloak"
	s.prop = "storm_staff"
	return s


## Tam, the arcanist's younger sibling. Given the player's appearance, Tam
## shares their skin, hair colour and eyes; by default Tam is the other body
## type so the two read apart at a glance.
static func tam(player_source = null, body := "") -> CharacterSpec:
	var player := CharacterSpec.from_any(player_source)
	var s := CharacterSpec.new()
	s.character_name = "Tam"
	s.body = body if body in CharacterStyle.BODIES else ("girl" if player.body == "boy" else "boy")
	s.skin = player.skin
	s.hair_color = player.hair_color
	s.eyes = player.eyes
	s.face = "round"
	s.hair_style = "tousled" if s.body == "boy" else "topknot"
	s.build = "slight"
	s.age = 0
	s.outfit = "farm"
	s.dye = "green"
	s.extra_pieces = PackedStringArray(["neckerchief"])
	s.palette = {"bottom": Color("#7a6648")}
	return s


## A Millbrook villager. The same seed always gives the same person; [param role]
## picks the trade (random when empty).
static func villager(seed_value: int, role := "") -> CharacterSpec:
	var rng := GenRng.stream(seed_value, "villager")
	if not role in ROLES:
		role = ROLES[rng.randi_range(0, ROLES.size() - 1)]
	var s := CharacterSpec.new()
	s.body = CharacterStyle.BODIES[rng.randi_range(0, 1)]
	s.face = _pick(rng, CharacterStyle.FACES)
	s.skin = _pick(rng, CharacterStyle.SKINS)
	s.hair_color = _pick(rng, CharacterStyle.HAIR_COLORS)
	s.eyes = _pick(rng, CharacterStyle.EYES)
	s.build = _pick(rng, CharacterStyle.BUILDS)
	var styles := ["short", "tousled", "shaved"] if s.body == "boy" else ["long", "braid", "topknot", "short"]
	s.hair_style = styles[rng.randi_range(0, styles.size() - 1)]
	s.outfit = "villager"
	s.age = 2
	s.height = rng.randf_range(0.96, 1.05)
	var names: Array = NAMES[s.body]
	s.character_name = names[rng.randi_range(0, names.size() - 1)]
	var shirt := Color.from_hsv(rng.randf_range(0.05, 0.15), rng.randf_range(0.2, 0.45), rng.randf_range(0.55, 0.8))
	var trousers := Color.from_hsv(rng.randf_range(0.08, 0.6), rng.randf_range(0.1, 0.3), rng.randf_range(0.28, 0.45))
	s.palette = {"top": shirt, "bottom": trousers}
	var extra := PackedStringArray()
	match role:
		"farmer":
			s.hat = "straw"
			s.prop = "pitchfork"
			extra.append("vest")
			s.palette["vest"] = Color("#6a5236")
		"baker":
			s.build = "sturdy"
			s.hat = "cap"
			s.palette["hat"] = Color("#e9e4d8")
			extra.append("apron")
		"elder":
			s.age = 3
			s.prop = "walking_stick"
			extra.append("shawl")
			if s.body == "girl":
				extra.append("long_skirt")
				s.hair_style = "topknot"
			else:
				s.beard = "long" if rng.randf() < 0.5 else "full"
		"child":
			s.age = 0
			s.height = rng.randf_range(0.92, 1.05)
			s.palette["top"] = Color.from_hsv(rng.randf(), 0.45, 0.75)
			extra.append("neckerchief")
		"militia":
			s.build = "sturdy"
			s.hat = "cap"
			s.palette["hat"] = Color("#5a4632")
			extra.append("jerkin")
			if s.body == "boy" and rng.randf() < 0.5:
				s.beard = "stubble"
		"merchant":
			s.prop = "basket"
			extra.append("vest")
			s.palette["vest"] = Color.from_hsv(rng.randf(), 0.5, 0.45)
			if s.body == "girl":
				extra.append("long_skirt")
		"miller":
			s.hat = "cap"
			s.palette["hat"] = Color("#cfc6b0")
			s.palette["top"] = Color("#dcd3bd")
			extra.append("apron")
			s.palette["apron"] = Color("#f0ece2")
	s.extra_pieces = extra
	s.set_meta("role", role)
	return s


static func _pick(rng: RandomNumberGenerator, table) -> String:
	var keys := CharacterStyle.ids(table)
	return keys[rng.randi_range(0, keys.size() - 1)]
