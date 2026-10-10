extends SceneTree
## Headless tests for Spark's charge-up, hit feedback and effects.
## Run: godot --headless --path . --fixed-fps 60 --script res://systems/combat/tests/test_spark.gd

var _failures: PackedStringArray = []
var _world: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	SpellLibrary.reload()
	await _test_tap_and_charge()
	await _test_charge_rules()
	await _test_effects_clean_up()
	await _test_feedback()
	await _test_props_and_aim()
	_test_sounds()
	await _test_hitstop()

	if _failures.is_empty():
		print("SPARK TESTS PASSED")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: ", f)
		quit(1)


func _test_tap_and_charge() -> void:
	print("-- tap and charge")
	_new_world()
	var caster := _make_caster()
	var spark := caster.get_cantrip()
	_check(spark.chargeable and spark.visual != null, "Spark is chargeable and has its look")

	var a := _make_dummy(Vector3(0, 0, -8))
	var hits: Array = []
	caster.hit_landed.connect(func(t: HealthComponent, amount: float, crit: bool, killed: bool, s: SpellData, charge: float) -> void:
		hits.append({"target": t, "amount": amount, "charge": charge, "killed": killed}))

	# A quick tap is an ordinary Spark.
	_check(caster.begin_charge(spark), "pressing starts a charge")
	await _seconds(0.05)
	caster.release_charge(_aim(a))
	await _seconds(0.8)
	_check(is_equal_approx(a.total_damage, 6.0), "a tap fires a normal 6-damage Spark (%.1f)" % a.total_damage)
	_check(hits.size() == 1 and is_zero_approx(hits[0]["charge"]), "hit_landed reports the hit with no charge")

	# A full charge: triple damage, pierces, jumps and knocks back.
	await _clear_world()
	_new_world()
	caster = _make_caster()
	hits.clear()
	caster.hit_landed.connect(func(t: HealthComponent, amount: float, _c: bool, _k: bool, _s: SpellData, charge: float) -> void:
		hits.append({"target": t, "amount": amount, "charge": charge}))
	var front := _make_dummy(Vector3(0, 0, -6))
	var behind := _make_dummy(Vector3(0, 0, -11))
	var side := _make_dummy(Vector3(4, 0, -6))
	var pushed := [Vector3.ZERO]
	front.health.knocked_back.connect(func(i: Vector3) -> void: pushed[0] = i)
	var full := [false]
	caster.charge_full.connect(func(_s: SpellData) -> void: full[0] = true)
	caster.begin_charge(spark)
	await _seconds(0.6)
	var mid := caster.get_charge()
	_check(mid > 0.2 and mid < 0.8, "charge builds while held (%.2f)" % mid)
	_check(is_equal_approx(caster.get_cast_progress(), mid), "the cast bar shows the charge")
	await _seconds(0.7)
	_check(full[0] and is_equal_approx(caster.get_charge(), 1.0), "charge_full fires at full charge")
	caster.release_charge(_aim(front))
	await _seconds(1.0)
	_check(is_equal_approx(front.total_damage, 18.0), "a full charge hits for triple damage (%.1f)" % front.total_damage)
	_check(behind.total_damage > 0.0, "a full charge pierces to the enemy behind (%.1f)" % behind.total_damage)
	_check(side.total_damage > 0.0, "a full charge jumps to a nearby enemy (%.1f)" % side.total_damage)
	_check(pushed[0].z < -3.0, "a full charge knocks the target back (%.1f)" % pushed[0].z)
	_check(hits.all(func(h: Dictionary) -> bool: return is_equal_approx(h["charge"], 1.0)), "every hit reports the full charge")
	await _clear_world()


