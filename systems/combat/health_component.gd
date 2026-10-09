class_name HealthComponent
extends Node
## Health, armor, resistances, wards and status effects for anything that can be hurt.
##
## Add as a child named "HealthComponent" of a Node3D body (player, enemy, dummy).
## Spells find targets through the "combat_targets" group this node joins, so no
## collision layers are needed. The body reacts through signals: move it on
## `knocked_back`, stop it while `is_stunned()`, scale speed by
## `get_move_speed_multiplier()`, and decide what `died` means.

signal health_changed(current: float, maximum: float)
## amount is what actually came off health after armor, resistances and wards.
signal damaged(hit: Hit, amount: float)
signal healed(amount: float)
signal died(killer: Node)
signal ward_changed(amount: float)
signal status_applied(kind: Status.Kind, duration: float)
signal status_ended(kind: Status.Kind)
signal knocked_back(impulse: Vector3)
## A stun, knockback or heavy hit. A SpellCaster on the same body cancels its cast.
signal interrupted

const GROUP := &"combat_targets"
const MAX_RESISTANCE := 0.75

enum Tier { NORMAL, ELITE, BOSS }

@export var max_health := 100.0:
	set(value):
		max_health = maxf(value, 1.0)
		if is_node_ready():
			health = minf(health, max_health)
			health_changed.emit(health, max_health)
@export var regen_per_second := 0.0
## Reduces physical and force damage: armor / (armor + 100).
@export var armor := 0.0
## Who this belongs to. Spells only hit the other team.
@export var team := &"enemy"
## Elites take half crowd-control duration, bosses only a brief stagger.
@export var tier := Tier.NORMAL
## DamageType.Kind -> fraction resisted (0.25 = 25% less). Negative means weak to it.
@export var resistances: Dictionary = {}
## Height of the body's center above its origin, used for aiming and hit tests.
@export var center_height := 1.0
## Radius used for spell hit tests.
@export var hit_radius := 0.5

var health := 100.0
var ward := 0.0
var is_dead := false
## Status.Kind -> {"remaining": float, "magnitude": float, "source": Node}
var statuses: Dictionary = {}

var _ward_remaining := 0.0
var _burn_source: Node


func _ready() -> void:
	health = max_health
	add_to_group(GROUP)


func _process(delta: float) -> void:
	if is_dead:
		return
	_tick_statuses(delta)
	if _ward_remaining > 0.0:
		_ward_remaining -= delta
		if _ward_remaining <= 0.0 and ward > 0.0:
			ward = 0.0
			ward_changed.emit(ward)
	var regen := regen_per_second + get_status_magnitude(Status.Kind.REGEN)
	if regen > 0.0 and health < max_health:
		heal(regen * delta)


## Applies armor, resistances and wards, then removes health. Returns damage taken.
func take_damage(hit: Hit) -> float:
	if is_dead or hit.amount <= 0.0 or _is_body_invulnerable():
		return 0.0
	var amount := hit.amount * (1.0 - get_mitigation(hit.damage_type))
	if ward > 0.0:
		var absorbed := minf(ward, amount)
		ward -= absorbed
		amount -= absorbed
		ward_changed.emit(ward)
	health = maxf(health - amount, 0.0)
	damaged.emit(hit, amount)
	health_changed.emit(health, max_health)
	if health <= 0.0:
		is_dead = true
		statuses.clear()
		died.emit(hit.source)
	elif amount >= max_health * hit.interrupt_threshold:
		interrupted.emit()
	return amount


## Fraction of incoming damage of this type that is removed (negative = extra damage).
func get_mitigation(damage_type: DamageType.Kind) -> float:
	var mitigation := 0.0
	if damage_type in DamageType.ARMORED:
		mitigation = armor / (armor + 100.0) if armor > 0.0 else 0.0
	else:
		mitigation = float(resistances.get(damage_type, 0.0))
	return clampf(mitigation, -1.0, MAX_RESISTANCE)


func heal(amount: float) -> float:
	if is_dead or amount <= 0.0:
		return 0.0
	var before := health
	health = minf(health + amount, max_health)
	var gained := health - before
	if gained > 0.0:
		healed.emit(gained)
		health_changed.emit(health, max_health)
	return gained


## Adds a damage-absorbing shield. A new ward replaces a weaker one.
func add_ward(amount: float, duration: float) -> void:
	if is_dead:
		return
	ward = maxf(ward, amount)
	_ward_remaining = maxf(_ward_remaining, duration)
	ward_changed.emit(ward)


