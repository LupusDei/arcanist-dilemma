class_name CharacterOutfits
extends RefCounted
## Clothes, hats, held props and magic effects, added on top of the body that
## CharacterBuilder makes. Each outfit is a list of pieces, so NPCs mix and
## match the same pieces with their own colours.

const PIECES := {
	"farm": ["collar", "belt", "satchel", "cuffs"],
	"wizard": ["robe", "wide_sleeves", "belt", "rune_trim", "book"],
	"mage": ["coat_skirt", "belt", "backpack", "clock_pendant", "frost_pauldron", "cuffs"],
	"sorcerer": ["coat_skirt", "gold_trim", "sash", "high_collar"],
	# NPCs (see NpcCatalog).
	"grey_cloak": ["cloak", "hood", "fringe_sleeves", "belt", "strap", "pouches", "rune_stitches"],
	"villager": ["collar", "belt"],
}

## Palettes for NPC outfits; the player's are in CharacterStyle.PALETTES.
const NPC_PALETTES := {
	"grey_cloak": {
		"top": Color("#62676e"), "bottom": Color("#3a3d42"), "boots": Color("#5a3a26"),
		"leather": Color("#5b3a24"), "metal": Color("#b8763f"), "accent": Color("#cfe6ff"),
		"hat": Color("#575c63"), "trim": Color("#d8c89a"),
	},
	"villager": {
		"top": Color("#b59a74"), "bottom": Color("#5a5446"), "boots": Color("#5e3d26"),
		"leather": Color("#5a3820"), "metal": Color("#a88a4a"), "accent": Color("#9fd4ff"),
		"hat": Color("#d8bd73"), "apron": Color("#d9d2bf"), "shawl": Color("#7b5a72"),
	},
}


static func palette_for(spec: CharacterSpec) -> Dictionary:
	var base: Dictionary = CharacterStyle.PALETTES.get(spec.outfit, NPC_PALETTES.get(spec.outfit, CharacterStyle.PALETTES["farm"]))
	var pal := base.duplicate()
	if spec.outfit == "farm":
		pal["top"] = CharacterStyle.DYES.get(spec.dye, CharacterStyle.DYES["linen"])
	for key in spec.palette:
		pal[key] = spec.palette[key]
	return pal


static func pieces_for(spec: CharacterSpec) -> PackedStringArray:
	var out := PackedStringArray(PIECES.get(spec.outfit, PIECES["villager"]))
	for p in spec.extra_pieces:
		if not p in out:
			out.append(p)
	return out


