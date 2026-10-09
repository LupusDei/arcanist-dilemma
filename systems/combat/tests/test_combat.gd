extends SceneTree
## Headless tests for the spell and combat system.
## Run: godot --headless --path . --fixed-fps 60 --script res://systems/combat/tests/test_combat.gd

var _failures: PackedStringArray = []
var _world: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_health()
	_test_combat_stats()
	_test_library()
	await _test_tricks()
	await _test_wizard()
	await _test_mage()
	await _test_sorcerer()
	await _test_deliveries()
	await _test_sandbox()

	if _failures.is_empty():
		print("COMBAT TESTS PASSED")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: ", f)
		quit(1)


# --- Health ------------------------------------------------------------------

func _test_health() -> void:
	print("-- health")
	var body := Node3D.new()
	var health := HealthComponent.new()
	health.max_health = 100.0
	body.add_child(health)
	root.add_child(body)

	var died_count := [0]
	health.died.connect(func(_k: Node) -> void: died_count[0] += 1)

	_check(is_equal_approx(health.take_damage(Hit.new(10.0, DamageType.Kind.FIRE)), 10.0), "plain damage lands in full")
	health.resistances = {DamageType.Kind.FIRE: 0.5, DamageType.Kind.COLD: 0.9, DamageType.Kind.MIND: -0.5}
	_check(is_equal_approx(health.take_damage(Hit.new(10.0, DamageType.Kind.FIRE)), 5.0), "50% fire resistance halves fire")
	_check(is_equal_approx(health.take_damage(Hit.new(10.0, DamageType.Kind.COLD)), 2.5), "resistance caps at 75%")
	_check(is_equal_approx(health.take_damage(Hit.new(10.0, DamageType.Kind.MIND)), 15.0), "negative resistance is a weakness")
	health.armor = 100.0
	_check(is_equal_approx(health.take_damage(Hit.new(10.0, DamageType.Kind.FORCE)), 5.0), "100 armor halves force")
	health.add_ward(8.0, 5.0)
	_check(is_equal_approx(health.take_damage(Hit.new(10.0, DamageType.Kind.FIRE)), 0.0), "ward absorbs before health")
	_check(is_zero_approx(health.ward - 3.0), "ward drains by what it absorbed")

	var invulnerable := _InvulnerableBody.new()
	var shielded := HealthComponent.new()
	invulnerable.add_child(shielded)
	root.add_child(invulnerable)
	_check(shielded.take_damage(Hit.new(50.0)) == 0.0, "dodging (is_invulnerable) body takes no damage")
	invulnerable.queue_free()

	health.tier = HealthComponent.Tier.ELITE
	health.apply_status(Status.Kind.STUN, 2.0)
	_check(is_equal_approx(health.statuses[Status.Kind.STUN]["remaining"], 1.0), "elites take half stun duration")
	health.tier = HealthComponent.Tier.BOSS
	health.statuses.clear()
	health.apply_status(Status.Kind.ROOT, 3.0)
	_check(health.statuses[Status.Kind.ROOT]["remaining"] <= 0.2, "bosses only stagger")
	health.statuses.clear()

	health.take_damage(Hit.new(1000.0, DamageType.Kind.ARCANE))
	health.take_damage(Hit.new(1000.0, DamageType.Kind.ARCANE))
	_check(health.is_dead and died_count[0] == 1, "died fires exactly once")
	health.revive()
	_check(not health.is_dead and health.health == 100.0, "revive restores full health")
	body.queue_free()


class _InvulnerableBody extends Node3D:
	var is_invulnerable := true


func _test_combat_stats() -> void:
	print("-- combat stats")
	var base := CombatStats.from_attributes(CombatStats.Path.MAGE, 10, 10, 10, 10, 10)
	_check(is_equal_approx(base.spell_power, 1.0), "all-10 attributes give base power")
	var mage := CombatStats.from_attributes(CombatStats.Path.MAGE, 10, 10, 10, 50, 10)
	_check(is_equal_approx(mage.spell_power, 1.4), "mage Intelligence 50 gives +40% power")
	var sorc := CombatStats.from_attributes(CombatStats.Path.SORCERER, 10, 55, 40, 10, 30)
	_check(is_equal_approx(sorc.spell_power, 1.45) and is_equal_approx(sorc.bonus_strain_capacity, 27.0), "sorcerer power and strain from Vitality")
	var wizard := CombatStats.from_attributes(CombatStats.Path.WIZARD, 10, 25, 25, 60, 25)
	_check(wizard.bonus_prepared_spells == 2 and is_equal_approx(wizard.spell_power, 1.0), "wizard Int gives pages, not power")
	var fast := CombatStats.from_attributes(CombatStats.Path.WIZARD, 10, 10, 200, 10, 200)
	_check(fast.cast_speed <= CombatStats.CAST_SPEED_CAP and fast.crit_chance <= CombatStats.CRIT_CHANCE_CAP, "cast speed and crit are capped")


