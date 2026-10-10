class_name ChoreTarget
extends Node3D
## Something in the world the opening asks you to use a trick on: the spoon on
## the kitchen table (Nudge), Ma's cold stove (Spark) and the jar on the fence
## post (Jolt). Spells really hit it (it carries a HealthComponent on the
## "prop" team), and only the right spell does the chore, with an effect you
## can't miss: the spoon flies, the stove roars alight, the jar leaps in a
## crackle of blue. Then it tells the quests (notify_event(event_name)).
##
## While `active`, a gold arrow bobs over it and it can be targeted; otherwise
## spells pass it by.

signal done
## A spell hit it that doesn't do this chore (the opening explains which does).
signal wrong_spell(spell: SpellData)

enum Kind { SPOON, STOVE, JAR }

@export var kind := Kind.SPOON
## The spell that does the chore.
@export var spell_id := &"nudge"
## Sent to QuestManager.notify_event when the chore is done.
@export var event_name := &"spoon_moved"
@export var label := "Spoon"

var is_done := false
var active := false:
	set(value):
		active = value
		_sync_active()
var health: HealthComponent
var beacon: Node3D

var _model: Node3D
var _fire: Node3D
var _light: OmniLight3D
var _glow_material: StandardMaterial3D
var _beacon_time := 0.0


func _ready() -> void:
	health = HealthComponent.new()
	health.name = "HealthComponent"
	health.team = &"prop"
	health.max_health = 100000.0
	add_child(health)
	health.damaged.connect(_on_damaged)
	match kind:
		Kind.SPOON:
			health.center_height = 0.0
			health.hit_radius = 0.6
			_build_spoon()
		Kind.STOVE:
			health.center_height = 0.55
			health.hit_radius = 0.75
			_build_stove()
		Kind.JAR:
			health.center_height = 1.25
			health.hit_radius = 0.55
			_build_jar()
	_build_beacon()
	_sync_active()


func _process(delta: float) -> void:
	if beacon != null and beacon.visible:
		_beacon_time += delta
		var arrow := beacon.get_node(^"Arrow") as Node3D
		arrow.position.y = 0.15 * sin(_beacon_time * 3.0)
		arrow.rotation.y += delta * 2.0
	if _light != null and is_done and kind == Kind.STOVE:
		_light.light_energy = 2.4 + 0.5 * sin(Time.get_ticks_msec() * 0.013) + 0.3 * sin(Time.get_ticks_msec() * 0.031)


## Shows the chore as already done, without the effect (after loading a save).
func set_done_quietly() -> void:
	if is_done:
		return
	is_done = true
	active = false
	match kind:
		Kind.SPOON:
			_model.position = Vector3(0.9, -0.88, 0.7)
			_model.rotation = Vector3(0, 0.8, PI * 0.5)
		Kind.STOVE:
			_light_stove(false)
		Kind.JAR:
			_model.position = Vector3(0.8, -1.15, 0.6)
			_model.rotation = Vector3(PI * 0.5, 0.3, 0)


## Does the chore as if the right spell hit it from `from` (tests, and the hit handler).
func trigger(from: Vector3) -> void:
	if is_done:
		return
	is_done = true
	active = false
	match kind:
		Kind.SPOON:
			_fly_spoon(from)
		Kind.STOVE:
			_light_stove(true)
		Kind.JAR:
			_jolt_jar()
	done.emit()
	var quests := QuestManager.find(get_tree())
	if quests != null:
		quests.notify_event(event_name)


func _on_damaged(hit: Hit, amount: float) -> void:
	health.heal(amount)
	if is_done or not active:
		return
	var id: StringName = hit.spell.id if hit != null and hit.spell != null else &""
	if id == spell_id:
		var from := global_position - Vector3.FORWARD
		if hit.source is Node3D and is_instance_valid(hit.source):
			from = (hit.source as Node3D).global_position
		trigger(from)
	else:
		_shrug()
		wrong_spell.emit(hit.spell if hit != null else null)


func _sync_active() -> void:
	if beacon != null:
		beacon.visible = active
	if health == null or not health.is_inside_tree():
		return
	if active and not health.is_in_group(HealthComponent.GROUP):
		health.add_to_group(HealthComponent.GROUP)
	elif not active and health.is_in_group(HealthComponent.GROUP):
		health.remove_from_group(HealthComponent.GROUP)


# --- reactions ---------------------------------------------------------------