static func dress(rig: CharacterRig, spec: CharacterSpec, d: Dictionary, pal: Dictionary) -> void:
	var B := CharacterBuilder
	var w: float = d.waist
	var sh: float = d.shoulders
	var leather: Color = pal.leather
	var metal: Color = pal.metal
	for piece in pieces_for(spec):
		# The sculpted body already wears the collar, belt and boot cuffs.
		if rig.sculpted and piece in ["collar", "belt", "cuffs"]:
			continue
		match piece:
			"collar":
				for sx in [-1.0, 1.0]:
					var c := B.part(rig, "Chest", "Collar" + _side(sx), B.prism(Vector3(0.08, 0.07, 0.02)), Vector3(0.045 * sx, d.chest - 0.01, -0.1), pal.top.lightened(0.08))
					c.rotation = Vector3(-0.5, 0, 0.5 * sx)
			"belt":
				B.part(rig, "Spine", "Belt", B.cylinder(0.142 * w, 0.142 * w, 0.045), Vector3(0, 0.03, 0), leather, Vector3(1, 1, 0.8))
				B.part(rig, "Spine", "Buckle", B.box(Vector3(0.05, 0.04, 0.015)), Vector3(0, 0.03, -0.118 * 0.8 - 0.005), metal)
			"satchel":
				# Strap from the right shoulder to the left hip, bag on the left hip.
				var strap := B.part(rig, "Chest", "SatchelStrap", B.box(Vector3(0.045, 0.52, 0.02)), Vector3(0.0, d.chest * 0.42, -0.135), leather)
				strap.rotation.z = -0.62
				var strap_back := B.part(rig, "Chest", "SatchelStrapBack", B.box(Vector3(0.045, 0.52, 0.02)), Vector3(0.0, d.chest * 0.42, 0.135), leather)
				strap_back.rotation.z = 0.62
				B.part(rig, "Hips", "Satchel", B.box(Vector3(0.05, 0.15, 0.17)), Vector3(-0.17 * w, -0.04, 0.0), leather.lightened(0.08))
				B.part(rig, "Hips", "SatchelFlap", B.box(Vector3(0.055, 0.07, 0.175)), Vector3(-0.172 * w, 0.0, 0.0), leather.darkened(0.1))
			"cuffs":
				for side in ["L", "R"]:
					B.part(rig, "Knee" + side, "TrouserCuff" + side, B.cylinder(d.limb_r * 1.32, d.limb_r * 1.45, 0.06), Vector3(0, -d.shin * 0.48, 0), pal.bottom.lightened(0.1))
			"robe":
				# A long robe from the chest to the ankles, hung on the hips so legs swing inside it.
				B.part(rig, "Hips", "Robe", B.cylinder(0.15 * w, 0.33, d.hip_y - 0.06, 20), Vector3(0, -(d.hip_y - 0.06) * 0.5 + 0.08, 0.0), pal.top, Vector3(1, 1, 0.85))
				B.part(rig, "Chest", "RobeOverlap", B.cylinder(0.12 * sh, 0.17 * w, d.chest + 0.02), Vector3(0, d.chest * 0.45, 0), pal.top, Vector3(1.15, 1, 0.82))
				B.part(rig, "Chest", "RobeOpening", B.box(Vector3(0.05, d.chest * 0.8, 0.01)), Vector3(0, d.chest * 0.5, -0.14), Color("#c9c3b6"))
			"wide_sleeves":
				for side in ["L", "R"]:
					B.part(rig, "Elbow" + side, "Sleeve" + side, B.cylinder(d.limb_r * 1.0, d.limb_r * 2.1, d.forearm * 0.95), Vector3(0, -d.forearm * 0.55, 0), pal.top)
			"rune_trim":
				var gold := CharacterStyle.glow(Color(pal.accent, 1.0), 1.6)
				var hem := B.part(rig, "Hips", "HemTrim", B.torus(0.31, 0.335), Vector3(0, -(d.hip_y - 0.06) + 0.1, 0), pal.accent, Vector3(1, 1, 0.85))
				hem.material_override = gold
				# Golden rune glyphs stitched down the robe front.
				for i in 5:
					var glyph := B.part(rig, "Hips", "Rune%d" % i, B.box(Vector3(0.05, 0.05, 0.006)), Vector3(0.1 * (1 if i % 2 == 0 else -1), -0.08 - i * 0.12, -0.2 - i * 0.022), pal.accent)
					glyph.rotation = Vector3(0.12, 0, 0.785)
					glyph.material_override = gold
					var bar := B.part(rig, "Hips", "RuneBar%d" % i, B.box(Vector3(0.008, 0.07, 0.006)), glyph.position + Vector3(0, 0, -0.002), pal.accent)
					bar.material_override = gold
			"book":
				B.part(rig, "Hips", "Book", B.box(Vector3(0.05, 0.17, 0.13)), Vector3(0.19 * w, -0.06, 0.02), Color("#4a2e1e"))
				var rune := B.part(rig, "Hips", "BookRune", B.box(Vector3(0.006, 0.05, 0.05)), Vector3(0.217 * w, -0.06, 0.02), pal.accent)
				rune.material_override = CharacterStyle.glow(pal.accent, 2.0)
			"coat_skirt":
				var long := spec.outfit == "sorcerer"
				var length: float = d.thigh * (0.95 if long else 0.6)
				B.part(rig, "Hips", "CoatSkirt", B.cylinder(0.16 * w, 0.24, length, 18), Vector3(0, -length * 0.5 + 0.05, 0.01), pal.top.darkened(0.05), Vector3(1, 1, 0.85))
				B.part(rig, "Hips", "CoatSplit", B.box(Vector3(0.03, length * 0.9, 0.012)), Vector3(0, -length * 0.5 + 0.02, -0.205), pal.bottom.darkened(0.2))
			"backpack":
				B.part(rig, "Chest", "Pack", B.box(Vector3(0.28 * sh, 0.34, 0.15)), Vector3(0, d.chest * 0.5, 0.2), pal.get("pack", leather))
				B.part(rig, "Chest", "PackFlap", B.box(Vector3(0.29 * sh, 0.12, 0.16)), Vector3(0, d.chest * 0.5 + 0.13, 0.205), pal.get("pack", leather).darkened(0.15))
				var roll := B.part(rig, "Chest", "Bedroll", B.cylinder(0.065, 0.065, 0.36 * sh), Vector3(0, d.chest * 0.5 + 0.24, 0.2), Color("#8a6a45"))
				roll.rotation.z = PI / 2
				for sx in [-1.0, 1.0]:
					B.part(rig, "Chest", "PackStrap" + _side(sx), B.box(Vector3(0.035, 0.3, 0.02)), Vector3(0.08 * sx, d.chest * 0.5, -0.13), leather)
			"clock_pendant":
				var chest_front := -0.135
				_set_prop(B.part(rig, "Chest", "Clock", B.cylinder(0.045, 0.045, 0.012), Vector3(0, d.chest * 0.3, chest_front - 0.01), metal), "rotation.x", PI / 2)
				var face := B.part(rig, "Chest", "ClockFace", B.cylinder(0.036, 0.036, 0.004), Vector3(0, d.chest * 0.3, chest_front - 0.018), Color("#efe6cf"))
				face.rotation.x = PI / 2
				var hand := B.part(rig, "Chest", "ClockHand", B.box(Vector3(0.004, 0.03, 0.003)), Vector3(0.006, d.chest * 0.3 + 0.01, chest_front - 0.022), Color("#2a2420"))
				hand.rotation.z = -0.6
			"frost_pauldron":
				var ice := CharacterStyle.glow(Color(pal.accent, 0.85), 1.4)
				for i in 4:
					var shard := B.part(rig, "Chest", "Frost%d" % i, B.prism(Vector3(0.04, 0.12 - i * 0.015, 0.04)), Vector3(-d.shoulder_x - 0.02 + i * 0.03, d.chest + 0.02, -0.02 + (i % 2) * 0.05), pal.accent)
					shard.rotation = Vector3(0.2 * (i % 2), 0, 0.5 - i * 0.3)
					shard.material_override = ice
			"gold_trim":
				var gold: Color = pal.metal
				B.part(rig, "Chest", "FrontTrim", B.box(Vector3(0.04, d.chest * 0.95, 0.01)), Vector3(0, d.chest * 0.5, -0.137), gold)
				for i in 3:
					B.part(rig, "Chest", "Frog%d" % i, B.box(Vector3(0.11, 0.014, 0.012)), Vector3(0, d.chest * (0.25 + i * 0.22), -0.138), gold)
				for side in ["L", "R"]:
					B.part(rig, "Elbow" + side, "GoldCuff" + side, B.cylinder(d.limb_r * 1.2, d.limb_r * 1.25, 0.05), Vector3(0, -d.forearm + 0.05, 0), gold)
					B.part(rig, "Chest", "Epaulette" + side, B.sphere(0.08), Vector3(d.shoulder_x * (-1 if side == "L" else 1), d.chest - 0.035, 0), gold, Vector3(1.1, 0.5, 1.1))
			"sash":
				B.part(rig, "Spine", "Sash", B.cylinder(0.145 * w, 0.148 * w, 0.07), Vector3(0, 0.04, 0), Color("#5b2a1c"), Vector3(1, 1, 0.8))
				B.part(rig, "Spine", "SashKnot", B.sphere(0.035), Vector3(0.1, 0.04, -0.1), Color("#5b2a1c"))
				B.part(rig, "Spine", "SashTail", B.box(Vector3(0.04, 0.16, 0.012)), Vector3(0.11, -0.05, -0.105), Color("#5b2a1c"))
			"high_collar":
				B.part(rig, "Chest", "HighCollar", B.cylinder(0.085, 0.1, 0.08), Vector3(0, d.chest + 0.01, 0.005), pal.metal)
			"cloak":
				# The old man's rune-stitched grey cloak, to below the knee.
				var length: float = d.hip_y + d.pelvis - d.shin * 0.45
				B.part(rig, "Chest", "Cloak", B.cylinder(0.17 * sh, 0.34, length, 20), Vector3(0, d.chest - length * 0.5 + 0.02, 0.01), pal.top, Vector3(1.05, 1, 0.82))
				var fringe := B.part(rig, "Chest", "CloakFringe", B.cylinder(0.345, 0.36, 0.04, 20), Vector3(0, d.chest - length + 0.04, 0.01), pal.top.lightened(0.1), Vector3(1.05, 1, 0.82))
				fringe.transparency = 0.15
				B.part(rig, "Chest", "CloakOpening", B.box(Vector3(0.04, length * 0.6, 0.01)), Vector3(0, d.chest - length * 0.62, -0.28), pal.bottom)
			"hood":
				B.part(rig, "Chest", "Hood", B.torus(0.07, 0.15), Vector3(0, d.chest + 0.02, 0.03), pal.top, Vector3(1.0, 1.4, 1.0))
				B.part(rig, "Chest", "HoodBack", B.sphere(0.12), Vector3(0, d.chest + 0.02, 0.15), pal.top, Vector3(1.2, 0.8, 0.7))
			"fringe_sleeves":
				for side in ["L", "R"]:
					B.part(rig, "Shoulder" + side, "ShortSleeve" + side, B.cylinder(d.limb_r * 1.5, d.limb_r * 2.4, d.upper_arm * 0.8), Vector3(0, -d.upper_arm * 0.42, 0), pal.top)
					B.part(rig, "Elbow" + side, "Bracer" + side, B.cylinder(d.limb_r * 1.15, d.limb_r * 1.05, d.forearm * 0.6), Vector3(0, -d.forearm * 0.6, 0), pal.leather)
					for i in 3:
						var wrap := B.part(rig, "Elbow" + side, "Wire%s%d" % [side, i], B.torus(d.limb_r * 1.12, d.limb_r * 1.3), Vector3(0, -d.forearm * (0.4 + i * 0.15), 0), pal.metal)
						wrap.rotation.x = 0.15 * (i - 1)
			"strap":
				var strap := B.part(rig, "Chest", "Bandolier", B.box(Vector3(0.06, 0.56, 0.025)), Vector3(0, d.chest * 0.5, -0.15), pal.leather)
				strap.rotation.z = 0.6
				_set_prop(B.part(rig, "Chest", "BandolierBuckle", B.torus(0.018, 0.032), Vector3(-0.05, d.chest * 0.6, -0.17), pal.metal), "rotation.x", PI / 2)
			"pouches":
				for i in 2:
					B.part(rig, "Hips", "Pouch%d" % i, B.box(Vector3(0.08, 0.13, 0.06)), Vector3(0.12 + i * 0.08, -0.08, -0.17 + i * 0.04), pal.leather.lightened(0.05 * i))
			"rune_stitches":
				# Faded runes stitched into the cloak, the storm-keeper's look.
				var stitch := CharacterStyle.material(pal.trim)
				for i in 8:
					var y: float = d.chest - 0.12 - i * 0.11
					var x: float = (-0.14 if i % 2 == 0 else 0.15) + (i % 3) * 0.02
					var s := B.part(rig, "Chest", "Stitch%d" % i, B.box(Vector3(0.05, 0.006, 0.004)), Vector3(x, y, -_cloak_front(i)), pal.trim)
					s.rotation.z = 0.6 if i % 2 == 0 else -0.8
					s.material_override = stitch
					var s2 := B.part(rig, "Chest", "Stitch%db" % i, B.box(Vector3(0.006, 0.05, 0.004)), Vector3(x + 0.012, y, -_cloak_front(i)), pal.trim)
					s2.material_override = stitch
			"apron":
				B.part(rig, "Spine", "Apron", B.box(Vector3(0.24 * w, 0.42, 0.012)), Vector3(0, -0.15, -0.135), pal.get("apron", Color("#d9d2bf")))
				B.part(rig, "Chest", "ApronBib", B.box(Vector3(0.18, 0.16, 0.012)), Vector3(0, d.chest * 0.32, -0.142), pal.get("apron", Color("#d9d2bf")))
			"shawl":
				B.part(rig, "Chest", "Shawl", B.cylinder(0.1, 0.24 * sh, 0.18, 18), Vector3(0, d.chest - 0.06, 0.0), pal.get("shawl", Color("#7b5a72")), Vector3(1.05, 1, 0.85))
			"long_skirt":
				B.part(rig, "Hips", "Skirt", B.cylinder(0.15 * w, 0.29, d.hip_y - 0.12, 18), Vector3(0, -(d.hip_y - 0.12) * 0.5 + 0.06, 0), pal.bottom, Vector3(1, 1, 0.85))
			"vest":
				B.part(rig, "Chest", "Vest", B.sphere(0.172), Vector3(0, d.chest * 0.48, 0.0), pal.get("vest", pal.leather), Vector3(1.19 * sh, 1.02, 0.8))
				B.part(rig, "Chest", "VestOpening", B.box(Vector3(0.06, d.chest * 0.8, 0.01)), Vector3(0, d.chest * 0.48, -0.138), pal.top)
			"jerkin":
				B.part(rig, "Chest", "Jerkin", B.sphere(0.174), Vector3(0, d.chest * 0.48, 0.0), pal.leather, Vector3(1.2 * sh, 1.05, 0.8))
				B.part(rig, "Spine", "JerkinSkirt", B.cylinder(0.15 * w, 0.2, 0.2), Vector3(0, -0.04, 0), pal.leather, Vector3(1, 1, 0.85))
				for i in 4:
					B.part(rig, "Chest", "Stud%d" % i, B.sphere(0.012), Vector3(-0.06 + (i % 2) * 0.12, d.chest * (0.35 + int(i / 2) * 0.25), -0.138), pal.metal)
			"neckerchief":
				_set_prop(B.part(rig, "Chest", "Neckerchief", B.prism(Vector3(0.12, 0.09, 0.02)), Vector3(0, d.chest - 0.07, -0.12), pal.get("scarf", Color("#b24a3a"))), "rotation.x", PI)