func _test_library() -> void:
	print("-- library")
	SpellLibrary.reload()
	_check(SpellLibrary.all_spells().size() >= 20, "library loads the example spells (%d)" % SpellLibrary.all_spells().size())
	for spell in SpellLibrary.all_spells():
		_check(spell.id != &"" and not spell.display_name.is_empty(), "spell %s has an id and a name" % spell.id)
		if spell.delivery != SpellData.Delivery.SELF:
			_check(spell.effects.size() > 0, "spell %s has effects" % spell.id)
	_check(SpellLibrary.find_pair(&"burn", &"air") == SpellLibrary.get_spell(&"burn_air"), "mage pair lookup")
	_check(SpellLibrary.spells_for_path(SpellData.PathTag.SORCERER).size() >= 6, "sorcerer tree spells load")


# --- Paths -------------------------------------------------------------------

func _test_tricks() -> void:
	print("-- tricks")
	_new_world()
	var caster := _make_caster(TrickSet.new())
	var dummy := _make_dummy(Vector3(0, 0, -8))
	_check(caster.get_action_bar()[0].id == &"spark", "trick bar starts with Spark")
	_check(caster.cast_cantrip(_aim(dummy)), "cantrip casts")
	await _seconds(1.0)
	_check(is_equal_approx(dummy.total_damage, 6.0), "Spark projectile hits for 6 (%.1f)" % dummy.total_damage)
	caster.source.level = 3
	var cast_ok := caster.cast_cantrip(_aim(dummy))
	await _seconds(1.0)
	_check(cast_ok and is_equal_approx(dummy.last_damage, 7.2), "tricks grow 10%% per level (%.2f)" % dummy.last_damage)

	var jolt := SpellLibrary.get_spell(&"jolt")
	_check(caster.cast(jolt, _aim(dummy)), "Jolt casts at a target")
	_check(dummy.health.is_stunned(), "Jolt stuns")
	var reasons := _collect_failures(caster)
	caster.cast(jolt, _aim(dummy))
	_check(reasons.has(&"cooldown"), "Jolt respects its cooldown")
	await _clear_world()


