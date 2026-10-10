extends Node3D
## Combat sandbox: try every path's spells on practice dummies.
## Open res://systems/combat/sandbox/combat_sandbox.tscn and press F6.
##
## WASD move · mouse aims · left click cantrip (hold to charge Spark) · right click / 1-6 bar spells
## F1 tricks · F2 wizard · F3 mage · F4 sorcerer · T rest · R reset dummies

const SPEED := 6.0

var caster: SpellCaster
var _body: CharacterBody3D
var _camera: Camera3D
var _hud: Label
var _last_event := ""
var _dummies: Array[TargetDummy] = []
var feedback: CombatFeedback


func _ready() -> void:
	_build_environment()
	_build_caster()
	_build_dummies()
	_build_hud()
	_use_path(4)


func _physics_process(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var speed := SPEED * caster.health.get_move_speed_multiplier()
	_body.velocity = Vector3(input.x, 0.0, input.y) * speed
	if not _body.is_on_floor():
		_body.velocity.y -= 20.0 * delta
	_body.move_and_slide()
	_camera.global_position = _body.global_position + Vector3(0, 10, 8)
	_camera.look_at(_body.global_position + Vector3(0, 0, -4))
	var aim := _mouse_aim()
	var flat := Vector3(aim.x, _body.global_position.y, aim.z)
	if flat.distance_to(_body.global_position) > 0.1:
		_body.look_at(flat)


func _process(_delta: float) -> void:
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				var cantrip := caster.get_cantrip()
				if cantrip and cantrip.chargeable:
					caster.begin_charge(cantrip)
				else:
					caster.cast_cantrip(_mouse_aim())
			MOUSE_BUTTON_RIGHT:
				caster.cast_slot(6, _mouse_aim())
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT and caster.is_charging():
		caster.release_charge(_mouse_aim())
	elif event is InputEventKey and event.pressed and not event.echo:
		var key: Key = event.physical_keycode
		if key >= KEY_1 and key <= KEY_6:
			caster.cast_slot(key - KEY_1, _mouse_aim())
		elif key >= KEY_F1 and key <= KEY_F4:
			_use_path(key - KEY_F1 + 1)
		elif key == KEY_T:
			caster.begin_rest()
			caster.end_rest()
			_last_event = "Rested: full health and resource"
		elif key == KEY_R:
			for dummy in _dummies:
				dummy.reset()


## 1 tricks, 2 wizard, 3 mage, 4 sorcerer. Each gets a level 11 kit.
func _use_path(index: int) -> void:
	var source: SpellSource
	match index:
		1:
			source = TrickSet.new()
			source.level = 4
		2:
			var book := WizardSpellbook.new(11)
			for id in [&"fireball", &"frost_lance", &"arcane_ward"]:
				book.add_book(id, 4)
			book.add_book(&"fireball_searing")
			book.is_resting = true
			for id in [&"fireball", &"frost_lance", &"arcane_ward"]:
				book.inscribe(id)
				book.upgrade(id)
			book.choose_variant(&"fireball", &"fireball_searing")
			book.prepare([&"fireball", &"frost_lance", &"arcane_ward"])
			book.is_resting = false
			source = book
		3:
			var codex := MageCodex.new(11)
			codex.grant_starting_kit()
			for word in [&"chill", &"water", &"mend", &"flesh", &"break", &"earth"]:
				codex.learn_word(word)
			for pair in [[&"chill", &"water"], [&"mend", &"flesh"]]:
				codex.discovered[MageCodex.pair_key(pair[0], pair[1])] = true
				codex.formulated[MageCodex.pair_key(pair[0], pair[1])] = true
				codex.bar_order.append(MageCodex.pair_key(pair[0], pair[1]))
			# Break + Earth stays a raw experiment on the bar to show half power.
			codex.discovered[MageCodex.pair_key(&"break", &"earth")] = true
			codex.bar_order.append(MageCodex.pair_key(&"break", &"earth"))
			source = codex
		_:
			var tree := SorcererSpellTree.new(11)
			tree.points = 10
			for id in [&"spark_bolt", &"static_field", &"chain_lightning", &"shove", &"barrier", &"flare", &"overflow"]:
				tree.learn(id)
			source = tree
	caster.set_source(source)
	_last_event = "Switched to %s" % ["", "tricks", "wizard", "mage", "sorcerer"][index]


func _mouse_aim() -> Vector3:
	var mouse := get_viewport().get_mouse_position()
	var from := _camera.project_ray_origin(mouse)
	var dir := _camera.project_ray_normal(mouse)
	var hit: Variant = Plane(Vector3.UP, 1.0).intersects_ray(from, dir)
	return hit if hit != null else _body.global_position - _body.global_basis.z * 10.0


func _build_environment() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.16, 0.17, 0.22)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.5, 0.5, 0.55)
	# Same tonemap and bloom as the world, so spell effects read the same here.
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment.tonemap_white = 4.0
	env.environment.glow_enabled = true
	env.environment.glow_bloom = 0.04
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 60)
	shape.shape = box
	shape.position.y = -0.5
	floor_body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	mesh.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.32, 0.36, 0.3)
	mesh.material_override = material
	floor_body.add_child(mesh)
	add_child(floor_body)
	_camera = Camera3D.new()
	_camera.fov = 50.0
	add_child(_camera)


