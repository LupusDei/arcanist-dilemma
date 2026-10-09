class_name SpellCaster
extends Node3D
## Casts spells for a body: checks cooldowns and the path resource, runs cast
## times, resolves the spell through SpellDelivery and reports everything by signal.
##
## Add as a child of the player (or a casting enemy) at hand or chest height.
## Give it a SpellSource with `set_source` (TrickSet before level 5, then
## WizardSpellbook, MageCodex or SorcererSpellTree) and cast with
## `cast_slot(index, aim_point)` or `cast_cantrip(aim_point)`.

signal cast_started(spell: SpellData, cast_time: float)
## The spell resolved (it may still miss).
signal spell_cast(spell: SpellData)
signal cast_interrupted(spell: SpellData)
## reason: &"busy", &"cooldown", &"no_resource", &"stunned", &"no_target",
## &"not_prepared", &"not_learned", &"unknown_words", &"dead", &"empty_slot"
signal cast_failed(spell: SpellData, reason: StringName)
## A mage's first raw experiment fizzled harmlessly.
signal misfired(spell: SpellData)
signal cooldown_started(spell: SpellData, duration: float)
signal resource_changed(current: float, maximum: float)
## The source or bar contents changed (UI should redraw the bar).
signal bar_changed

const COMBAT_LINGER := 5.0

@export var team := &"player"
@export var stats: CombatStats
## Optional. Defaults to a HealthComponent on the parent body.
@export var health: HealthComponent
## Optional. Where projectiles and effects are spawned. Defaults to the current scene.
@export var effects_parent: Node

var source: SpellSource
var caster_resource: CasterResource
var rng := RandomNumberGenerator.new()

var _casting: SpellData
var _cast_elapsed := 0.0
var _cast_duration := 0.0
var _cast_aim := Vector3.ZERO
## Spell id -> seconds left.
var _cooldowns: Dictionary = {}
var _combat_timer := 0.0


func _ready() -> void:
	if stats == null:
		stats = CombatStats.new()
	if health == null:
		health = HealthComponent.find_on(get_parent())
	if health:
		health.interrupted.connect(_on_interrupted)
		health.damaged.connect(func(_hit: Hit, _amount: float) -> void: _combat_timer = COMBAT_LINGER)
	if source == null:
		set_source(TrickSet.new())


func _process(delta: float) -> void:
	if _combat_timer > 0.0:
		_combat_timer -= delta
	if caster_resource:
		caster_resource.tick(delta, is_in_combat())
	for id in _cooldowns.keys():
		_cooldowns[id] -= delta
		if _cooldowns[id] <= 0.0:
			_cooldowns.erase(id)
	if _casting:
		if health and (health.is_dead or health.is_stunned()):
			interrupt()
			return
		_cast_elapsed += delta
		if _cast_elapsed >= _cast_duration:
			var spell := _casting
			_casting = null
			_resolve(spell, _cast_aim)


## Switches path (or rebuilds after a stat change). Creates a fresh resource.
func set_source(new_source: SpellSource) -> void:
	if source and source.changed.is_connected(_on_source_changed):
		source.changed.disconnect(_on_source_changed)
	source = new_source
	source.changed.connect(_on_source_changed)
	_rebuild_resource()
	bar_changed.emit()


## Call after progression changes stats (level-up, attribute points, gear).
func set_stats(new_stats: CombatStats) -> void:
	stats = new_stats
	_rebuild_resource(true)


## The bar as the HUD lays it out: left click (cantrip), right click (the main
## spell in slot 6), then keys 1 to 6.
var action_bar: Array:
	get:
		var bar := get_action_bar()
		var layout: Array = [get_cantrip(), bar[6] if bar.size() > 6 else null]
		for i in 6:
			layout.append(bar[i] if i < bar.size() else null)
		return layout


func get_action_bar() -> Array[SpellData]:
	return source.get_bar() if source else []


func get_cantrip() -> SpellData:
	return source.cantrip if source else null


func cast_slot(index: int, aim_point: Vector3) -> bool:
	var bar := get_action_bar()
	if index < 0 or index >= bar.size() or bar[index] == null:
		cast_failed.emit(null, &"empty_slot")
		return false
	return cast(bar[index], aim_point)


func cast_cantrip(aim_point: Vector3) -> bool:
	var cantrip := get_cantrip()
	if cantrip == null:
		cast_failed.emit(null, &"empty_slot")
		return false
	return cast(cantrip, aim_point)


## Starts casting any spell the source allows. Returns false (and emits
## cast_failed) if it can't start. Instant spells resolve immediately.
func cast(spell: SpellData, aim_point: Vector3) -> bool:
	var reason := check_cast(spell, aim_point)
	if reason != &"":
		cast_failed.emit(spell, reason)
		return false
	_combat_timer = COMBAT_LINGER
	var duration := get_cast_time(spell)
	if duration <= 0.0:
		_resolve(spell, aim_point)
		return true
	_casting = spell
	_cast_elapsed = 0.0
	_cast_duration = duration
	_cast_aim = aim_point
	cast_started.emit(spell, duration)
	return true