func _test_wizard() -> void:
	print("-- wizard")
	_new_world()
	var book := WizardSpellbook.new(5)
	for id in [&"fireball", &"frost_lance", &"arcane_ward"]:
		book.add_book(id)
	var caster := _make_caster(book)
	_check(caster.caster_resource is ArcanaPool and caster.caster_resource.maximum == 150.0, "wizard uses a 150 Arcana pool")
	_check(not book.inscribe(&"fireball"), "inscribing needs a rest")

	caster.begin_rest()
	_check(book.inscribe(&"fireball") and book.inscribe(&"frost_lance") and book.inscribe(&"arcane_ward"), "inscribe three spells at a rest")
	book.prepare([&"fireball", &"arcane_ward"])
	caster.end_rest()
	_check(book.get_free_slots() == 2, "level 5 wizard has 5 slots")
	_check(caster.get_action_bar()[0].id == &"fireball", "prepared spells fill the bar")

	var reasons := _collect_failures(caster)
	caster.cast(SpellLibrary.get_spell(&"frost_lance"), Vector3.ZERO)
	_check(reasons.has(&"not_prepared"), "unprepared spells can't be cast")

	var a := _make_dummy(Vector3(0, 0, -10))
	var b := _make_dummy(Vector3(1.2, 0, -10))
	caster.caster_resource.regen_multiplier = 0.0
	var arcana_before := caster.caster_resource.current
	_check(caster.cast_slot(0, _aim(a)), "Fireball starts casting")
	_check(caster.is_casting(), "Fireball has a cast time")
	await _seconds(1.0)
	_check(a.total_damage == 0.0 and caster.caster_resource.current == arcana_before, "nothing happens or is spent mid-cast")
	await _seconds(2.0)
	_check(is_equal_approx(a.total_damage, 30.0) and is_equal_approx(b.total_damage, 30.0), "Fireball explosion hits both dummies for 30 (%.1f, %.1f)" % [a.total_damage, b.total_damage])
	_check(is_equal_approx(caster.caster_resource.current, arcana_before - 25.0), "Fireball costs 25 Arcana")

	# Interrupt by stun: nothing spent.
	var spent_before := caster.caster_resource.current
	caster.cast_slot(0, _aim(a))
	caster.health.apply_status(Status.Kind.STUN, 0.5)
	await _seconds(0.1)
	_check(not caster.is_casting() and caster.caster_resource.current >= spent_before, "a stun interrupts the cast without spending")
	await _seconds(0.6)

	# Circles: level 7 opens circle III; the book is needed.
	book.level = 7
	caster.begin_rest()
	_check(not book.upgrade(&"fireball"), "can't upgrade without the circle's book")
	book.add_book(&"fireball", 3)
	_check(book.upgrade(&"fireball") and book.get_circle(SpellLibrary.get_spell(&"fireball")) == 3, "upgrade to circle III with its book")
	book.add_book(&"fireball_searing")
	_check(book.choose_variant(&"fireball", &"fireball_searing"), "choose the Searing variant")
	caster.end_rest()
	_check(caster.get_action_bar()[0].id == &"fireball_searing", "the bar fires the chosen variant")
	_check(is_equal_approx(caster.get_power(caster.get_action_bar()[0]), pow(1.35, 2)), "circle III is 1.35^2 stronger")

	a.reset()
	b.reset()
	caster.cast_slot(0, _aim(a))
	await _seconds(3.0)
	var expected := 30.0 * pow(1.35, 2)
	_check(a.total_damage > expected + 1.0, "Searing Fireball's burning ground keeps hurting (%.1f > %.1f)" % [a.total_damage, expected])

	# Ward
	var ward_ok := caster.cast_slot(1, Vector3.ZERO)
	await _seconds(2.0)
	_check(ward_ok and caster.health.ward > 0.0, "Arcane Ward shields the caster")
	await _clear_world()


func _test_mage() -> void:
	print("-- mage")
	_new_world()
	var codex := MageCodex.new(5)
	codex.grant_starting_kit()
	var caster := _make_caster(codex)
	caster.stats.misfire_chance = 0.0
	_check(caster.caster_resource is ManaPool, "mage uses Mana")
	_check(caster.get_action_bar()[0].id == &"burn_air" and caster.get_action_bar()[2].id == &"bind_mind", "tricks evolve into the mage's three starting pairs")

	var chill := SpellLibrary.get_spell(&"chill_water")
	var reasons := _collect_failures(caster)
	caster.cast(chill, Vector3.ZERO)
	_check(reasons.has(&"unknown_words"), "can't cast a pair without knowing both words")

	codex.learn_word(&"chill")
	codex.learn_word(&"water")
	var dummy := _make_dummy(Vector3(0, 0, -6))
	caster.caster_resource.regen_multiplier = 0.0
	var mana_before := caster.caster_resource.current
	_check(caster.cast(chill, _aim(dummy)), "raw experiment with a new pair")
	await _seconds(1.5)
	_check(is_equal_approx(dummy.total_damage, 7.0), "raw casts are half power (%.1f)" % dummy.total_damage)
	_check(is_equal_approx(mana_before - caster.caster_resource.current, 32.0), "raw casts cost double mana")
	_check(codex.discovered.has(MageCodex.pair_key(&"chill", &"water")), "experiment writes the pair into the Codex")

	_check(not codex.formulate(&"chill", &"water"), "formulating needs Insight and a rest")
	codex.level = 6
	_check(codex.insight == 1, "level 6 gives an Insight")
	caster.begin_rest()
	_check(codex.formulate(&"chill", &"water"), "formulate the pair with Insight")
	caster.end_rest()
	await _seconds(2.5)
	dummy.reset()
	caster.cast(chill, _aim(dummy))
	await _seconds(1.5)
	_check(dummy.total_damage > 13.9, "formulated spells hit at full power (%.1f)" % dummy.total_damage)
	_check(dummy.health.has_status(Status.Kind.SLOW), "Chill Water slows")
	_check(codex.practice.get(&"chill", 0) == 2, "casting practices the words")

	# Misfire on a brand-new pair.
	codex.learn_word(&"break")
	codex.learn_word(&"earth")
	caster.stats.misfire_chance = 1.0
	var fizzled := [false]
	caster.misfired.connect(func(_s: SpellData) -> void: fizzled[0] = true)
	var generic := codex.get_pair_spell(&"break", &"earth")
	_check(generic != null and generic.delivery == SpellData.Delivery.AREA_AROUND_CASTER, "unauthored pairs are built from the verb/noun rules")
	caster.cast(generic, Vector3.ZERO)
	await _seconds(1.0)
	_check(fizzled[0], "a first raw experiment can misfire")
	await _clear_world()