static func _set_prop(node: Node3D, prop: String, value) -> void:
	if prop == "rotation":
		node.rotation = value
	else:
		node.set_indexed(prop.replace(".", ":"), value)


static func _cloak_front(i: int) -> float:
	return 0.14 + i * 0.024


## Hats sit on the head's HatSocket.
static func add_hat(rig: CharacterRig, spec: CharacterSpec, d: Dictionary, pal: Dictionary) -> void:
	var B := CharacterBuilder
	var r: float = d.head_r
	var hat_color: Color = pal.get("hat", pal.top)
	match spec.hat:
		"wizard":
			B.part(rig, "hat", "HatBrim", B.cylinder(r * 2.0, r * 2.05, 0.02, 24), Vector3(0, 0, 0), hat_color)
			B.part(rig, "hat", "HatCone", B.cylinder(r * 0.5, r * 1.05, r * 2.0, 20), Vector3(0, r * 1.0, 0.0), hat_color)
			var tip := B.part(rig, "hat", "HatTip", B.cylinder(0.0, r * 0.5, r * 1.2, 16), Vector3(0, r * 2.45, r * 0.18), hat_color)
			tip.rotation.x = 0.45
			var band := B.part(rig, "hat", "HatBand", B.cylinder(r * 1.0, r * 1.06, r * 0.22, 20), Vector3(0, r * 0.14, 0), pal.accent)
			band.material_override = CharacterStyle.glow(pal.accent, 1.2)
			var buckle := B.part(rig, "hat", "HatRune", B.box(Vector3(r * 0.3, r * 0.3, 0.01)), Vector3(0, r * 0.16, -r * 1.06), pal.accent)
			buckle.rotation.z = PI / 4
			buckle.material_override = CharacterStyle.glow(pal.accent, 2.5)
		"top":
			B.part(rig, "hat", "HatBrim", B.cylinder(r * 1.45, r * 1.45, 0.018, 24), Vector3(0, r * 0.05, 0), hat_color)
			B.part(rig, "hat", "HatCrown", B.cylinder(r * 0.82, r * 0.88, r * 1.25, 20), Vector3(0, r * 0.66, 0), hat_color)
			B.part(rig, "hat", "HatBand", B.cylinder(r * 0.9, r * 0.9, r * 0.22, 20), Vector3(0, r * 0.2, 0), pal.leather)
			var gear := B.part(rig, "hat", "HatGear", B.torus(r * 0.08, r * 0.17), Vector3(r * 0.86, r * 0.22, -r * 0.2), pal.metal)
			gear.rotation.z = PI / 2
		"straw":
			B.part(rig, "hat", "HatBrim", B.cylinder(r * 1.4, r * 2.2, r * 0.25, 20), Vector3(0, r * 0.0, 0), hat_color)
			B.part(rig, "hat", "HatCrown", B.cylinder(r * 0.65, r * 0.95, r * 0.6, 16), Vector3(0, r * 0.35, 0), hat_color)
			B.part(rig, "hat", "HatBand", B.cylinder(r * 0.96, r * 0.98, r * 0.14, 16), Vector3(0, r * 0.12, 0), Color("#8a3f2c"))
		"cap":
			B.part(rig, "hat", "Cap", B.sphere(r * 1.08, true), Vector3(0, -r * 0.1, 0.0), hat_color, Vector3(1, 0.7, 1))
			B.part(rig, "hat", "CapPeak", B.cylinder(r * 0.8, r * 0.8, 0.012), Vector3(0, -r * 0.08, -r * 0.75), hat_color.darkened(0.15), Vector3(1, 1, 0.6))
		"frayed_point":
			# The storm-keeper's hat: wide frayed brim, short crooked point.
			B.part(rig, "hat", "HatBrim", B.cylinder(r * 2.1, r * 2.2, 0.025, 28), Vector3(0, 0, 0), hat_color)
			for i in 14:
				var a := TAU * float(i) / 14.0
				var fray := B.part(rig, "hat", "Fray%d" % i, B.prism(Vector3(r * 0.32, r * 0.18, 0.012)), Vector3(cos(a) * r * 2.18, -r * 0.05, sin(a) * r * 2.18), hat_color.darkened(0.12))
				fray.rotation = Vector3(PI, -a + PI / 2, 0)
			B.part(rig, "hat", "HatCone", B.cylinder(r * 0.45, r * 1.05, r * 1.5, 18), Vector3(0, r * 0.75, 0), hat_color)
			var tip := B.part(rig, "hat", "HatTip", B.cylinder(0.0, r * 0.45, r * 0.9, 12), Vector3(r * 0.15, r * 1.75, r * 0.1), hat_color)
			tip.rotation = Vector3(0.3, 0, -0.5)
			B.part(rig, "hat", "HatBand", B.cylinder(r * 1.02, r * 1.06, r * 0.18, 18), Vector3(0, r * 0.1, 0), pal.leather)


