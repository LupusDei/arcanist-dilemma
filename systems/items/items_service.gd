class_name ItemsService
extends Node
## Autoload "Items": the player's bag and worn gear for the running game.
##
## Wire in project.godot as:  Items="*res://systems/items/items_service.gd"
##
## - Picks up the enemies' drops (it joins "loot_listeners") and adds its own
##   level- and biome-keyed item drops on every kill (it joins "enemy_listeners").
## - Applies worn gear to the player's SpellCaster, HealthComponent and spell
##   source whenever gear or progression changes.
## - Saves with the character through Progression.save_game, under extra "items".

signal inventory_changed
signal equipment_changed
signal gold_changed(gold: int)
signal gear_stats_changed(stats: Dictionary)
signal item_picked_up(item: ItemInstance)
signal item_used(item: ItemInstance)
signal item_dropped(item: ItemInstance)
## A short line for the HUD ("Your bag is full", "Only a wizard can study this").
signal message(text: String)

const SAVE_KEY := "items"
const PICKUP_SCRIPT := preload("res://systems/items/item_pickup.gd")

var inventory := Inventory.new()
var equipment := Equipment.new()

## Biome used for kill drops. World and dungeon scenes set it when the player enters.
var current_biome := &"meadow"
## Roll item drops from res://data/items/loot.json on every kill.
var drop_items_on_kill := true
## Seeds kill drops; the kill counter makes each kill different.
var loot_seed := 0
## Used for requirement checks when there is no Progression autoload.
var fallback_character := {"level": 1, "path": "", "attributes": {}}
## When set, used instead of Progression (sandbox, tests): {"level", "path", "attributes"}.
var character_override := {}
## Finds the node in the "player" group on its own and binds to it.
var auto_bind_player := true
## Adds the inventory screen (I to open) once a player is bound.
var auto_inventory_screen := true

var player: Node3D
var caster: Node
var health: Node

var screen: Control

var _kills := 0
var _gear_stats := {}
var _refresh_queued := false
var _bind_timer := 0.0


func _ready() -> void:
	add_to_group(&"loot_listeners")
	add_to_group(&"enemy_listeners")
	inventory.changed.connect(inventory_changed.emit)
	inventory.gold_changed.connect(gold_changed.emit)
	equipment.changed.connect(_on_equipment_changed)
	var progression := _progression()
	if progression:
		progression.connect("character_loaded", _on_character_loaded)
		# Deferred, so gear lands after anything else that rebuilds stats on the same signal.
		progression.connect("stats_changed", queue_refresh)
		if progression.has_signal("path_chosen"):
			progression.connect("path_chosen", func(_p: String) -> void: queue_refresh())
	refresh_stats()


## The "drink_potion" input action, when the project has one, drinks the best healing draught.
func _unhandled_input(event: InputEvent) -> void:
	if InputMap.has_action(&"drink_potion") and event.is_action_pressed(&"drink_potion") and player and not get_tree().paused:
		drink_health_potion()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not auto_bind_player or (player and is_instance_valid(player)):
		return
	_bind_timer -= delta
	if _bind_timer <= 0.0:
		_bind_timer = 0.5
		var p := get_tree().get_first_node_in_group(&"player") as Node3D
		if p:
			bind_player(p)


# --- Player binding ---------------------------------------------------------

## Points the gear at the player's combat nodes. Without arguments it finds the
## node in the "player" group and its HealthComponent and SpellCaster children.
func bind_player(p_player: Node3D = null, p_caster: Node = null, p_health: Node = null) -> void:
	if caster and is_instance_valid(caster) and caster.has_signal("bar_changed") and caster.bar_changed.is_connected(_on_caster_source_changed):
		caster.bar_changed.disconnect(_on_caster_source_changed)
	player = p_player if p_player else get_tree().get_first_node_in_group(&"player") as Node3D
	caster = p_caster
	health = p_health
	if player:
		if caster == null:
			caster = _find_child_with(player, "set_stats")
		if health == null:
			health = player.get_node_or_null("HealthComponent")
			if health == null:
				health = _find_child_with(player, "take_damage")
		if auto_inventory_screen and screen == null:
			_add_screen()
	# A new spell source (the path choice) needs the gear "+N to a spell" again.
	if caster and caster.has_signal("bar_changed"):
		caster.bar_changed.connect(_on_caster_source_changed)
	refresh_stats()


# --- Character --------------------------------------------------------------