func _build_caster() -> void:
	_body = CharacterBody3D.new()
	_body.name = "Arcanist"
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	shape.shape = capsule
	shape.position.y = 0.9
	_body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var capsule_mesh := CapsuleMesh.new()
	capsule_mesh.radius = 0.4
	capsule_mesh.height = 1.8
	mesh.mesh = capsule_mesh
	mesh.position.y = 0.9
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.35, 0.4, 0.75)
	mesh.material_override = material
	_body.add_child(mesh)
	var health := HealthComponent.new()
	health.name = "HealthComponent"
	health.team = &"player"
	health.max_health = 250.0
	_body.add_child(health)
	caster = SpellCaster.new()
	caster.name = "SpellCaster"
	caster.position = Vector3(0, 1.2, -0.5)
	caster.effects_parent = self
	_body.add_child(caster)
	add_child(_body)
	feedback = CombatFeedback.new()
	feedback.caster = caster
	# The sandbox aims with the cursor, so no center reticle.
	feedback.show_reticle = false
	_body.add_child(feedback)
	caster.misfired.connect(func(s: SpellData) -> void: _last_event = "%s misfired! Sparks fly harmlessly." % s.display_name)
	caster.cast_failed.connect(func(s: SpellData, reason: StringName) -> void:
		_last_event = "%s: %s" % [s.display_name if s else "Empty slot", String(reason).replace("_", " ")])
	caster.spell_cast.connect(func(s: SpellData) -> void: _last_event = "Cast %s" % s.display_name)
	caster.cast_interrupted.connect(func(s: SpellData) -> void: _last_event = "%s interrupted" % s.display_name)


func _build_dummies() -> void:
	var spots := [Vector3(0, 0, -8), Vector3(2.5, 0, -9), Vector3(-2.5, 0, -9), Vector3(6, 0, -14), Vector3(-7, 0, -6)]
	for i in spots.size():
		var dummy := TargetDummy.new()
		dummy.position = spots[i]
		if i == 3:
			dummy.tier = HealthComponent.Tier.ELITE
			dummy.armor = 50.0
			dummy.max_health = 400.0
		if i == 4:
			dummy.resistances = {DamageType.Kind.FIRE: 0.5, DamageType.Kind.COLD: -0.5}
		add_child(dummy)
		_dummies.append(dummy)
	var wall := CSGBox3D.new()
	wall.use_collision = true
	wall.size = Vector3(4, 3, 0.5)
	wall.position = Vector3(-7, 1.5, -3)
	add_child(wall)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(16, 12)
	_hud.add_theme_font_size_override("font_size", 18)
	_hud.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud.add_theme_constant_override("outline_size", 6)
	layer.add_child(_hud)


func _update_hud() -> void:
	var lines: PackedStringArray = []
	var res := caster.caster_resource
	lines.append("Health %d / %d   %s %d / %d%s" % [
		caster.health.health, caster.health.max_health, res.get_display_name(), res.current, res.maximum,
		"   OVERSTRAINED" if res is StrainPool and (res as StrainPool).is_overstrained() else ""])
	if caster.is_casting():
		lines.append("Casting %s  [%s]" % [caster.get_casting_spell().display_name, "#".repeat(roundi(caster.get_cast_progress() * 20)).rpad(20, ".")])
	else:
		lines.append("")
	var cantrip := caster.get_cantrip()
	lines.append("LMB  %s" % (cantrip.display_name if cantrip else "-"))
	var bar := caster.get_action_bar()
	for i in bar.size():
		var spell := bar[i]
		var key := "RMB" if i == 6 else str(i + 1)
		if spell == null:
			lines.append("%s    -" % key)
			continue
		var cd := caster.get_cooldown_remaining(spell)
		lines.append("%s    %s  (%d %s, %s)%s" % [key, spell.display_name, roundi(caster.get_cost(spell)), res.get_display_name().to_lower(),
			caster.source.describe_growth(spell), "  cd %.1f" % cd if cd > 0.0 else ""])
	lines.append("")
	lines.append(_last_event)
	lines.append("F1 tricks  F2 wizard  F3 mage  F4 sorcerer  ·  T rest  ·  R reset dummies")
	_hud.text = "\n".join(lines)