func _test_sorcerer() -> void:
	print("-- sorcerer")
	_new_world()
	var tree := SorcererSpellTree.new(5)
	tree.grant_starting_points()
	var caster := _make_caster(tree)
	_check(caster.caster_resource is StrainPool and caster.caster_resource.current == 0.0, "sorcerer starts with 0 strain")
	_check(tree.get_tree().size() >= 7, "the whole tree is visible")
	_check(tree.check_learn(&"static_field") == &"row_locked", "row 2 opens at level 8")
	_check(tree.learn(&"spark_bolt") and tree.learn(&"spark_bolt") and tree.learn(&"shove"), "spend points on Spark Bolt and Shove")
	tree.level = 8
	_check(tree.check_learn(&"barrier") == &"", "Barrier is learnable after Shove at level 8")
	_check(tree.check_learn(&"overflow") == &"needs_previous", "Overflow needs Flare first")
	_check(tree.learn(&"static_field"), "learn Static Field")
	var bolt := SpellLibrary.get_spell(&"spark_bolt")
	_check(is_equal_approx(tree.get_power_multiplier(bolt), 1.2 * 1.05), "rank 2 +20%, synergy +5% per Static Field rank")

	var dummy := _make_dummy(Vector3(0, 0, -8))
	dummy.health.max_health = 10000.0
	dummy.health.revive()
	caster.cast(bolt, _aim(dummy))
	_check(caster.caster_resource.current > 0.0, "casting builds strain")
	var hp_before := caster.health.health
	for i in 15:
		caster._cooldowns.clear()
		caster.cast(bolt, _aim(dummy))
	var strain := caster.caster_resource as StrainPool
	_check(strain.is_overstrained(), "strain goes past capacity (%.0f / %.0f)" % [strain.current, strain.maximum])
	_check(caster.health.health < hp_before, "overstrained casts hurt the caster")
	_check(is_equal_approx(caster.get_power(bolt) / tree.get_power_multiplier(bolt), 1.25), "overstrain adds 25% power")
	for i in 10:
		caster.cast(bolt, _aim(dummy))
	_check(caster.health.is_stunned(), "collapse at 150% stuns the sorcerer")
	await _seconds(2.5)
	var high := strain.current
	await _seconds(1.0)
	_check(strain.current < high, "strain fades when you stop")

	# Chain Lightning jumps.
	await _clear_world()
	_new_world()
	tree = SorcererSpellTree.new(11)
	tree.points = 5
	tree.learn(&"spark_bolt")
	tree.learn(&"static_field")
	tree.learn(&"chain_lightning")
	caster = _make_caster(tree)
	var d1 := _make_dummy(Vector3(0, 0, -8))
	var d2 := _make_dummy(Vector3(3, 0, -8))
	var d3 := _make_dummy(Vector3(6, 0, -8))
	var far := _make_dummy(Vector3(30, 0, -8))
	caster.cast(SpellLibrary.get_spell(&"chain_lightning"), _aim(d1))
	await _seconds(0.6)
	var base := 20.0 * 1.05
	_check(is_equal_approx(d1.total_damage, base), "Chain Lightning hits the target (%.2f)" % d1.total_damage)
	_check(is_equal_approx(d2.total_damage, base * 0.8) and is_equal_approx(d3.total_damage, base * 0.64), "and jumps twice with falloff (%.2f, %.2f)" % [d2.total_damage, d3.total_damage])
	_check(far.total_damage == 0.0, "but not out of range")
	await _clear_world()