## Applies or refreshes a status. Crowd control is scaled by tier.
func apply_status(kind: Status.Kind, duration: float, magnitude := 0.0, source: Node = null) -> void:
	if is_dead or duration <= 0.0:
		return
	if kind in Status.CROWD_CONTROL:
		if _is_body_invulnerable():
			return
		match tier:
			Tier.ELITE:
				duration *= 0.5
			Tier.BOSS:
				duration = minf(duration, 0.2)
	var current: Dictionary = statuses.get(kind, {})
	statuses[kind] = {
		"remaining": maxf(duration, current.get("remaining", 0.0)),
		"magnitude": maxf(magnitude, current.get("magnitude", 0.0)),
		"source": source,
	}
	if kind == Status.Kind.BURN:
		_burn_source = source
	status_applied.emit(kind, duration)
	if kind == Status.Kind.STUN:
		interrupted.emit()


func knock_back(impulse: Vector3) -> void:
	if is_dead or impulse.is_zero_approx() or _is_body_invulnerable():
		return
	if tier == Tier.BOSS:
		impulse *= 0.2
	elif tier == Tier.ELITE:
		impulse *= 0.5
	knocked_back.emit(impulse)
	interrupted.emit()


func has_status(kind: Status.Kind) -> bool:
	return statuses.has(kind)


func get_status_magnitude(kind: Status.Kind) -> float:
	return statuses[kind]["magnitude"] if statuses.has(kind) else 0.0


func is_stunned() -> bool:
	return has_status(Status.Kind.STUN)


## Can't move: stunned, rooted or dead.
func is_immobile() -> bool:
	return is_dead or has_status(Status.Kind.STUN) or has_status(Status.Kind.ROOT)


## Multiply movement speed by this. 0 while stunned or rooted.
func get_move_speed_multiplier() -> float:
	if is_immobile():
		return 0.0
	return maxf(1.0 - get_status_magnitude(Status.Kind.SLOW) + get_status_magnitude(Status.Kind.HASTE), 0.1)


## Brings a dead body back (rest spot, respawn) at full health with no statuses.
func revive() -> void:
	is_dead = false
	health = max_health
	statuses.clear()
	ward = 0.0
	health_changed.emit(health, max_health)


## Same as revive(); the name enemies call when they return home or respawn.
func reset() -> void:
	revive()


## The point spells aim at and measure distance from.
func get_target_position() -> Vector3:
	var body := get_parent() as Node3D
	if body == null:
		return Vector3.ZERO
	return body.global_position + Vector3.UP * center_height


func get_body() -> Node3D:
	return get_parent() as Node3D


## Finds the HealthComponent on a body: a direct child, or the node itself.
static func find_on(node: Node) -> HealthComponent:
	if node == null:
		return null
	if node is HealthComponent:
		return node
	var direct := node.get_node_or_null(^"HealthComponent") as HealthComponent
	if direct:
		return direct
	for child in node.get_children():
		if child is HealthComponent:
			return child
	return null


## Living targets not on `exclude_team` whose hit sphere touches the given sphere,
## nearest first.
static func find_in_radius(tree: SceneTree, center: Vector3, radius: float, exclude_team: StringName) -> Array[HealthComponent]:
	var found: Array[HealthComponent] = []
	for node in tree.get_nodes_in_group(GROUP):
		var target := node as HealthComponent
		if target == null or target.is_dead or target.team == exclude_team or not target.is_inside_tree():
			continue
		if target.get_target_position().distance_to(center) <= radius + target.hit_radius:
			found.append(target)
	found.sort_custom(func(a: HealthComponent, b: HealthComponent) -> bool:
		return a.get_target_position().distance_squared_to(center) < b.get_target_position().distance_squared_to(center))
	return found


func _tick_statuses(delta: float) -> void:
	if statuses.has(Status.Kind.BURN):
		var burn := Hit.new(get_status_magnitude(Status.Kind.BURN) * delta, DamageType.Kind.FIRE, _burn_source)
		burn.interrupt_threshold = INF
		take_damage(burn)
		if is_dead:
			return
	for kind in statuses.keys():
		statuses[kind]["remaining"] -= delta
		if statuses[kind]["remaining"] <= 0.0:
			statuses.erase(kind)
			status_ended.emit(kind)


func _is_body_invulnerable() -> bool:
	var body := get_parent()
	return body != null and body.get(&"is_invulnerable") == true
