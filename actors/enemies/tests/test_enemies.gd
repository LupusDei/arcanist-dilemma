extends SceneTree
## Headless tests for the enemy package.
## Run: godot --headless --path . --script res://actors/enemies/tests/test_enemies.gd

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const BRUTE := preload("res://actors/enemies/types/bramble_brute.tscn")
const HEXLING := preload("res://actors/enemies/types/hexling.tscn")
const HOUND := preload("res://actors/enemies/types/gloom_hound.tscn")
const ARENA := preload("res://actors/enemies/arena/enemy_arena.tscn")

var _failures: PackedStringArray = []


class Listener:
	extends Node
	var kills: Array = []
	var pickups: Array = []

	func on_enemy_died(enemy: Enemy, xp_value: int, loot: Array[Dictionary]) -> void:
		kills.append({"enemy": enemy, "xp": xp_value, "loot": loot})

	func on_loot_collected(loot: Array[Dictionary], collector: Node3D) -> void:
		pickups.append({"loot": loot, "collector": collector})


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_health()
	_test_loot_table()
	await _test_damage_rules()
	await _test_idle_out_of_range()
	await _test_melee_chase_and_attack()
	await _test_dodge_avoids_hit()
	await _test_ranged_caster()
	await _test_flee()
	await _test_pack_alert()
	await _test_death_loot_and_spawner()
	await _test_leash()
	await _test_arena()

	if _failures.is_empty():
		print("ENEMY TESTS PASSED")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: ", f)
		quit(1)


# --- Units --------------------------------------------------------------------

func _test_health() -> void:
	print("-- health")
	var health := EnemyHealth.new()
	health.max_health = 50.0
	health.armor = 2.0
	root.add_child(health)
	var deaths := [0]
	health.died.connect(func(_killer: Node) -> void: deaths[0] += 1)
	_check(is_equal_approx(health.take_damage(10.0), 8.0), "armor reduces damage")
	_check(is_equal_approx(health.current_health, 42.0), "health goes down")
	health.take_damage(EnemyDamage.make_hit(500.0, null))
	_check(health.current_health == 0.0 and health.is_dead(), "health stops at zero")
	health.take_damage(5.0)
	_check(deaths[0] == 1, "died fires exactly once")
	health.reset()
	_check(health.current_health == 50.0 and not health.is_dead(), "reset restores full health")
	health.free()


func _test_loot_table() -> void:
	print("-- loot")
	var table: EnemyLootTable = (load("res://actors/enemies/types/bramble_brute.tres") as EnemyData).loot_table
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var first := table.roll(rng)
	rng.seed = 42
	_check(first == table.roll(rng), "same seed gives the same loot")
	var gold_ok := true
	var thorns := 0
	rng.seed = 7
	for i in 400:
		for drop in table.roll(rng):
			if drop["id"] == &"gold" and (drop["count"] < 5 or drop["count"] > 15):
				gold_ok = false
			if drop["id"] == &"bramble_thorn":
				thorns += 1
	_check(gold_ok, "gold stays in its range")
	_check(thorns > 180 and thorns < 300, "60%% thorn drop rate is roughly right (%d / 400)" % thorns)


func _test_damage_rules() -> void:
	print("-- damage rules")
	var w := await _world(Vector3(0, 0, 30))
	var player: Player = w.player
	var brute := _spawn(w, BRUTE, Vector3(0, 0, -30))
	await _frames(2)
	_check(EnemyDamage.apply(player, 5.0, brute), "an enemy can damage the player")
	_check(not EnemyDamage.apply(brute, 5.0, brute), "an enemy can't damage its own team")
	player.is_invulnerable = true
	_check(not EnemyDamage.apply(player, 5.0, brute), "a dodging player takes no damage")
	_check(_hp(player) == 145.0, "only the first hit landed (hp %.0f)" % _hp(player))
	await _free(w)


# --- AI -----------------------------------------------------------------------

func _test_idle_out_of_range() -> void:
	print("-- idle")
	var w := await _world(Vector3(0, 0, 25))
	var brute := _spawn(w, BRUTE, Vector3.ZERO)
	await _frames(90)
	_check(brute.state == Enemy.State.IDLE, "enemy ignores a player outside aggro range")
	_check(brute.global_position.distance_to(brute.home_position) < 3.0, "idle wander stays near home")
	await _free(w)


func _test_melee_chase_and_attack() -> void:
	print("-- melee")
	var w := await _world(Vector3(0, 0, 7))
	var brute := _spawn(w, BRUTE, Vector3.ZERO)
	var seen := _record_states(brute)
	var hits := [0]
	brute.attacked.connect(func(_t: Node3D, _d: float) -> void: hits[0] += 1)
	await _frames(240)
	_check(seen.has(Enemy.State.AGGRO), "player in range triggers aggro")
	_check(seen.has(Enemy.State.CHASE), "aggro leads to chase")
	_check(seen.has(Enemy.State.ATTACK), "chase leads to attack")
	_check(hits[0] >= 1, "melee attack connects")
	_check(_hp(w.player) <= 150.0 - 18.0, "player lost health to the brute (hp %.0f)" % _hp(w.player))
	await _free(w)


