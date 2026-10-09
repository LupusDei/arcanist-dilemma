class_name SpellGroundArea
extends Node3D
## Lingering ground left by a spell (burning ground): applies the spell's
## ground_effects to enemies inside every tick until it expires.

var spell: SpellData
var context: SpellContext
var _remaining := 0.0
var _until_tick := 0.0


func start(p_spell: SpellData, p_context: SpellContext, at: Vector3) -> void:
	spell = p_spell
	context = p_context
	global_position = _snap_to_ground(at)
	_remaining = spell.ground_duration
	_until_tick = 0.0
	_build_visual()


func _physics_process(delta: float) -> void:
	if spell == null:
		return
	_until_tick -= delta
	if _until_tick <= 0.0:
		_until_tick += spell.ground_tick_interval
		for target in HealthComponent.find_in_radius(get_tree(), global_position + Vector3.UP, spell.ground_radius, context.team):
			SpellDelivery.apply_to(spell.ground_effects, target, context, global_position)
	_remaining -= delta
	if _remaining <= 0.0:
		queue_free()


## Spells land at body height; the burning ground belongs on the floor below.
func _snap_to_ground(at: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(at, at + Vector3.DOWN * 4.0)
	query.exclude = [context.caster.get_rid()] if context.caster is CollisionObject3D else []
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit["position"] + Vector3.UP * 0.03 if not hit.is_empty() else at


func _build_visual() -> void:
	var disc := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = spell.ground_radius
	mesh.bottom_radius = spell.ground_radius
	mesh.height = 0.05
	disc.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(spell.get_color(), 0.35)
	disc.material_override = material
	add_child(disc)