## {"level", "path", "attributes"} from character_override, Progression, or fallback_character.
func character_snapshot() -> Dictionary:
	if not character_override.is_empty():
		return character_override
	var progression := _progression()
	if progression == null:
		return fallback_character
	var p: Object = progression.get("progression")
	var attrs := {}
	for a in ItemDefs.ATTRIBUTES:
		attrs[a] = p.get_attribute(a)
	return {"level": p.get("level"), "path": p.get("path"), "attributes": attrs}


## Character attributes plus gear, for the character sheet.
func total_attributes() -> Dictionary:
	return ItemStats.attributes_with_gear(character_snapshot().get("attributes", {}), _gear_stats)


func get_gear_stats() -> Dictionary:
	return _gear_stats


func get_gear_stat(stat: StringName) -> float:
	return float(_gear_stats.get(stat, 0.0))


# --- Equipping --------------------------------------------------------------

## Empty if the item can be worn in [param slot] now, otherwise a reason (see Equipment.check_equip).
func check_equip(item: ItemInstance, slot := &"") -> StringName:
	if slot == &"":
		slot = equipment.best_slot_for(item)
	return equipment.check_equip(item, slot, character_snapshot())


## Moves an item from the bag to a slot; what was worn goes back to the bag.
## Returns an empty StringName on success, otherwise the reason.
func equip(item: ItemInstance, slot := &"") -> StringName:
	if slot == &"":
		slot = equipment.best_slot_for(item)
	var reason := check_equip(item, slot)
	if reason != &"":
		message.emit(describe_reason(reason, item))
		return reason
	var from_pos := inventory.get_position_of(item)
	inventory.remove_item(item)
	var previous := equipment.equip(item, slot)
	if previous:
		if not (from_pos.x >= 0 and inventory.place_at(previous, from_pos)) and inventory.add_item(previous) != null:
			# No room for the old item: undo.
			equipment.equip(previous, slot)
			if from_pos.x >= 0:
				inventory.place_at(item, from_pos)
			else:
				inventory.add_item(item)
			message.emit("No room in your bag")
			return &"no_room"
	return &""


## Takes off a worn item into the bag (at [param pos] if given and free).
func unequip(slot: StringName, pos := Vector2i(-1, -1)) -> bool:
	var item := equipment.get_item(slot)
	if item == null:
		return false
	if pos.x >= 0 and inventory.is_area_free(pos, item.get_size()):
		equipment.unequip(slot)
		inventory.place_at(item, pos)
		return true
	if not inventory.can_fit(item):
		message.emit("No room in your bag")
		return false
	equipment.unequip(slot)
	inventory.add_item(item)
	return true


# --- Using items ------------------------------------------------------------

## Right click: drink a potion, study a spellbook, or wear gear.
func use_item(item: ItemInstance) -> bool:
	match item.get_kind():
		ItemDefs.Kind.GEAR:
			return equip(item) == &""
		ItemDefs.Kind.POTION:
			return _drink(item)
		ItemDefs.Kind.SPELLBOOK:
			return _study(item)
	return false


## Drinks the strongest healing draught in the bag (for a potion hotkey).
func drink_health_potion() -> bool:
	var best: ItemInstance
	for item in inventory.items():
		var base := item.get_base()
		if base and base.kind == ItemDefs.Kind.POTION and base.heal_amount > 0.0:
			if best == null or base.heal_amount > best.get_base().heal_amount:
				best = item
	if best == null:
		message.emit("No healing draughts")
		return false
	return _drink(best)


func _drink(item: ItemInstance) -> bool:
	var base := item.get_base()
	var did := false
	if base.heal_amount > 0.0 and health and health.has_method("heal"):
		if health.get("health") != null and health.get("max_health") != null and health.health >= health.max_health:
			message.emit("Already at full health")
			return false
		health.heal(base.heal_amount)
		did = true
	if base.resource_amount > 0.0 and caster:
		var res: Object = caster.get("caster_resource")
		if res:
			var amount := base.resource_amount
			# A sorcerer's strain builds up, so the draught cools it instead.
			if res.get_script() and res.get_script().get_global_name() == &"StrainPool":
				amount = -amount
			res.call("_set_current", clampf(res.current + amount, 0.0, res.maximum))
			did = true
	if not did and health == null and caster == null:
		did = true  # No player bound (sandbox): still use it up.
	if did:
		inventory.consume(item)
		item_used.emit(item)
	return did


