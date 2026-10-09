extends SceneTree
## Headless tests for the character models, animations and NPCs.
## Run: godot --headless --path . --script res://actors/characters/tests/test_characters.gd

var _failures: PackedStringArray = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_presets_match_creation_data()
	_test_spec_sources()
	_test_every_preset_builds()
	_test_proportions()
	_test_outfits()
	await _test_animations()
	await _test_follows_progression()
	await _test_driver_on_player()
	await _test_npcs()

	if _failures.is_empty():
		print("CHARACTER TESTS PASSED")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: ", f)
		quit(1)


## The model's preset tables must line up with the creation screen and progression data.
func _test_presets_match_creation_data() -> void:
	var data := ProgressionData.appearance()
	var pairs := {
		"faces": CharacterStyle.FACES, "skins": CharacterStyle.SKINS, "hair_styles": CharacterStyle.HAIR_STYLES,
		"hair_colors": CharacterStyle.HAIR_COLORS, "eyes": CharacterStyle.EYES, "builds": CharacterStyle.BUILDS,
	}
	for key in pairs:
		var ids := PackedStringArray()
		for entry in data[key]:
			ids.append(entry["id"])
		_check(ids == CharacterStyle.ids(pairs[key]), "%s ids and order match appearance_presets.json" % key)
	for entry in data["skins"]:
		_check(Color(entry["color"]).is_equal_approx(CharacterStyle.SKINS[entry["id"]]), "skin %s colour matches" % entry["id"])
	_check(CharacterStyle.ids(CharacterStyle.FACES).size() == UiCharacterPresets.FACES.size(), "face count matches the creation screen")
	_check(CharacterStyle.HAIR_STYLES.size() == UiCharacterPresets.HAIR_STYLES.size(), "hair style count matches the creation screen")
	for i in UiCharacterPresets.HAIR_STYLES.size():
		_check(UiCharacterPresets.HAIR_STYLES[i].to_lower() == CharacterStyle.HAIR_STYLES[i], "hair style %d is %s" % [i, CharacterStyle.HAIR_STYLES[i]])
	for i in UiCharacterPresets.EYES.size():
		_check(UiCharacterPresets.EYES[i].name.to_lower() == CharacterStyle.ids(CharacterStyle.EYES)[i], "eye colour %d lines up" % i)


func _test_spec_sources() -> void:
	# The creation screen's index dictionary.
	var ui := {"name": "Lyra", "sex": 1, "face": 2, "skin": 4, "hair": 3, "hair_color": 2, "eyes": 5, "build": 0}
	var s := CharacterSpec.from_any(ui)
	_check(s.body == "girl" and s.face == "heart" and s.skin == "brown" and s.hair_style == "braid", "UI indices map to presets")
	_check(s.hair_color == "auburn" and s.eyes == "violet" and s.build == "slight" and s.character_name == "Lyra", "UI indices map to the rest")
	# Progression's CharacterAppearance, and its round trip through the UI dictionary.
	var a := CharacterAppearance.from_ui_dict(ui)
	var from_appearance := CharacterSpec.from_any(a)
	_check(from_appearance.to_dict().merged({}, true)["face"] == "heart" and from_appearance.body == "girl", "CharacterAppearance converts")
	for key in ["body", "face", "skin", "hair_style", "hair_color", "eyes", "build"]:
		_check(str(from_appearance.get(key)) == str(s.get(key)), "UI dict and CharacterAppearance agree on %s" % key)
	# Bad input falls back instead of failing.
	var bad := CharacterSpec.from_any({"body": "dragon", "skin": "plaid", "sex_unused": 1})
	_check(bad.body == "boy" and bad.skin == "fair", "unknown presets fall back to defaults")
	var clamped := CharacterSpec.from_any({"sex": 9, "face": -3, "hair": 99})
	_check(clamped.body == "girl" and clamped.face == "round" and clamped.hair_style == "shaved", "out-of-range UI indices clamp")
	_check(CharacterSpec.from_any(null).body == "boy", "null gives the default")
	var copy := CharacterSpec.from_any(s)
	copy.face = "square"
	_check(s.face == "heart", "from_any copies a spec instead of sharing it")
	var mage := CharacterSpec.player("girl", "mage")
	_check(mage.outfit == "mage" and mage.hat == "top", "girl mage gets the green top hat")
	mage.set_path("sorcerer")
	_check(mage.outfit == "sorcerer" and mage.hat == "", "switching path drops the mage hat")
	_check(CharacterSpec.player("boy", "nonsense").outfit == "farm", "unknown path gives farm clothes")