func _test_dodge_avoids_hit() -> void:
	print("-- dodge")
	var w := await _world(Vector3(0, 0, 1.8))
	var brute := _spawn(w, BRUTE, Vector3.ZERO)
	await _until(func() -> bool: return brute.state == Enemy.State.ATTACK, 120)
	w.player.is_invulnerable = true
	await _until(func() -> bool: return brute.state != Enemy.State.ATTACK, 120)
	_check(_hp(w.player) == 150.0, "attack during a dodge does nothing (hp %.0f)" % _hp(w.player))
	await _free(w)


func _test_ranged_caster() -> void:
	print("-- ranged")
	var w := await _world(Vector3(0, 0, 10))
	var hexling := _spawn(w, HEXLING, Vector3.ZERO)
	var seen := _record_states(hexling)
	await _until(func() -> bool: return _hp(w.player) < 150.0, 300)
	_check(seen.has(Enemy.State.ATTACK), "caster attacks from range")
	_check(hexling.global_position.distance_to(Vector3.ZERO) < 1.5, "caster doesn't need to close in")
	_check(_hp(w.player) == 150.0 - 9.0, "bolt hits the player (hp %.0f)" % _hp(w.player))
	await _free(w)

	w = await _world(Vector3(0, 0, 2.5))
	hexling = _spawn(w, HEXLING, Vector3.ZERO)
	await _frames(90)
	var gap := hexling.distance_to_target()
	_check(gap > 4.0, "caster backs away from a close player (%.1fm)" % gap)
	await _free(w)


func _test_flee() -> void:
	print("-- flee")
	var w := await _world(Vector3(0, 0, 6))
	var hound := _spawn(w, HOUND, Vector3.ZERO)
	await _until(func() -> bool: return hound.state == Enemy.State.CHASE, 120)
	hound.health.take_damage(EnemyDamage.make_hit(26.0, w.player))
	await _frames(1)
	_check(hound.state == Enemy.State.FLEE, "hound flees below 30% health")
	var start_gap := hound.distance_to_target()
	await _frames(60)
	_check(hound.distance_to_target() > start_gap + 2.0, "fleeing hound runs away (%.1f -> %.1f)" % [start_gap, hound.distance_to_target()])
	await _until(func() -> bool: return hound.state != Enemy.State.FLEE, 240)
	_check(hound.state in [Enemy.State.CHASE, Enemy.State.ATTACK], "hound comes back after fleeing")
	await _free(w)


func _test_pack_alert() -> void:
	print("-- pack")
	var w := await _world(Vector3(0, 0, 20))
	var spawner := EnemySpawner.new()
	spawner.enemy_scene = HOUND
	spawner.count = 4
	spawner.spawn_radius = 2.5
	spawner.spawn_on_ready = false
	w.root.add_child(spawner)
	spawner.spawn_all()
	await _frames(5)
	_check(spawner.alive.size() == 4, "spawner spawns its pack")
	var pack := spawner.alive.duplicate()
	var idle := pack.all(func(e: Enemy) -> bool: return e.state == Enemy.State.IDLE)
	_check(idle, "pack starts idle with the player out of range")
	pack[0].health.take_damage(EnemyDamage.make_hit(5.0, w.player))
	await _frames(2)
	var awake := pack.all(func(e: Enemy) -> bool: return e.state != Enemy.State.IDLE)
	_check(awake, "hitting one hound wakes the whole pack")
	await _free(w)


func _test_death_loot_and_spawner() -> void:
	print("-- death and loot")
	var w := await _world(Vector3(0, 0, 30))
	var listener := Listener.new()
	listener.add_to_group(Enemy.LISTENER_GROUP)
	listener.add_to_group(EnemyLootDrop.LISTENER_GROUP)
	w.root.add_child(listener)
	var spawner := EnemySpawner.new()
	spawner.enemy_scene = BRUTE
	spawner.count = 1
	spawner.spawn_on_ready = false
	w.root.add_child(spawner)
	var brute := spawner.spawn_one()
	brute.data = brute.data.duplicate()
	brute.data.loot_table = brute.data.loot_table.duplicate()
	brute.data.loot_table.gold_min = 10 # guarantee a drop
	var relayed := []
	var cleared := [false]
	spawner.enemy_died.connect(func(e: Enemy, xp_value: int, loot: Array[Dictionary]) -> void: relayed.append([e, xp_value, loot]))
	spawner.cleared.connect(func() -> void: cleared[0] = true)
	var signalled := []
	brute.died.connect(func(e: Enemy, xp_value: int, loot: Array[Dictionary]) -> void: signalled.append([e, xp_value, loot]))
	await _frames(10)

	brute.health.take_damage(EnemyDamage.make_hit(1000.0, w.player))
	_check(brute.state == Enemy.State.DEAD, "lethal damage kills the enemy")
	_check(signalled.size() == 1 and signalled[0][1] == 25, "died signal carries the xp value")
	_check(not signalled.is_empty() and (signalled[0][2] as Array).any(func(d: Dictionary) -> bool: return d["id"] == &"gold"), "died signal carries rolled loot")
	_check(relayed.size() == 1 and cleared[0], "spawner relays the death and reports cleared")
	_check(listener.kills.size() == 1 and listener.kills[0]["xp"] == 25, "enemy_listeners group hears about the kill")
	_check(not brute.is_in_group(Enemy.ENEMY_GROUP), "dead enemy leaves the enemies group")

	var drops: Array = []
	for node: Node in (w.root as Node).find_children("*", "Area3D", true, false):
		if node is EnemyLootDrop:
			drops.append(node)
	_check(drops.size() == 1, "loot drop spawns where the enemy died")
	await _frames(150)
	_check(not is_instance_valid(brute), "corpse is freed after the death animation")
	if drops.size() == 1:
		var drop := drops[0] as EnemyLootDrop
		w.player.global_position = drop.global_position
		await _frames(10)
		_check(not is_instance_valid(drop), "walking over the drop collects it")
		_check(listener.pickups.size() == 1 and listener.pickups[0]["collector"] == w.player, "loot_listeners group hears about the pickup")
	await _free(w)


