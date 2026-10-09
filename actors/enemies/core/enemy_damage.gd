class_name EnemyDamage
extends RefCounted
## How enemies deal damage, independent of which health script a target uses.
##
## A damageable body has a child node named "HealthComponent" with
## take_damage(hit). When the combat system's Hit and DamageType classes exist
## in the project, hits are built with them; until then a local stand-in is used.

const HEALTH_NODE := "HealthComponent"

static var _script_cache := {}


## Small stand-in for combat's Hit, used only while that class is absent.
class LocalHit:
	extends RefCounted
	var amount: float
	var source: Node

	func _init(p_amount: float, p_source: Node) -> void:
		amount = p_amount
		source = p_source


static func find_health(body: Node) -> Node:
	if body == null:
		return null
	return body.get_node_or_null(HEALTH_NODE)


## Deals physical damage to `target` unless it is dodging, already dead, or on
## the attacker's team. Returns true if a hit was delivered.
static func apply(target: Node, amount: float, source: Node) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if target.get("is_invulnerable") == true:
		return false
	var health := find_health(target)
	if health == null or not health.has_method("take_damage"):
		return false
	if (health.has_method("is_dead") and health.is_dead()) or health.get("is_dead") == true:
		return false
	var attacker_health := find_health(source)
	if attacker_health != null and attacker_health.get("team") == health.get("team"):
		return false
	health.take_damage(make_hit(amount, source))
	return true


static func make_hit(amount: float, source: Node) -> Object:
	var hit_script := _global_script(&"Hit")
	var damage_type := _global_script(&"DamageType")
	if hit_script != null and damage_type != null:
		return hit_script.new(amount, damage_type.Kind.PHYSICAL, source)
	return make_local_hit(amount, source)


static func make_local_hit(amount: float, source: Node) -> Object:
	return LocalHit.new(amount, source)


static func _global_script(class_name_to_find: StringName) -> Script:
	if not _script_cache.has(class_name_to_find):
		_script_cache[class_name_to_find] = null
		for entry in ProjectSettings.get_global_class_list():
			if entry["class"] == class_name_to_find:
				_script_cache[class_name_to_find] = load(entry["path"])
	return _script_cache[class_name_to_find]
