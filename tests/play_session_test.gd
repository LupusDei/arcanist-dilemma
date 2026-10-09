extends SceneTree
## Plays a short session in the real world scene with every system wired in:
## monsters spawn, the player's spells hurt them, kills give XP, the level 5
## path choice gives the path's spells, and the player respawns after dying.
## Run: godot --headless --path . --fixed-fps 60 --script res://tests/play_session_test.gd

var _failures: PackedStringArray = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var world: Node = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(world)
	await _frames(30)
	var player: Player = world.get_node("Player")
	var caster: SpellCaster = player.get_node("SpellCaster")
	var health: HealthComponent = player.get_node("HealthComponent")
	var progression: CharacterProgression = root.get_node("Progression").progression

	var enemies := root.get_tree().get_nodes_in_group(&"enemies")
	if enemies.is_empty():
		for node in world.get_node("Monsters").find_children("*", "Enemy", true, false):
			enemies.append(node)
	print("     %d monsters, player has %.0f health, bar: %s" % [enemies.size(), health.max_health, caster.get_action_bar().map(func(s: SpellData) -> String: return s.display_name if s else "-")])
	_check(enemies.size() >= 5, "monsters are spawned in the world")
	_check(caster.get_cantrip() != null, "player starts with a cantrip")
	_check(health.max_health >= 100.0, "player health comes from progression")

	# Walk up to the nearest monster and spark it until it dies.
	var target: Enemy = null
	var best := INF
	for enemy in enemies:
		var d: float = enemy.global_position.distance_to(player.global_position)
		if d < best:
			best = d
			target = enemy
	var enemy_health: HealthComponent = target.get_node("HealthComponent")
	var start_xp := progression.xp
	var start_level := progression.level
	player.global_position = target.global_position + Vector3(0, 0.5, 6)
	await _frames(10)
	var casts := 0
	var full := enemy_health.health
	while is_instance_valid(target) and not enemy_health.is_dead and casts < 60:
		health.revive()
		caster.cast_cantrip(target.global_position + Vector3.UP)
		casts += 1
		await _frames(20)
	_check(casts > 0 and (not is_instance_valid(enemy_health) or enemy_health.health < full or enemy_health.is_dead), "spells hurt monsters")
	_check(not is_instance_valid(target) or enemy_health.is_dead, "a monster can be killed (%d casts)" % casts)
	await _frames(10)
	_check(progression.xp > start_xp or progression.level > start_level, "killing it gives XP")

	# Level to 5 and take the first dilemma.
	while progression.level < 5:
		root.get_node("Progression").grant_xp(500, "test")
	await _frames(2)
	var session := world.get_node("GameSession")
	var picker: CanvasLayer = session._path_choice
	_check(picker.visible and paused, "the path choice opens at level 5")
	picker.close()
	session._on_path_picked("wizard")
	await _frames(2)
	_check(caster.source is WizardSpellbook, "choosing wizard gives a spellbook")
	_check(caster.get_action_bar().any(func(s: SpellData) -> bool: return s != null), "the wizard has spells on the bar (%s)" % [caster.get_action_bar().map(func(s: SpellData) -> String: return s.display_name if s else "-")])
	_check(caster.caster_resource != null and caster.caster_resource.get_display_name() == "Arcana", "the wizard uses Arcana")

	# Die and come back.
	player.respawn_delay = 0.2
	health.take_damage(Hit.new(99999.0, DamageType.Kind.PHYSICAL, null))
	await _frames(2)
	_check(player.is_dead, "the player can die")
	await _frames(30)
	_check(not player.is_dead and not health.is_dead and health.health == health.max_health, "the player respawns at full health")

	if _failures.is_empty():
		print("PLAY SESSION TEST PASSED")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: ", f)
		quit(1)


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _check(condition: bool, label: String) -> void:
	print(("ok   " if condition else "FAIL ") + label)
	if not condition:
		_failures.append(label)