func _test_every_preset_builds() -> void:
	var count := 0
	for body in CharacterStyle.BODIES:
		for table in [CharacterStyle.FACES, CharacterStyle.SKINS, CharacterStyle.HAIR_STYLES, CharacterStyle.HAIR_COLORS, CharacterStyle.EYES, CharacterStyle.BUILDS]:
			for id in CharacterStyle.ids(table):
				var s := CharacterSpec.player(body)
				var field := _field_for(table)
				s.set(field, id)
				var rig := CharacterBuilder.build(s)
				if rig.joints.size() != CharacterBuilder.JOINTS.size() or rig.anim_tree == null:
					_check(false, "%s %s=%s builds" % [body, field, id])
				count += 1
				rig.free()
	_check(count == 2 * (4 + 6 + 6 + 6 + 6 + 3), "built every preset for both bodies (%d)" % count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 40:
		var s := CharacterSpec.new()
		s.body = CharacterStyle.BODIES[rng.randi() % 2]
		s.face = _rand(rng, CharacterStyle.FACES)
		s.hair_style = _rand(rng, CharacterStyle.HAIR_STYLES)
		s.build = _rand(rng, CharacterStyle.BUILDS)
		s.set_path(CharacterStyle.OUTFITS[rng.randi() % 4])
		var rig := CharacterBuilder.build(s)
		_check(rig.anim_tree != null, "random combination %d builds" % i)
		rig.free()


func _test_proportions() -> void:
	for body in CharacterStyle.BODIES:
		var rig := CharacterBuilder.build(CharacterSpec.player(body))
		root.add_child(rig)
		var aabb := _aabb(rig)
		_check(absf(aabb.position.y) < 0.03, "%s stands on the ground (lowest point %.3f)" % [body, aabb.position.y])
		_check(aabb.end.y > 1.5 and aabb.end.y < 1.8, "%s is 1.5 to 1.8m tall, fits the 1.7m capsule (%.2f)" % [body, aabb.end.y])
		_check(aabb.size.x < 0.8 and aabb.size.z < 0.6, "%s fits the player capsule's footprint (%.2f x %.2f)" % [body, aabb.size.x, aabb.size.z])
		# Faces the controller's forward (-Z).
		var nose_z: float = rig.get_joint("Head").get_node("Merged").get_aabb().position.z
		_check(nose_z < -rig.dims.head_r * 0.8, "%s faces -Z" % body)
		_check(rig.get_cast_point().global_position.y > 0.5, "%s cast point is at hand height" % body)
		rig.free()
	var child := CharacterBuilder.build(NpcCatalog.tam())
	var adult := CharacterBuilder.build(CharacterSpec.player())
	_check(child.get_height() < adult.get_height() * 0.8, "Tam is a child, clearly shorter than the arcanist")
	child.free()
	adult.free()


func _test_outfits() -> void:
	var expect := {
		"farm": ["Satchel", "Belt"],
		"wizard": ["Robe", "HatCone", "HemTrim", "Book"],
		"mage": ["Pack", "Clock", "Frost0", "ClockRing"],
		"sorcerer": ["CoatSkirt", "HighCollar", "Sash"],
	}
	for path in expect:
		var rig := CharacterBuilder.build(CharacterSpec.player("boy", path))
		var names := _all_names(rig)
		for part in expect[path]:
			# Merged parts lose their names, so also accept their unmerged glow pieces.
			_check(part in names or _was_built(rig, path, part), "%s outfit has %s" % [path, part])
		_check(rig.magic_fx.size() == 2, "%s has magic in both hands" % path)
		rig.free()
	var girl := CharacterBuilder.build(CharacterSpec.player("girl", "mage"))
	_check(girl.get_socket(&"hat").get_child_count() > 0, "girl mage wears a hat")
	girl.free()
	var boy := CharacterBuilder.build(CharacterSpec.player("boy", "farm"))
	_check(boy.get_socket(&"hat").get_child_count() == 0, "farm boy is bareheaded")
	var meshes := boy.find_children("*", "MeshInstance3D", true, false).size()
	_check(meshes < 60, "body parts are merged into few meshes (%d)" % meshes)
	boy.free()


func _test_animations() -> void:
	var rig := CharacterBuilder.build(CharacterSpec.player("boy", "sorcerer"))
	root.add_child(rig)
	var lib := rig.anim_tree.get_animation_library(&"")
	for anim_name in CharacterAnimations.NAMES:
		_check(lib.has_animation(anim_name), "has %s animation" % anim_name)
	var events: Array = []
	rig.action_finished.connect(func(a): events.append(a))
	var released := [false]
	rig.cast_released.connect(func(): released[0] = true)

	rig.update_locomotion(0.0, true)
	await _frames(30)
	var thigh: Node3D = rig.get_joint("ThighL")
	var rest := rig.rest_rotation("ThighL")
	_check(thigh.rotation.distance_to(rest) < 0.05, "idle keeps the legs near rest")

	rig.update_locomotion(6.5, true)
	var swing := 0.0
	for i in 40:
		await physics_frame
		swing = maxf(swing, absf(thigh.rotation.x - rest.x))
	_check(rig.locomotion_state() == &"run", "running speed picks run")
	_check(swing > 0.5, "run swings the legs (%.2f rad)" % swing)

	rig.update_locomotion(0.0, false, 6.0)
	await _frames(15)
	_check(rig.locomotion_state() == &"jump", "rising off the ground picks jump")
	rig.update_locomotion(0.0, false, -4.0)
	await _frames(5)
	_check(rig.locomotion_state() == &"fall", "falling picks fall")
	rig.update_locomotion(0.0, true)

	rig.play_dodge(0.22)
	var min_hips := 99.0
	var turned := 0.0
	for i in 16:
		await physics_frame
		min_hips = minf(min_hips, rig.get_joint("Hips").position.y)
		turned = minf(turned, rig.get_joint("Hips").rotation.x)
	_check(turned < -3.0, "dodge rolls forward (%.2f rad)" % turned)
	_check(min_hips < rig.dims.hip_y * 0.8, "dodge ducks low")
	_check(&"dodge" in events, "dodge finishes")

	rig.play_cast(0.5)
	_check(rig.current_action() == &"cast", "cast starts")
	var arm_raise := 0.0
	var fx_seen := false
	for i in 70:
		await physics_frame
		arm_raise = maxf(arm_raise, rig.get_joint("ShoulderR").rotation.x - rig.rest_rotation("ShoulderR").x)
		fx_seen = fx_seen or rig.magic_fx[0].visible
	_check(released[0], "cast_released fires")
	_check(arm_raise > 1.0, "cast thrusts the arm forward (%.2f rad)" % arm_raise)
	_check(fx_seen, "magic shows in the hands while casting")
	_check(&"cast" in events and not rig.is_busy(), "cast finishes")

	# Casting while running keeps the legs running.
	rig.update_locomotion(6.5, true)
	await _frames(10)
	rig.play_cast(0.0)
	swing = 0.0
	for i in 20:
		await physics_frame
		swing = maxf(swing, absf(thigh.rotation.x - rest.x))
	_check(swing > 0.4, "legs keep running under a cast")
	rig.update_locomotion(0.0, true)

	rig.play_hit()
	await _frames(3)
	_check(rig.skin_material.emission_enabled, "hit flashes the body")
	await _frames(30)
	_check(not rig.skin_material.emission_enabled, "hit flash fades")

	rig.play_cast(1.0)
	await _frames(5)
	rig.cancel_action()
	_check(not rig.is_busy(), "cancel_action stops a cast")
	rig.free()


func _test_follows_progression() -> void:
	var progression: Node = root.get_node_or_null("Progression")
	_check(progression != null, "Progression autoload is running")
	if progression == null:
		return
	var appearance := CharacterAppearance.create_default("girl")
	appearance.set_option("hair_color", "ember")
	progression.new_character(appearance)
	var scene: Node3D = load("res://actors/characters/arcanist.tscn").instantiate()
	root.add_child(scene)
	var rig := scene as CharacterRig
	_check(rig.spec.body == "girl" and rig.spec.hair_color == "ember", "arcanist.tscn builds the player's character")
	_check(rig.spec.outfit == "farm", "no path yet means farm clothes")
	progression.appearance.set_option("skin", "deep")
	await process_frame
	_check(rig.spec.skin == "deep", "follows appearance changes")
	progression.progression.path = "wizard"
	progression.progression.path_chosen.emit("wizard")
	await process_frame
	_check(rig.spec.outfit == "wizard" and rig.get_socket(&"hat").get_child_count() > 0, "changes into wizard robes when the path is chosen")
	progression.new_character(CharacterAppearance.create_default("boy"))
	await process_frame
	_check(rig.spec.body == "boy" and rig.spec.outfit == "farm", "a new game rebuilds the model")
	rig.queue_free()
	await process_frame


func _test_driver_on_player() -> void:
	var level: Node = load("res://scenes/greybox_test.tscn").instantiate()
	root.add_child(level)
	var player: CharacterBody3D = level.get_node("Player")
	# The swap-in from the PR: rig under Model, driver beside it.
	for child in player.get_node("Model").get_children():
		child.queue_free()
	var rig: CharacterRig = load("res://actors/characters/arcanist.tscn").instantiate()
	player.get_node("Model").add_child(rig)
	var driver := CharacterAnimationDriver.new()
	player.add_child(driver)
	await _frames(60)
	_check(rig.locomotion_state() == &"idle", "driver: standing still idles")
	Input.action_press("move_forward")
	await _frames(30)
	_check(rig.locomotion_state() == &"run", "driver: moving runs")
	Input.action_release("move_forward")
	await _frames(30)
	Input.action_press("jump")
	await _frames(6)
	_check(rig.locomotion_state() == &"jump", "driver: jumping")
	Input.action_release("jump")
	await _frames(60)
	Input.action_press("dodge")
	await _frames(2)
	Input.action_release("dodge")
	_check(rig.current_action() == &"dodge", "driver: dodge plays the roll")
	var caster := player.get_node_or_null("SpellCaster")
	if caster:
		caster.cast_started.emit(null, 0.4)
		_check(rig.current_action() == &"cast", "driver: SpellCaster.cast_started plays the cast")
	var health := player.get_node_or_null("HealthComponent")
	if health:
		await _frames(40)
		health.damaged.emit(null, 5.0)
		_check(rig.current_action() == &"hit", "driver: HealthComponent.damaged plays the hit")
	level.queue_free()
	await _frames(2)


func _test_npcs() -> void:
	var old := CharacterBuilder.build(NpcCatalog.old_man())
	_check(old.get_socket(&"storm_cloud") != null, "the old man's staff holds a storm cloud")
	_check(old.spec.beard == "full" and old.spec.hat == "frayed_point", "the old man has his beard and frayed hat")
	_check(old.flickers.size() > 0, "the storm cloud crackles")
	old.free()

	var player := CharacterSpec.player("boy")
	player.skin = "olive"
	player.hair_color = "blond"
	var tam := NpcCatalog.tam(player)
	_check(tam.skin == "olive" and tam.hair_color == "blond", "Tam shares the arcanist's skin and hair")
	_check(tam.body == "girl" and NpcCatalog.tam(CharacterSpec.player("girl")).body == "boy", "Tam defaults to the other body")

	var a := NpcCatalog.villager(42).to_dict()
	var b := NpcCatalog.villager(42).to_dict()
	_check(a == b, "the same seed gives the same villager")
	var looks := {}
	for i in 30:
		looks[str(NpcCatalog.villager(i).to_dict())] = true
	_check(looks.size() > 25, "different seeds give different villagers (%d of 30)" % looks.size())
	for role in NpcCatalog.ROLES:
		var spec := NpcCatalog.villager(7, role)
		_check(spec.get_meta("role") == role, "villager role %s" % role)
		var rig := CharacterBuilder.build(spec)
		_check(rig.anim_tree != null, "villager %s builds" % role)
		rig.free()

	var npc := Npc.create("old_man")
	root.add_child(npc)
	await _frames(2)
	_check(npc.is_in_group(&"npcs") and npc.display_name != "", "Npc joins the npcs group with a name")
	npc.face_toward(npc.global_position + Vector3(5, 0, 0))
	await _frames(60)
	var forward := -npc.rig.global_basis.z
	_check(forward.dot(Vector3.RIGHT) > 0.95, "Npc turns to face a point")
	npc.talk()
	_check(npc.rig.current_action() == &"talk", "Npc talks")
	npc.queue_free()
	await _frames(2)


# --- Helpers ---

func _was_built(rig: CharacterRig, _path: String, part: String) -> bool:
	# Parts merged into a joint's mesh are gone by name; check the build log instead.
	return part in rig.built_parts


func _all_names(node: Node) -> PackedStringArray:
	var out := PackedStringArray()
	for n in node.find_children("*", "", true, false):
		out.append(n.name)
	return out


func _aabb(rig: CharacterRig) -> AABB:
	var box := AABB()
	var first := true
	for mi in rig.find_children("*", "MeshInstance3D", true, false):
		if not (mi as MeshInstance3D).is_visible_in_tree():
			continue
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _field_for(table) -> String:
	match table:
		CharacterStyle.FACES: return "face"
		CharacterStyle.SKINS: return "skin"
		CharacterStyle.HAIR_STYLES: return "hair_style"
		CharacterStyle.HAIR_COLORS: return "hair_color"
		CharacterStyle.EYES: return "eyes"
	return "build"


func _rand(rng: RandomNumberGenerator, table) -> String:
	var keys := CharacterStyle.ids(table)
	return keys[rng.randi() % keys.size()]


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _check(condition: bool, label: String) -> void:
	print(("ok   " if condition else "FAIL ") + label)
	if not condition:
		_failures.append(label)