func _study(item: ItemInstance) -> bool:
	var character := character_snapshot()
	if String(character.get("path", "")) != "wizard":
		message.emit("Only a wizard can study a spellbook")
		return false
	var source: Object = caster.get("source") if caster else null
	if source == null or not source.has_method("add_book"):
		message.emit("Nothing to study it with yet")
		return false
	source.add_book(item.spell_id, item.circle)
	inventory.consume(item)
	item_used.emit(item)
	message.emit("%s (Circle %s) added to your Library" % [ItemDatabase.spell_display_name(item.spell_id), ItemInstance._roman(item.circle)])
	return true


# --- Picking up and dropping -------------------------------------------------

## Puts an item in the bag. Returns false (and leaves it on the ground) if it does not fit.
func pick_up(item: ItemInstance) -> bool:
	if not inventory.can_fit(item):
		message.emit("Your bag is full")
		return false
	inventory.add_item(item)
	item_picked_up.emit(item)
	return true


## Enemies' gem drop: [{"id": &"gold", "count": 12}, ...] (EnemyLootDrop calls this group).
func on_loot_collected(loot: Array, _collector: Node) -> void:
	collect_loot(loot)


func collect_loot(loot: Array) -> void:
	for item in LootRoller.from_enemy_loot(loot):
		if not pick_up(item):
			drop_item(item, _player_position())


## Every kill also rolls the item tables for the enemy's level, elite status and the current biome.
func on_enemy_died(enemy: Node, _xp_value: int, _loot: Array) -> void:
	if not drop_items_on_kill or enemy == null:
		return
	_kills += 1
	var level := int(enemy.get("level")) if enemy.get("level") != null else 1
	var rng := LootRoller.rng_for(loot_seed, _kills, level)
	var drops := LootRoller.roll(LootRoller.source_for_enemy(enemy), current_biome, level, rng,
			get_gear_stat(&"magic_find"), get_gear_stat(&"gold_find"))
	var origin: Vector3 = enemy.global_position if enemy is Node3D else _player_position()
	spawn_drops(drops, origin, enemy.get_parent() if enemy.get_parent() else get_tree().current_scene)


## Scatters items on the ground around [param origin].
func spawn_drops(items: Array[ItemInstance], origin: Vector3, parent: Node = null) -> Array[Node]:
	var nodes: Array[Node] = []
	if parent == null:
		parent = get_tree().current_scene
	if parent == null:
		return nodes
	for i in items.size():
		var angle := TAU * float(i) / maxf(items.size(), 1) + 0.6
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * (1.0 + 0.6 * float(i % 3))
		nodes.append(PICKUP_SCRIPT.spawn(items[i], parent, origin + offset))
	return nodes


## Drops an item from the bag (or one never added) on the ground near the player.
func drop_item(item: ItemInstance, at := Vector3.INF) -> Node:
	if inventory.has_item(item):
		inventory.remove_item(item)
	var pos := _player_position() if at == Vector3.INF else at
	item_dropped.emit(item)
	return PICKUP_SCRIPT.spawn(item, get_tree().current_scene, pos + Vector3(0.8, 0, 0.4))


## Sells a bag item for its value (vendors).
func sell_item(item: ItemInstance) -> int:
	if not inventory.has_item(item):
		return 0
	var value := item.get_sell_value()
	inventory.remove_item(item)
	inventory.add_gold(value)
	return value


# --- Stats ------------------------------------------------------------------

## Refreshes at the end of this frame (several changes in a row refresh once).
func queue_refresh() -> void:
	if not _refresh_queued:
		_refresh_queued = true
		refresh_stats.call_deferred()


## Re-applies worn gear to the bound player's combat nodes:
## CombatStats from attributes plus gear, health (Progression's max_health()
## plus CombatStats.bonus_health, the same sum the game session uses),
## armor, resistances, regen and "+N to a spell".
func refresh_stats() -> void:
	_refresh_queued = false
	if player and not is_instance_valid(player):
		player = null
		caster = null
		health = null
	_gear_stats = equipment.total_stats()
	var character := character_snapshot()
	var stats: Resource = null
	if caster and caster.has_method("set_stats"):
		stats = ItemStats.build_combat_stats(String(character.get("path", "")), character.get("attributes", {}), _gear_stats)
		if stats:
			caster.set_stats(stats)
	_apply_spell_bonuses()
	if health:
		var progression := _progression()
		if progression:
			var p: Object = progression.get("progression")
			var total: float = p.max_health() + (float(stats.get("bonus_health")) if stats else ItemStats.bonus_health(_gear_stats))
			ItemStats.apply_to_health(health, _gear_stats, total, p.health_regen())
		else:
			# No progression: remember the body's own maximum the first time.
			if not health.has_meta(&"base_max_health"):
				health.set_meta(&"base_max_health", float(health.get("max_health")))
			ItemStats.apply_to_health(health, _gear_stats, float(health.get_meta(&"base_max_health")) + ItemStats.bonus_health(_gear_stats))
	gear_stats_changed.emit(_gear_stats)


