class_name SpellProjectile
extends Node3D
## A spell in flight. Moves itself each physics frame and tests hits along its
## path against the world (ray) and against enemy HealthComponents (distance to
## the segment), so it works without collision layer setup and can't tunnel.

const RADIUS := 0.25

var spell: SpellData
var context: SpellContext
var direction := Vector3.FORWARD
var travelled := 0.0

var _pierce_left := 0
var _speed := 0.0
var _visual: BoltVisual
var _power_scale := 1.0
var _hit: Array[HealthComponent] = []
var _exclude: Array[RID] = []
var wall_hit := false
var _wall_normal := Vector3.ZERO


func launch(p_spell: SpellData, p_context: SpellContext, origin: Vector3, aim: Vector3) -> void:
	spell = p_spell
	context = p_context
	_pierce_left = spell.pierce + (spell.charged_pierce if context.is_full_charge() else 0)
	_speed = spell.projectile_speed * lerpf(1.0, spell.charge_speed, context.charge)
	global_position = origin
	var to_aim := aim - origin
	direction = to_aim.normalized() if to_aim.length_squared() > 0.001 else -context.caster.global_basis.z
	if context.caster is CollisionObject3D:
		_exclude.append((context.caster as CollisionObject3D).get_rid())
	if spell.visual:
		_power_scale = lerpf(1.0, spell.visual.charge_scale, context.charge)
		_visual = BoltVisual.new()
		add_child(_visual)
		_visual.setup(spell.visual, _power_scale, get_parent())
		LaunchFlash.spawn(get_parent(), origin, direction, spell.visual, _power_scale)
	else:
		_build_visual()


func _physics_process(delta: float) -> void:
	if spell == null:
		return
	var step := minf(_speed * delta, spell.cast_range - travelled)
	var from := global_position
	var to := from + direction * step

	var wall_point: Variant = _cast_world(from, to)
	if wall_point != null:
		to = wall_point

	for target in _targets_along(from, to):
		var point := target.get_target_position()
		if spell.radius > 0.0:
			_finish(point)
			return
		if spell.visual:
			SpellImpact.spawn(get_parent(), point, Vector3.ZERO, spell.visual, _power_scale, target)
		_hit.append(target)
		SpellDelivery.hit_target(spell, context, target, point, get_parent(), _hit)
		if _pierce_left <= 0:
			_end()
			return
		_pierce_left -= 1

	global_position = to
	travelled += step
	if wall_point != null or travelled >= spell.cast_range - 0.001:
		_finish(to)


func _finish(point: Vector3) -> void:
	if spell.visual and (wall_hit or spell.radius > 0.0):
		SpellImpact.spawn(get_parent(), point, _wall_normal, spell.visual, _power_scale)
	elif spell.visual:
		# Ran out of range: fizzle out with a smaller pop.
		SpellImpact.spawn(get_parent(), point, Vector3.ZERO, spell.visual, _power_scale * 0.5)
	if spell.radius > 0.0 or spell.ground_duration > 0.0:
		SpellDelivery.impact(spell, context, point, get_parent())
	_end()


func _end() -> void:
	if _visual and is_instance_valid(_visual):
		_visual.detach()
	queue_free()


func _cast_world(from: Vector3, to: Vector3) -> Variant:
	var space := get_world_3d().direct_space_state
	if space == null:
		return null
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = _exclude
	query.collide_with_areas = false
	var result := space.intersect_ray(query)
	if result.is_empty():
		return null
	# Bodies with a HealthComponent are handled as targets, not walls.
	var collider := result.get("collider") as Node
	var health := HealthComponent.find_on(collider)
	if health and (health.team == context.team or health in _hit):
		_exclude.append(result["rid"])
		return _cast_world(from, to)
	if health:
		return null
	wall_hit = true
	_wall_normal = result["normal"]
	return result["position"]


## Enemies whose hit sphere touches the segment, nearest to `from` first.
func _targets_along(from: Vector3, to: Vector3) -> Array[HealthComponent]:
	var found: Array[HealthComponent] = []
	var segment := to - from
	var length_sq := segment.length_squared()
	for node in get_tree().get_nodes_in_group(HealthComponent.GROUP):
		var target := node as HealthComponent
		if target == null or target.is_dead or target.team == context.team or target in _hit:
			continue
		var center := target.get_target_position()
		var t := 0.0 if length_sq < 0.0001 else clampf((center - from).dot(segment) / length_sq, 0.0, 1.0)
		if center.distance_to(from + segment * t) <= target.hit_radius + RADIUS:
			found.append(target)
	found.sort_custom(func(a: HealthComponent, b: HealthComponent) -> bool:
		return a.get_target_position().distance_squared_to(from) < b.get_target_position().distance_squared_to(from))
	return found


func _build_visual() -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = RADIUS
	mesh.height = RADIUS * 2.0
	mesh_instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = spell.get_color()
	mesh_instance.material_override = material
	add_child(mesh_instance)
	var light := OmniLight3D.new()
	light.light_color = spell.get_color()
	light.omni_range = 3.0
	light.light_energy = 1.5
	add_child(light)