## Empty if the spell could be cast now, otherwise the reason it can't.
func check_cast(spell: SpellData, aim_point := Vector3.ZERO) -> StringName:
	if spell == null:
		return &"empty_slot"
	if health and health.is_dead:
		return &"dead"
	if health and health.is_stunned():
		return &"stunned"
	if _casting:
		return &"busy"
	if _cooldowns.has(spell.id):
		return &"cooldown"
	var source_reason := source.check_cast(spell) if source else &""
	if source_reason != &"":
		return source_reason
	if caster_resource and not caster_resource.can_pay(get_cost(spell)):
		return &"no_resource"
	if spell.delivery == SpellData.Delivery.TARGETED and is_inside_tree() \
			and SpellDelivery.find_target(_make_context(spell), global_position, aim_point, spell.cast_range) == null:
		return &"no_target"
	return &""


## Cancels the current cast. Nothing is spent.
func interrupt() -> void:
	if _casting == null:
		return
	var spell := _casting
	_casting = null
	cast_interrupted.emit(spell)


func is_casting() -> bool:
	return _casting != null


func get_casting_spell() -> SpellData:
	return _casting


## 0 to 1 while casting, 0 otherwise.
func get_cast_progress() -> float:
	return clampf(_cast_elapsed / _cast_duration, 0.0, 1.0) if _casting and _cast_duration > 0.0 else 0.0


func get_cooldown_remaining(spell: SpellData) -> float:
	return _cooldowns.get(spell.id, 0.0) if spell else 0.0


func get_cost(spell: SpellData) -> float:
	return spell.cost * (source.get_cost_multiplier(spell) if source else 1.0)


func get_cast_time(spell: SpellData) -> float:
	return spell.cast_time / (1.0 + stats.cast_speed)


## The power a cast of this spell would have right now, for tooltips.
func get_power(spell: SpellData) -> float:
	var power := stats.spell_power * (source.get_power_multiplier(spell) if source else 1.0)
	return power * (caster_resource.get_power_multiplier() if caster_resource else 1.0)


func is_in_combat() -> bool:
	return _combat_timer > 0.0


## Refills the resource and lets path systems make rest-only changes until `end_rest`.
func begin_rest() -> void:
	interrupt()
	if caster_resource:
		caster_resource.refill()
	if health:
		health.heal(health.max_health)
	if source:
		source.is_resting = true
	_cooldowns.clear()


func end_rest() -> void:
	if source:
		source.is_resting = false
	bar_changed.emit()


func _resolve(spell: SpellData, aim_point: Vector3) -> void:
	# Re-check what may have changed during a cast time.
	var cost := get_cost(spell)
	if caster_resource and not caster_resource.pay(cost):
		cast_failed.emit(spell, &"no_resource")
		return
	if spell.cooldown > 0.0:
		_cooldowns[spell.id] = spell.cooldown
		cooldown_started.emit(spell, spell.cooldown)

	if caster_resource is StrainPool and health:
		var backlash := (caster_resource as StrainPool).get_backlash(cost)
		if backlash > 0.0:
			var hurt := Hit.new(backlash, DamageType.Kind.ARCANE, get_parent())
			hurt.interrupt_threshold = INF
			health.take_damage(hurt)

	if source and source.rolls_misfire(spell, rng, stats):
		source.on_cast(spell)
		misfired.emit(spell)
		return

	var context := _make_context(spell)
	SpellDelivery.deliver(spell, context, global_position, aim_point, _get_effects_parent())
	if health and not spell.caster_effects.is_empty():
		SpellDelivery.apply_to(spell.caster_effects, health, context, global_position)
	if source:
		source.on_cast(spell)
	spell_cast.emit(spell)


func _make_context(spell: SpellData) -> SpellContext:
	var context := SpellContext.new()
	context.spell = spell
	context.caster = get_parent() as Node3D if get_parent() is Node3D else self
	context.caster_health = health
	context.team = health.team if health else team
	context.power = get_power(spell)
	context.force_power = stats.force_power
	context.crit_multiplier = stats.crit_multiplier
	context.is_crit = spell.is_hostile() and rng.randf() < stats.crit_chance
	context.origin = global_position if is_inside_tree() else Vector3.ZERO
	return context


func _get_effects_parent() -> Node:
	if effects_parent:
		return effects_parent
	var scene := get_tree().current_scene
	if scene:
		return scene
	# Headless test runs have no current scene; use the body's parent.
	var body := get_parent()
	return body.get_parent() if body and body.get_parent() else self


func _rebuild_resource(keep_fill := false) -> void:
	if source == null:
		return
	var fill := caster_resource.get_fill() if caster_resource and keep_fill else -1.0
	if caster_resource:
		caster_resource.changed.disconnect(_on_resource_changed)
		if caster_resource is StrainPool:
			(caster_resource as StrainPool).collapsed.disconnect(_on_collapsed)
	caster_resource = source.create_resource(stats)
	caster_resource.changed.connect(_on_resource_changed)
	if caster_resource is StrainPool:
		(caster_resource as StrainPool).collapsed.connect(_on_collapsed)
	if fill >= 0.0 and not caster_resource is StrainPool:
		caster_resource.current = caster_resource.maximum * fill
	resource_changed.emit(caster_resource.current, caster_resource.maximum)


func _on_resource_changed(current: float, maximum: float) -> void:
	resource_changed.emit(current, maximum)


func _on_source_changed() -> void:
	bar_changed.emit()


func _on_collapsed() -> void:
	if health:
		health.apply_status(Status.Kind.STUN, (caster_resource as StrainPool).collapse_stun, 0.0, get_parent())


## Heavy hits interrupt casts; Wisdom gives wizards a chance to hold on.
func _on_interrupted() -> void:
	if _casting == null:
		return
	if health and health.is_stunned():
		interrupt()
	elif rng.randf() >= stats.interrupt_resistance:
		interrupt()