func _apply_spell_bonuses() -> void:
	var source: Object = caster.get("source") if caster else null
	if source == null or source.get("gear_bonus_ranks") == null:
		return
	var bonuses := equipment.spell_bonuses()
	if source.get("gear_bonus_ranks") != bonuses:
		ItemStats.apply_to_spell_source(source, bonuses)


func _on_caster_source_changed() -> void:
	_apply_spell_bonuses()


func _add_screen() -> void:
	var layer := CanvasLayer.new()
	layer.name = "InventoryLayer"
	layer.layer = 20
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	screen = load("res://ui/inventory/inventory_screen.gd").new()
	screen.name = "InventoryScreen"
	layer.add_child(screen)


func _on_equipment_changed() -> void:
	equipment_changed.emit()
	refresh_stats()


# --- New game, save and load -------------------------------------------------

## A level 1 arcanist's things: an oak staff, a linen robe, sandals, a few draughts.
func give_starter_kit() -> void:
	var kit: Dictionary = ItemDatabase.loot_config().get("starter_kit", {})
	for id in kit.get("equipped", []):
		var item := ItemInstance.create(StringName(id))
		var slot := equipment.best_slot_for(item)
		if slot != &"":
			equipment.equip(item, slot)
	for entry in kit.get("bag", []):
		inventory.add_item(ItemInstance.create(StringName(entry["id"]), int(entry.get("qty", 1))))
	inventory.add_gold(int(kit.get("gold", 0)))


func reset() -> void:
	inventory.clear()
	equipment.clear()
	_kills = 0


func to_dict() -> Dictionary:
	return {"inventory": inventory.to_dict(), "equipment": equipment.to_dict(), "kills": _kills}


func apply_dict(d: Dictionary) -> void:
	inventory.apply_dict(d.get("inventory", {}))
	equipment.apply_dict(d.get("equipment", {}))
	_kills = int(d.get("kills", 0))


## Saves the character and the items together (needs the Progression autoload).
func save_game(slot: int, extra := {}) -> Error:
	var progression := _progression()
	if progression == null:
		return ERR_UNAVAILABLE
	var all := extra.duplicate()
	all[SAVE_KEY] = to_dict()
	return progression.save_game(slot, all)


## Standalone save for scenes without progression.
func save_to_file(path: String) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(to_dict(), "\t"))
	return OK


func load_from_file(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		return false
	apply_dict(data)
	return true


## New game (no items in the save): starter kit. Load: restore the bag and gear.
func _on_character_loaded() -> void:
	var extra: Dictionary = _progression().get("loaded_extra")
	reset()
	if extra.has(SAVE_KEY):
		apply_dict(extra[SAVE_KEY])
	else:
		give_starter_kit()
	refresh_stats()


static func describe_reason(reason: StringName, item: ItemInstance = null) -> String:
	match reason:
		&"level":
			return "Requires level %d" % (item.get_required_level() if item else 0)
		&"path":
			return "Only a %s can use this" % (item.get_required_path() if item else "")
		&"wrong_slot":
			return "That doesn't go there"
		&"not_gear":
			return "You can't wear that"
		&"no_room":
			return "No room in your bag"
	if ItemDefs.ATTRIBUTES.has(reason) and item:
		return "Requires %d %s" % [int(item.get_requirements().get(reason, 0)), String(reason).capitalize()]
	return String(reason).capitalize()


func _progression() -> Node:
	var p := get_node_or_null(^"/root/Progression")
	return p if p and p.get("progression") != null else null


func _player_position() -> Vector3:
	if player and is_instance_valid(player):
		return player.global_position
	var p := get_tree().get_first_node_in_group(&"player") as Node3D
	return p.global_position if p else Vector3.ZERO


static func _find_child_with(node: Node, method: String) -> Node:
	for child in node.get_children():
		if child.has_method(method):
			return child
	for child in node.get_children():
		var found := _find_child_with(child, method)
		if found:
			return found
	return null