func _test_leash() -> void:
	print("-- leash")
	var w := await _world(Vector3(0, 0, 6))
	var brute := _spawn(w, BRUTE, Vector3.ZERO)
	await _until(func() -> bool: return brute.state == Enemy.State.CHASE, 120)
	brute.health.take_damage(EnemyDamage.make_hit(40.0, w.player))
	w.player.global_position = Vector3(0, 0.1, 40)
	await _until(func() -> bool: return brute.state == Enemy.State.RETURN, 300)
	_check(brute.state == Enemy.State.RETURN, "enemy gives up past its leash range")
	await _until(func() -> bool: return brute.state == Enemy.State.IDLE, 600)
	_check(brute.state == Enemy.State.IDLE, "leashed enemy goes home and idles")
	_check(brute.health_current == brute.health_max, "leashed enemy heals to full at home")
	await _free(w)


func _test_arena() -> void:
	print("-- arena")
	var arena := ARENA.instantiate()
	root.add_child(arena)
	await _frames(30)
	var enemies := get_nodes_in_group(Enemy.ENEMY_GROUP)
	_check(enemies.size() == 8, "arena spawns 2 brutes, 2 hexlings and 4 hounds (%d)" % enemies.size())
	var map: RID = arena.get_world_3d().navigation_map
	var path := NavigationServer3D.map_get_path(map, Vector3(0, 0, 4), Vector3(0, 0, -15), true)
	var length := 0.0
	for i in range(1, path.size()):
		length += path[i - 1].distance_to(path[i])
	_check(path.size() > 2 and length > 21.0, "navmesh routes around the divider wall (%d points, %.1fm)" % [path.size(), length])

	var brute: Enemy = arena.get_node("BruteCamp").alive[0]
	var player: Player = arena.get_node("Player")
	player.global_position = Vector3(0, 0.1, 2)
	brute.alert(player)
	var start := brute.global_position
	await _frames(240)
	_check(brute.global_position.distance_to(start) > 3.0, "brute moves through the arena toward the player")
	_check(absf(brute.global_position.x) > 7.0 or brute.global_position.z > -4.0, "brute went around the wall, not into it (%s)" % brute.global_position)

	arena.nova()
	await _frames(2)
	await _free({"root": arena})


# --- Helpers ------------------------------------------------------------------

func _world(player_position: Vector3) -> Dictionary:
	var world := Node3D.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(120, 1, 120)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0, -0.5, 0)
	world.add_child(floor_body)

	var player: Player = PLAYER_SCENE.instantiate()
	player.position = player_position + Vector3.UP * 0.1
	world.add_child(player)
	var health := EnemyHealth.new()
	health.name = EnemyDamage.HEALTH_NODE
	health.max_health = 150.0
	health.team = &"player"
	player.add_child(health)
	await _frames(2)
	return {"root": world, "player": player}


func _spawn(w: Dictionary, scene: PackedScene, at: Vector3) -> Enemy:
	var enemy := scene.instantiate() as Enemy
	enemy.position = at
	enemy.show_debug_label = false
	w.root.add_child(enemy)
	return enemy


func _free(w: Dictionary) -> void:
	w.root.queue_free()
	await _frames(2)


func _hp(body: Node) -> float:
	return EnemyDamage.find_health(body).current_health


func _record_states(enemy: Enemy) -> Dictionary:
	var seen := {}
	enemy.state_changed.connect(func(_from: Enemy.State, to: Enemy.State) -> void: seen[to] = true)
	return seen


func _until(condition: Callable, max_frames: int) -> void:
	for i in max_frames:
		if condition.call():
			return
		await physics_frame


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _check(condition: bool, label: String) -> void:
	print(("ok   " if condition else "FAIL ") + label)
	if not condition:
		_failures.append(label)
