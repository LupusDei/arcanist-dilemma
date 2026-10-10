class_name ScorchMark
extends MeshInstance3D
## A burnt mark with cooling, glowing cracks where a bolt struck a surface.

var visual: SpellVisual
var _material: ShaderMaterial
var _age := 0.0


static func spawn(parent: Node, at: Vector3, normal: Vector3, p_visual: SpellVisual, radius: float) -> ScorchMark:
	if parent == null or not parent.is_inside_tree():
		return null
	var mark := ScorchMark.new()
	mark.visual = p_visual
	mark.mesh = VfxLib.quad()
	mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mark._material = VfxLib.shader_material(VfxLib.SCORCH, {
		"ember_color": p_visual.glow_color,
		"seed": randf() * 40.0,
	})
	mark.material_override = mark._material
	parent.add_child(mark)
	mark.global_position = at
	mark.look_at(at + normal, Vector3.UP if absf(normal.y) < 0.95 else Vector3.FORWARD)
	mark.rotate_object_local(Vector3.FORWARD, randf() * TAU)
	mark.scale = Vector3.ONE * radius * 2.0
	return mark


func _process(delta: float) -> void:
	_age += delta
	var life := visual.scorch_seconds
	_material.set_shader_parameter("heat", maxf(1.0 - _age / 1.2, 0.0))
	_material.set_shader_parameter("alpha", 1.0 - smoothstep(life * 0.6, life, _age))
	if _age >= life:
		queue_free()