## Things held in the right hand.
static func add_prop(rig: CharacterRig, spec: CharacterSpec, d: Dictionary) -> void:
	var B := CharacterBuilder
	var wood := Color("#8b7355")
	match spec.prop:
		"storm_staff":
			# Copper-wrapped driftwood with a forked top holding a small storm cloud.
			var root := Node3D.new()
			root.name = "StormStaff"
			root.position = Vector3(0, 0.0, 0)
			rig.sockets["item_r"].add_child(root)
			rig.sockets["staff_root"] = root
			B.part(rig, "staff_root", "Shaft", B.cylinder(0.026, 0.032, 1.75, 10), Vector3(0, 0.12, 0), wood)
			for i in 5:
				B.part(rig, "staff_root", "Copper%d" % i, B.torus(0.028, 0.038), Vector3(0, 0.55 - i * 0.12 + (0.6 if i > 2 else 0.0), 0), Color("#b8763f"))
			for i in 3:
				var prong := B.part(rig, "staff_root", "Prong%d" % i, B.cylinder(0.008, 0.02, 0.32, 8), Vector3(0, 1.1, 0), wood)
				prong.rotation = Vector3(0.0, TAU * i / 3.0, 0.3)
				prong.position += prong.basis.y * 0.12
			var cloud := Node3D.new()
			cloud.name = "StormCloud"
			cloud.position = Vector3(0, 1.32, 0)
			rig.sockets["staff_root"].add_child(cloud)
			rig.sockets["storm_cloud"] = cloud
			var puffs := [Vector3(0, 0, 0), Vector3(0.07, 0.02, 0.02), Vector3(-0.07, 0.01, -0.02), Vector3(0.02, 0.06, -0.03), Vector3(-0.02, -0.03, 0.05), Vector3(0.0, 0.03, 0.07)]
			for i in puffs.size():
				var puff := B.part(rig, "storm_cloud", "Puff%d" % i, B.sphere(0.065 - i * 0.004), puffs[i], Color("#c9d6e6"))
				puff.material_override = CharacterStyle.material(Color("#c9d6e6"), 0.6, 0.6)
			var bolt := _lightning(Color("#e6f2ff"), 0.16, 5, 11)
			bolt.name = "CloudBolt"
			bolt.position = Vector3(0, -0.04, 0)
			cloud.add_child(bolt)
			rig.flickers.append(bolt)
			var light := OmniLight3D.new()
			light.name = "CloudLight"
			light.light_color = Color("#cfe6ff")
			light.light_energy = 0.6
			light.omni_range = 2.5
			cloud.add_child(light)
			rig.flicker_lights.append(light)
		"walking_stick":
			B.part(rig, "item_r", "Stick", B.cylinder(0.018, 0.022, 1.15, 8), Vector3(0, -0.35, 0), wood)
		"pitchfork":
			var fork := B.part(rig, "item_r", "Handle", B.cylinder(0.018, 0.018, 1.5, 8), Vector3(0, 0.15, 0), wood)
			for i in 3:
				B.part(rig, "item_r", "Tine%d" % i, B.cylinder(0.006, 0.008, 0.22, 6), Vector3(-0.05 + i * 0.05, 1.0, 0), Color("#7a7a7a"))
			B.part(rig, "item_r", "ForkBar", B.box(Vector3(0.12, 0.015, 0.015)), Vector3(0, 0.9, 0), Color("#7a7a7a"))
			fork.set_meta("prop", true)
		"basket":
			B.part(rig, "item_r", "Basket", B.cylinder(0.13, 0.1, 0.12, 14), Vector3(0, -0.12, -0.04), Color("#b08a52"))
			var handle := B.part(rig, "item_r", "BasketHandle", B.torus(0.1, 0.115), Vector3(0, -0.03, -0.04), Color("#8a6a3a"))
			handle.rotation.x = PI / 2
			for i in 3:
				B.part(rig, "item_r", "Apple%d" % i, B.sphere(0.035), Vector3(-0.05 + i * 0.05, -0.05, -0.04 + (i % 2) * 0.03), Color("#b8322a"))
		"book":
			B.part(rig, "item_l", "HeldBook", B.box(Vector3(0.16, 0.03, 0.12)), Vector3(0, -0.02, -0.05), Color("#4a2e1e"))