func _test_deliveries() -> void:
	print("-- deliveries")
	_new_world()
	var caster := _make_caster(SorcererSpellTree.new(5))
	var near := _make_dummy(Vector3(0, 0, -3))
	var behind := _make_dummy(Vector3(0, 0, 3))
	var pushed := [Vector3.ZERO]
	near.health.knocked_back.connect(func(i: Vector3) -> void: pushed[0] = i)
	var tree := caster.source as SorcererSpellTree
	tree.grant_starting_points()
	tree.learn(&"shove")
	caster.cast(SpellLibrary.get_spell(&"shove"), _aim(near))
	_check(near.total_damage > 0.0 and behind.total_damage == 0.0, "cones hit in front only")
	_check(pushed[0].z < -5.0, "Shove knocks the target away from the caster (%.1f)" % pushed[0].z)

	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 4, 0.5)
	shape.shape = box
	wall.add_child(shape)
	_world.add_child(wall)
	wall.position = Vector3(10, 1, -5)
	var hidden := _make_dummy(Vector3(10, 0, -8))
	var trick_caster := _make_caster(TrickSet.new(), Vector3(10, 0, 0))
	await physics_frame
	trick_caster.cast_cantrip(_aim(hidden))
	await _seconds(1.0)
	_check(hidden.total_damage == 0.0, "walls block projectiles")

	var reasons := _collect_failures(trick_caster)
	trick_caster.cast(SpellLibrary.get_spell(&"jolt"), Vector3(40, 0, 40))
	_check(reasons.has(&"no_target"), "targeted spells need a target")
	await _clear_world()


func _test_sandbox() -> void:
	print("-- sandbox")
	var scene: Node3D = load("res://systems/combat/sandbox/combat_sandbox.tscn").instantiate()
	root.add_child(scene)
	await _seconds(0.2)
	var caster: SpellCaster = scene.caster
	var target: TargetDummy = scene._dummies[0]
	var casts := [0]
	caster.spell_cast.connect(func(_s: SpellData) -> void: casts[0] += 1)
	for path in [1, 2, 3, 4]:
		scene._use_path(path)
		for slot in 7:
			caster.begin_rest()
			caster.end_rest()
			caster.stats.misfire_chance = 0.0
			caster.cast_slot(slot, target.health.get_target_position())
			await _seconds(3.2)
	_check(casts[0] >= 15, "every sandbox path casts its bar (%d casts)" % casts[0])
	_check(target.total_damage > 0.0, "sandbox spells hurt the dummies")
	scene.queue_free()
	await process_frame


# --- Helpers -----------------------------------------------------------------

func _new_world() -> void:
	_world = Node3D.new()
	_world.name = "World"
	root.add_child(_world)


func _clear_world() -> void:
	_world.queue_free()
	await process_frame


func _make_caster(source: SpellSource, at := Vector3.ZERO) -> SpellCaster:
	var body := Node3D.new()
	body.name = "Caster"
	var health := HealthComponent.new()
	health.name = "HealthComponent"
	health.team = &"player"
	health.max_health = 300.0
	body.add_child(health)
	var caster := SpellCaster.new()
	caster.name = "SpellCaster"
	caster.stats = CombatStats.new()
	caster.stats.crit_chance = 0.0
	caster.position = Vector3(0, 1, 0)
	caster.source = source
	body.add_child(caster)
	_world.add_child(body)
	body.position = at
	caster.set_source(source)
	caster.effects_parent = _world
	return caster


func _make_dummy(at: Vector3) -> TargetDummy:
	var dummy := TargetDummy.new()
	dummy.respawn_delay = 0.0
	dummy.max_health = 500.0
	dummy.position = at
	_world.add_child(dummy)
	return dummy


func _aim(dummy: TargetDummy) -> Vector3:
	return dummy.health.get_target_position()


func _collect_failures(caster: SpellCaster) -> Array[StringName]:
	var reasons: Array[StringName] = []
	caster.cast_failed.connect(func(_s: SpellData, reason: StringName) -> void: reasons.append(reason))
	return reasons


func _seconds(seconds: float) -> void:
	var elapsed := 0.0
	while elapsed < seconds:
		await process_frame
		elapsed += root.get_process_delta_time()


func _check(condition: bool, label: String) -> void:
	print(("ok   " if condition else "FAIL ") + label)
	if not condition:
		_failures.append(label)