## The wrong trick: a little wobble so you can see it was hit, but nothing happens.
func _shrug() -> void:
	if _model == null:
		return
	var tween := create_tween()
	var base := _model.rotation
	tween.tween_property(_model, "rotation:z", base.z + 0.15, 0.06)
	tween.tween_property(_model, "rotation:z", base.z - 0.15, 0.08)
	tween.tween_property(_model, "rotation:z", base.z, 0.06)


func _fly_spoon(from: Vector3) -> void:
	var push := global_position - from
	push.y = 0.0
	push = push.normalized() if push.length_squared() > 0.01 else Vector3.FORWARD
	var local_push := global_basis.inverse() * push
	var land := local_push * 2.6 + Vector3(0, -0.88, 0)
	var start := _model.position
	FeedbackSfx.play(self, &"clink", -4.0)
	_puff(Vector3.ZERO, Color(0.95, 0.9, 0.8), 10)
	var tween := create_tween()
	tween.tween_method(func(t: float) -> void:
		var p := start.lerp(land, t)
		p.y += 1.1 * sin(t * PI) * (1.0 - t * 0.3)
		_model.position = p
		_model.rotation = Vector3(t * TAU * 2.0, t * 4.0, 0.0), 0.0, 1.0, 0.7)
	# Two little bounces where it lands.
	tween.tween_callback(func() -> void:
		FeedbackSfx.play(self, &"clink", -6.0, 0.8)
		_puff(land, Color(0.7, 0.6, 0.45), 8))
	tween.tween_property(_model, "position:y", land.y + 0.25, 0.12).set_ease(Tween.EASE_OUT)
	tween.tween_property(_model, "position:y", land.y, 0.12).set_ease(Tween.EASE_IN)
	tween.tween_property(_model, "position:y", land.y + 0.08, 0.07).set_ease(Tween.EASE_OUT)
	tween.tween_property(_model, "position:y", land.y, 0.07).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(_model, "rotation", Vector3(0, 0.8, PI * 0.5), 0.14)


func _light_stove(with_effect: bool) -> void:
	_glow_material.albedo_color = Color(1.0, 0.55, 0.2)
	_glow_material.emission_enabled = true
	_glow_material.emission = Color(1.0, 0.45, 0.12)
	_glow_material.emission_energy_multiplier = 3.0
	_fire.visible = true
	_light.visible = true
	_light.light_energy = 2.4
	if with_effect:
		FeedbackSfx.play(self, &"whoomp", 0.0)
		_puff(Vector3(0, 0.6, 0.5), Color(1.0, 0.6, 0.2), 24, 3.0)
		_light.light_energy = 9.0
		_fire.scale = Vector3.ONE * 2.2
		var tween := create_tween()
		tween.tween_property(_fire, "scale", Vector3.ONE, 0.6).set_ease(Tween.EASE_OUT)


func _jolt_jar() -> void:
	FeedbackSfx.play(self, &"zap", 0.0)
	var flash := OmniLight3D.new()
	flash.light_color = Color(0.5, 0.75, 1.0)
	flash.light_energy = 8.0
	flash.omni_range = 7.0
	flash.position = Vector3(0, 1.4, 0)
	add_child(flash)
	var arcs := _arcs()
	var start := _model.position
	var land := Vector3(0.8, -1.15, 0.6)
	var tween := create_tween()
	tween.tween_property(flash, "light_energy", 0.0, 0.7)
	tween.parallel().tween_method(func(t: float) -> void:
		var p := start.lerp(land, t)
		p.y += 1.6 * sin(t * PI)
		_model.position = p
		_model.rotation = Vector3(t * PI * 0.5, t * TAU * 1.5, 0.0), 0.0, 1.0, 0.8)
	tween.tween_callback(func() -> void:
		flash.queue_free()
		arcs.queue_free()
		FeedbackSfx.play(self, &"clink", -8.0, 0.6)
		_puff(land, Color(0.7, 0.6, 0.45), 8))