func _test_charge_rules() -> void:
	print("-- charge rules")
	_new_world()
	var caster := _make_caster()
	var spark := caster.get_cantrip()
	var reasons: Array[StringName] = []
	caster.cast_failed.connect(func(_s: SpellData, r: StringName) -> void: reasons.append(r))
	var ended: Array = []
	caster.charge_ended.connect(func(_s: SpellData, released: bool) -> void: ended.append(released))

	caster.begin_charge(spark)
	caster.cast_slot(1, Vector3(0, 1, -5))
	_check(reasons.has(&"busy"), "other spells can't be cast mid-charge")
	caster.health.apply_status(Status.Kind.STUN, 0.3)
	await _seconds(0.05)
	_check(not caster.is_charging() and ended == [false], "a stun cancels the charge")
	await _seconds(0.4)

	var jolt := SpellLibrary.get_spell(&"jolt")
	_check(not caster.begin_charge(jolt), "spells that aren't chargeable don't charge")
	_check(not caster.release_charge(Vector3.ZERO), "releasing with nothing charging does nothing")

	# Launch point follows a character model's casting hand when there is one.
	var rig := _FakeRig.new()
	caster.get_parent().add_child(rig)
	rig.hand.position = Vector3(0.4, 1.5, -0.3)
	_check(caster.get_launch_point().is_equal_approx(caster.get_parent().global_position + Vector3(0.4, 1.5, -0.3)), "spells leave from the model's casting hand")
	caster.begin_charge(spark)
	await _seconds(0.5)
	_check(rig.magic > 0.0, "charging lights up the hand magic (%.2f)" % rig.magic)
	caster.release_charge(Vector3(0, 1, -10))
	_check(is_zero_approx(rig.magic), "releasing clears the hand magic")
	await _clear_world()


class _FakeRig extends Node3D:
	var hand := Marker3D.new()
	var magic := 0.0

	func _init() -> void:
		add_child(hand)

	func get_cast_point(_side := "r") -> Marker3D:
		return hand

	func set_magic_level(level: float) -> void:
		magic = level


func _test_effects_clean_up() -> void:
	print("-- effects")
	_new_world()
	var caster := _make_caster()
	var a := _make_dummy(Vector3(0, 0, -8))
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6, 4, 0.5)
	shape.shape = box
	wall.add_child(shape)
	_world.add_child(wall)
	wall.position = Vector3(8, 1, -6)
	await physics_frame

	caster.cast_cantrip(_aim(a))
	await _seconds(0.1)
	_check(_count(BoltVisual) == 1 and _count(BoltTrail) == 1, "the bolt flies with its trail")
	_check(_count(LaunchFlash) == 1, "the hand flashes on launch")
	await _seconds(0.4)
	_check(_count(SpellImpact) >= 1, "the hit bursts")
	await _seconds(0.4)
	caster.cast_cantrip(Vector3(8, 1, -6))
	await _seconds(0.6)
	_check(_count(ScorchMark) == 1, "hitting a wall leaves a scorch mark")
	caster.begin_charge(caster.get_cantrip())
	await _seconds(0.3)
	caster.release_charge(Vector3(0, 1, -40))
	await _seconds(8.0)
	_check(_count(BoltVisual) + _count(BoltTrail) + _count(SpellImpact) + _count(LaunchFlash) + _count(ScorchMark) + _count(LightningArcs) == 0, "every effect cleans itself up")
	_check(_count(AudioStreamPlayer3D) == 0, "no sounds are left playing")
	_check(_count(SparkParticles) == 0, "no particles are left behind")
	await _clear_world()


func _test_feedback() -> void:
	print("-- feedback")
	_new_world()
	var caster := _make_caster()
	var feedback := CombatFeedback.new()
	feedback.caster = caster
	caster.get_parent().add_child(feedback)
	await process_frame
	_check(feedback.reticle != null, "the reticle is shown")
	var a := _make_dummy(Vector3(0, 0, -6))
	a.health.max_health = 5.0
	a.health.revive()
	caster.begin_charge(caster.get_cantrip())
	await _seconds(0.4)
	_check(feedback.reticle.charging and feedback.reticle.charge > 0.0, "the reticle ring fills while charging")
	_check(_count(ChargeOrb) == 1, "power gathers in the hand")
	caster.release_charge(_aim(a))
	await _seconds(0.1)
	_check(_count(ChargeOrb) == 0, "the orb is spent on release")
	await _seconds(0.4)
	_check(_count(DamageNumber) >= 1, "damage numbers pop off the target")
	_check(a.health.is_dead and feedback.reticle._kill_time > 0.0, "a kill shows the kill marker")
	await _seconds(1.5)
	_check(is_zero_approx(Engine.time_scale - 1.0), "time runs normally after the hit")
	await _clear_world()


