class_name SpellDelivery
extends RefCounted
## Turns a resolved cast into hits: spawns projectiles, bursts areas, chains and
## applies effects. SpellCaster calls `deliver`; projectiles call back into
## `impact` and `apply_to`.

## How close to the aim point an enemy must be for a TARGETED spell to find it.
const TARGET_ASSIST_RADIUS := 4.0
const VFX_TIME := 0.35


## Fires `spell` from `origin` toward `aim`. `parent` holds spawned nodes.
static func deliver(spell: SpellData, context: SpellContext, origin: Vector3, aim: Vector3, parent: Node) -> void:
	context.origin = origin
	match spell.delivery:
		SpellData.Delivery.PROJECTILE:
			var projectile := SpellProjectile.new()
			parent.add_child(projectile)
			projectile.launch(spell, context, origin, aim)
		SpellData.Delivery.TARGETED:
			var target := find_target(context, origin, aim, spell.cast_range)
			if target:
				_spawn_flash(parent, target.get_target_position(), 0.4, spell.get_color())
				hit_target(spell, context, target, target.get_target_position(), parent)
		SpellData.Delivery.AREA_AT_TARGET:
			var offset := aim - origin
			if offset.length() > spell.cast_range:
				aim = origin + offset.normalized() * spell.cast_range
			impact(spell, context, aim, parent)
		SpellData.Delivery.AREA_AROUND_CASTER:
			burst(spell, context, origin, spell.radius, parent)
		SpellData.Delivery.CONE:
			_cone(spell, context, origin, aim, parent)
		SpellData.Delivery.SELF:
			if context.caster_health:
				_spawn_flash(parent, origin, 0.8, spell.get_color())
				apply_to(spell.effects, context.caster_health, context, origin)


## The enemy nearest the aim point, within range of the caster.
static func find_target(context: SpellContext, origin: Vector3, aim: Vector3, max_range: float) -> HealthComponent:
	var best: HealthComponent
	var best_distance := TARGET_ASSIST_RADIUS
	for target in HealthComponent.find_in_radius(context.caster.get_tree(), origin, max_range, context.team):
		var distance := target.get_target_position().distance_to(aim)
		var flat := Vector2(target.get_target_position().x - aim.x, target.get_target_position().z - aim.z).length()
		distance = minf(distance, flat)
		if distance <= best_distance + target.hit_radius:
			best = target
			best_distance = distance
	return best


## Where a spell lands at a point: a burst if it has a radius (with scatter and
## lingering ground), otherwise nothing (single-target spells use hit_target).
static func impact(spell: SpellData, context: SpellContext, point: Vector3, parent: Node) -> void:
	if spell.scatter_count > 0:
		var small_radius := spell.radius * 0.6
		for i in spell.scatter_count:
			var angle := TAU * i / spell.scatter_count
			var offset := Vector3(cos(angle), 0.0, sin(angle)) * spell.radius
			burst(spell, context.with_scale(context.scale * 0.5), point + offset, small_radius, parent)
	elif spell.radius > 0.0:
		burst(spell, context, point, spell.radius, parent)
	if spell.ground_duration > 0.0 and not spell.ground_effects.is_empty():
		var ground := SpellGroundArea.new()
		parent.add_child(ground)
		ground.start(spell, context, point)


## Applies the spell's effects to every enemy in the sphere.
static func burst(spell: SpellData, context: SpellContext, center: Vector3, radius: float, parent: Node) -> void:
	_spawn_flash(parent, center, radius, spell.get_color())
	for target in HealthComponent.find_in_radius(context.caster.get_tree(), center, radius, context.team):
		apply_to(spell.effects, target, context, center)


## A direct hit on one target, then any chain jumps.
static func hit_target(spell: SpellData, context: SpellContext, target: HealthComponent, point: Vector3, parent: Node) -> void:
	apply_to(spell.effects, target, context, point)
	if spell.chain_count <= 0:
		return
	var hit: Array[HealthComponent] = [target]
	var current := target
	var scale := context.scale
	for i in spell.chain_count:
		var next: HealthComponent
		for candidate in HealthComponent.find_in_radius(context.caster.get_tree(), current.get_target_position(), spell.chain_range, context.team):
			if candidate not in hit:
				next = candidate
				break
		if next == null:
			return
		scale *= spell.chain_falloff
		_spawn_flash(parent, next.get_target_position(), 0.4, spell.get_color())
		apply_to(spell.effects, next, context.with_scale(scale), current.get_target_position())
		hit.append(next)
		current = next


static func apply_to(effects: Array[SpellEffect], target: HealthComponent, context: SpellContext, point: Vector3) -> void:
	for effect in effects:
		if target.is_dead:
			return
		if effect:
			effect.apply(target, context, point)


static func _cone(spell: SpellData, context: SpellContext, origin: Vector3, aim: Vector3, parent: Node) -> void:
	var forward := aim - origin
	forward.y = 0.0
	forward = forward.normalized() if forward.length_squared() > 0.001 else Vector3.FORWARD
	var half_angle := deg_to_rad(spell.cone_angle * 0.5)
	_spawn_flash(parent, origin + forward * spell.radius * 0.5, spell.radius * 0.5, spell.get_color())
	for target in HealthComponent.find_in_radius(context.caster.get_tree(), origin, spell.radius, context.team):
		var to_target := target.get_target_position() - origin
		to_target.y = 0.0
		if to_target.length() <= target.hit_radius or forward.angle_to(to_target) <= half_angle:
			apply_to(spell.effects, target, context, origin)


## A short-lived glowing sphere so hits read in the sandbox. Art comes later.
static func _spawn_flash(parent: Node, at: Vector3, radius: float, color: Color) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var flash := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = maxf(radius, 0.2)
	mesh.height = mesh.radius * 2.0
	mesh.radial_segments = 16
	mesh.rings = 8
	flash.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(color, 0.45)
	flash.material_override = material
	parent.add_child(flash)
	flash.global_position = at
	var tween := flash.create_tween()
	tween.tween_property(material, "albedo_color:a", 0.0, VFX_TIME)
	tween.tween_callback(flash.queue_free)