## Jagged blue lines that flicker around the jar for a moment.
func _arcs() -> Node3D:
	var holder := Node3D.new()
	_model.add_child(holder)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.7, 0.88, 1.0)
	material.emission_enabled = true
	material.emission = Color(0.55, 0.8, 1.0)
	material.emission_energy_multiplier = 6.0
	var mesh := MeshInstance3D.new()
	var lines := ImmediateMesh.new()
	mesh.mesh = lines
	mesh.material_override = material
	holder.add_child(mesh)
	var rng := RandomNumberGenerator.new()
	var redraw := func() -> void:
		lines.clear_surfaces()
		lines.surface_begin(Mesh.PRIMITIVE_LINES)
		for arc in 6:
			var angle := rng.randf() * TAU
			var p := Vector3(cos(angle) * 0.2, rng.randf_range(0.0, 0.4), sin(angle) * 0.2)
			for step in 4:
				var q := p + Vector3(cos(angle), 0, sin(angle)) * 0.15 + Vector3(rng.randf_range(-0.12, 0.12), rng.randf_range(-0.12, 0.2), rng.randf_range(-0.12, 0.12))
				lines.surface_add_vertex(p)
				lines.surface_add_vertex(q)
				p = q
		lines.surface_end()
	redraw.call()
	var timer := Timer.new()
	timer.wait_time = 0.05
	timer.autostart = true
	timer.timeout.connect(redraw)
	holder.add_child(timer)
	return holder


## A one-shot burst of little particles (dust, embers).
func _puff(at: Vector3, color: Color, amount: int, speed := 1.6) -> void:
	var particles := CPUParticles3D.new()
	particles.one_shot = true
	particles.emitting = false
	particles.amount = amount
	particles.lifetime = 0.7
	particles.explosiveness = 1.0
	particles.direction = Vector3.UP
	particles.spread = 70.0
	particles.initial_velocity_min = speed * 0.5
	particles.initial_velocity_max = speed
	particles.gravity = Vector3(0, -3.0, 0)
	particles.scale_amount_min = 0.5
	particles.scale_amount_max = 1.0
	var quad := SphereMesh.new()
	quad.radius = 0.05
	quad.height = 0.1
	quad.radial_segments = 6
	quad.rings = 3
	particles.mesh = quad
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	particles.material_override = material
	particles.position = at
	add_child(particles)
	particles.emitting = true
	get_tree().create_timer(1.5).timeout.connect(particles.queue_free)


# --- models ------------------------------------------------------------------

func _build_spoon() -> void:
	_model = Node3D.new()
	_model.name = "Spoon"
	add_child(_model)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.82, 0.84, 0.88)
	metal.metallic = 0.8
	metal.roughness = 0.3
	_box(_model, Vector3(0.32, 0.025, 0.045), Vector3(-0.06, 0.012, 0), metal)
	var bowl := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.06
	sphere.height = 0.05
	bowl.mesh = sphere
	bowl.material_override = metal
	bowl.position = Vector3(0.13, 0.02, 0)
	bowl.scale = Vector3(1.3, 1.0, 1.0)
	_model.add_child(bowl)