func _test_props_and_aim() -> void:
	print("-- props, reticle tint, hurt kick")
	_new_world()
	var caster := _make_caster()
	var camera := Camera3D.new()
	_world.add_child(camera)
	camera.position = Vector3(0, 1.5, 0)
	camera.current = true
	var feedback := CombatFeedback.new()
	feedback.caster = caster
	caster.get_parent().add_child(feedback)
	await process_frame
	feedback.reticle.force_visible = true

	var prop := _make_dummy(Vector3(0, 0.5, -6))
	prop.health.team = &"prop"
	await _seconds(0.1)
	_check(feedback.target_under_reticle() == prop.health, "the reticle finds the prop it's over")
	_check(feedback.reticle.target_tint.is_equal_approx(CombatFeedback.PROP_TINT), "the reticle turns gold over a prop")
	caster.cast_cantrip(_aim(prop))
	await _seconds(0.6)
	_check(prop.total_damage > 0.0, "props still take the hit")
	_check(_count(DamageNumber) == 0 and feedback.reticle._hit_time < 0.0, "props get no damage numbers or hit markers")

	prop.queue_free()
	_make_dummy(Vector3(0.3, 0.5, -8))
	await _seconds(0.1)
	_check(feedback.reticle.target_tint.is_equal_approx(CombatFeedback.ENEMY_TINT), "the reticle turns red over an enemy")
	camera.rotation.y = 1.2
	await _seconds(0.1)
	_check(feedback.reticle.target_tint.a == 0.0, "and goes back to normal off target")

	var trauma_before := feedback.kick.trauma
	caster.health.take_damage(Hit.new(30.0, DamageType.Kind.PHYSICAL, null))
	_check(feedback.kick.trauma > trauma_before + 0.15, "getting hurt kicks the camera (%.2f)" % feedback.kick.trauma)
	await _clear_world()


func _test_sounds() -> void:
	print("-- sounds")
	for sound in [&"zap", &"crack", &"hum", &"ping", &"crackle"]:
		var stream := SpellSfx.get_stream(sound)
		_check(stream.data.size() > 2000, "%s is synthesised (%d bytes)" % [sound, stream.data.size()])
	_check(SpellSfx.get_stream(&"hum").loop_mode == AudioStreamWAV.LOOP_FORWARD, "the charge hum loops")
	_check(SpellSfx.get_stream(&"zap") == SpellSfx.get_stream(&"zap"), "sounds are built once")


func _test_hitstop() -> void:
	print("-- hitstop")
	CameraKick.hitstop(self, 0.05)
	_check(Engine.time_scale < 0.5, "hit-stop slows time")
	CameraKick.hitstop(self, 0.05)
	var start := Time.get_ticks_msec()
	while Engine.time_scale < 1.0 and Time.get_ticks_msec() - start < 1000:
		await process_frame
	_check(is_equal_approx(Engine.time_scale, 1.0), "and lets go")


# --- Helpers -----------------------------------------------------------------

func _new_world() -> void:
	_world = Node3D.new()
	_world.name = "World"
	root.add_child(_world)


func _clear_world() -> void:
	_world.queue_free()
	await process_frame


func _make_caster() -> SpellCaster:
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
	body.add_child(caster)
	_world.add_child(body)
	caster.set_source(TrickSet.new())
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


func _count(type: Variant) -> int:
	var n := 0
	for node in _world.find_children("*", "", true, false):
		if is_instance_of(node, type):
			n += 1
	return n


func _seconds(seconds: float) -> void:
	var elapsed := 0.0
	while elapsed < seconds:
		await process_frame
		elapsed += root.get_process_delta_time()


func _check(condition: bool, label: String) -> void:
	print(("ok   " if condition else "FAIL ") + label)
	if not condition:
		_failures.append(label)