## Hand sparks and the path's cast effect. The rig turns these up while casting.
static func add_magic(rig: CharacterRig, spec: CharacterSpec, _d: Dictionary) -> void:
	if not spec.is_player_outfit():
		return
	var color: Color = CharacterStyle.MAGIC[spec.outfit]
	for side in ["l", "r"]:
		var fx := Node3D.new()
		fx.name = "MagicFX"
		rig.sockets["cast_" + side].add_child(fx)
		match spec.outfit:
			"sorcerer":
				for i in 3:
					var bolt := _lightning(color, 0.22, 5, i * 7 + (1 if side == "l" else 2))
					bolt.rotation = Vector3(0.4 * i, i * 2.1, 0.8 * i)
					fx.add_child(bolt)
					rig.flickers.append(bolt)
			"mage":
				var ring := MeshInstance3D.new()
				ring.name = "ClockRing"
				ring.mesh = CharacterBuilder.torus(0.12, 0.135)
				ring.rotation.x = PI / 2
				ring.material_override = CharacterStyle.glow(Color(color, 0.8), 2.0)
				fx.add_child(ring)
				for i in 12:
					var tick := MeshInstance3D.new()
					tick.mesh = CharacterBuilder.box(Vector3(0.008, 0.03 if i % 3 == 0 else 0.016, 0.004))
					var a := TAU * i / 12.0
					tick.position = Vector3(sin(a) * 0.105, cos(a) * 0.105, 0)
					tick.rotation.z = -a
					tick.material_override = ring.material_override
					fx.add_child(tick)
				for i in 4:
					var shard := MeshInstance3D.new()
					shard.mesh = CharacterBuilder.prism(Vector3(0.03, 0.07, 0.03))
					var a := TAU * i / 4.0 + 0.4
					shard.position = Vector3(cos(a) * 0.17, sin(a) * 0.17, 0.0)
					shard.rotation.z = a - PI / 2
					shard.material_override = CharacterStyle.glow(Color("#d9fbff", 0.9), 1.5)
					fx.add_child(shard)
			"wizard":
				# Golden runes orbiting the hand.
				for i in 5:
					var rune := MeshInstance3D.new()
					rune.mesh = CharacterBuilder.box(Vector3(0.04, 0.04, 0.004))
					var a := TAU * i / 5.0
					rune.position = Vector3(cos(a) * 0.14, sin(a) * 0.14 + 0.02, sin(a * 2.0) * 0.04)
					rune.rotation = Vector3(0, a, PI / 4)
					rune.material_override = CharacterStyle.glow(color, 3.0)
					fx.add_child(rune)
					var bar := MeshInstance3D.new()
					bar.mesh = CharacterBuilder.box(Vector3(0.006, 0.055, 0.004))
					bar.position = rune.position
					bar.rotation.y = a
					bar.material_override = rune.material_override
					fx.add_child(bar)
			_:
				# Level 1 sparks: little blue crackles, like the turnaround.
				for i in 2:
					var bolt := _lightning(color, 0.1, 4, i * 5 + (3 if side == "l" else 4))
					bolt.rotation = Vector3(i * 1.4, i * 2.0, 0.5)
					fx.add_child(bolt)
					rig.flickers.append(bolt)
		var light := OmniLight3D.new()
		light.name = "MagicLight"
		light.light_color = color
		light.omni_range = 1.1
		light.light_energy = 0.0
		fx.add_child(light)
		rig.magic_fx.append(fx)
		rig.magic_lights.append(light)


## A jagged glowing bolt made of thin boxes, seeded so it looks the same every build.
static func _lightning(color: Color, length: float, segments: int, seed_value: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Bolt"
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var mat := CharacterStyle.glow(color, 4.0)
	var p := Vector3.ZERO
	var step := length / segments
	for i in segments:
		var next := p + Vector3(rng.randf_range(-0.6, 0.6) * step, step, rng.randf_range(-0.6, 0.6) * step)
		var seg := MeshInstance3D.new()
		seg.mesh = CharacterBuilder.box(Vector3(0.006, (next - p).length(), 0.006))
		seg.material_override = mat
		seg.position = (p + next) * 0.5
		seg.basis = _basis_along(next - p)
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(seg)
		p = next
	return root


static func _basis_along(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var x := y.cross(Vector3.FORWARD)
	if x.length_squared() < 0.001:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	return Basis(x, y, x.cross(y)).orthonormalized()


static func _side(sx: float) -> String:
	return "L" if sx < 0 else "R"