func _build_stove() -> void:
	_model = Node3D.new()
	_model.name = "Stove"
	add_child(_model)
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.18, 0.18, 0.2)
	iron.roughness = 0.7
	_box(_model, Vector3(0.9, 0.9, 0.9), Vector3(0, 0.45, 0), iron)
	_box(_model, Vector3(0.2, 1.2, 0.2), Vector3(0.15, 1.4, -0.25), iron)
	_glow_material = StandardMaterial3D.new()
	_glow_material.albedo_color = Color(0.06, 0.05, 0.05)
	_box(_model, Vector3(0.45, 0.28, 0.05), Vector3(0, 0.35, 0.46), _glow_material)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.9, 0.9, 0.9)
	shape.shape = box
	shape.position = Vector3(0, 0.45, 0)
	body.add_child(shape)
	_model.add_child(body)

	# Fire in the grate and smoke from the pipe, hidden until it's lit.
	_fire = Node3D.new()
	_fire.name = "Fire"
	_fire.position = Vector3(0, 0.3, 0.5)
	_fire.visible = false
	_model.add_child(_fire)
	var flames := CPUParticles3D.new()
	flames.amount = 24
	flames.lifetime = 0.5
	flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	flames.emission_box_extents = Vector3(0.18, 0.03, 0.04)
	flames.direction = Vector3.UP
	flames.spread = 15.0
	flames.initial_velocity_min = 0.4
	flames.initial_velocity_max = 0.9
	flames.gravity = Vector3(0, 0.8, 0)
	flames.scale_amount_min = 0.6
	flames.scale_amount_max = 1.2
	var flame_mesh := SphereMesh.new()
	flame_mesh.radius = 0.07
	flame_mesh.height = 0.16
	flame_mesh.radial_segments = 6
	flame_mesh.rings = 3
	flames.mesh = flame_mesh
	var flame_material := StandardMaterial3D.new()
	flame_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_material.vertex_color_use_as_albedo = true
	flame_material.albedo_color = Color(1.0, 0.6, 0.15)
	flame_material.emission_enabled = true
	flame_material.emission = Color(1.0, 0.5, 0.1)
	flame_material.emission_energy_multiplier = 4.0
	flames.material_override = flame_material
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.9, 0.4))
	ramp.set_color(1, Color(0.9, 0.2, 0.05))
	flames.color_ramp = ramp
	_fire.add_child(flames)
	var smoke := CPUParticles3D.new()
	smoke.amount = 14
	smoke.lifetime = 2.6
	smoke.position = Vector3(0.15, 1.75, -0.75)
	smoke.direction = Vector3.UP
	smoke.spread = 10.0
	smoke.initial_velocity_min = 0.5
	smoke.initial_velocity_max = 0.8
	smoke.gravity = Vector3(0.25, 0.1, 0)
	smoke.scale_amount_min = 1.0
	smoke.scale_amount_max = 2.2
	var puff := SphereMesh.new()
	puff.radius = 0.12
	puff.height = 0.24
	puff.radial_segments = 8
	puff.rings = 4
	smoke.mesh = puff
	var smoke_material := StandardMaterial3D.new()
	smoke_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smoke_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke_material.albedo_color = Color(0.75, 0.75, 0.78, 0.45)
	smoke.material_override = smoke_material
	_fire.add_child(smoke)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.6, 0.25)
	_light.omni_range = 6.0
	_light.position = Vector3(0, 0.6, 0.9)
	_light.visible = false
	_model.add_child(_light)


func _build_jar() -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.45, 0.32, 0.2)
	_box(self, Vector3(0.18, 1.1, 0.18), Vector3(0, 0.55, 0), wood)
	_model = Node3D.new()
	_model.name = "Jar"
	_model.position = Vector3(0, 1.1, 0)
	add_child(_model)
	var clay := StandardMaterial3D.new()
	clay.albedo_color = Color(0.72, 0.42, 0.26)
	var jar := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.1
	cylinder.bottom_radius = 0.13
	cylinder.height = 0.3
	jar.mesh = cylinder
	jar.material_override = clay
	jar.position = Vector3(0, 0.15, 0)
	_model.add_child(jar)
	var lid := StandardMaterial3D.new()
	lid.albedo_color = Color(0.55, 0.4, 0.25)
	_box(_model, Vector3(0.22, 0.04, 0.22), Vector3(0, 0.32, 0), lid)


func _build_beacon() -> void:
	beacon = Node3D.new()
	beacon.name = "Beacon"
	var top := 1.0
	match kind:
		Kind.SPOON:
			top = 0.75
		Kind.STOVE:
			top = 2.3
		Kind.JAR:
			top = 2.1
	beacon.position = Vector3(0, top, 0)
	add_child(beacon)
	var arrow := MeshInstance3D.new()
	arrow.name = "Arrow"
	var cone := CylinderMesh.new()
	cone.top_radius = 0.22
	cone.bottom_radius = 0.0
	cone.height = 0.45
	cone.radial_segments = 4
	arrow.mesh = cone
	var gold := StandardMaterial3D.new()
	gold.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gold.albedo_color = Color(1.0, 0.82, 0.3)
	gold.no_depth_test = true
	gold.render_priority = 5
	arrow.material_override = gold
	beacon.add_child(arrow)
	var text := Label3D.new()
	text.text = label
	text.font_size = 48
	text.outline_size = 12
	text.modulate = Color(1.0, 0.9, 0.6)
	text.outline_modulate = Color(0.05, 0.03, 0.02, 0.9)
	text.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	text.no_depth_test = true
	text.fixed_size = true
	text.pixel_size = 0.0008
	text.position = Vector3(0, 0.5, 0)
	beacon.add_child(text)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.85, 0.45)
	glow.light_energy = 0.8
	glow.omni_range = 1.6
	glow.position = Vector3(0, -top + 0.3, 0.2)
	beacon.add_child(glow)


func _box(parent: Node3D, size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	mesh.position = at
	parent.add_child(mesh)
	return mesh
