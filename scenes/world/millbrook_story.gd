extends Node3D
## Puts the prologue and The Hat and the Warden into the generated Millbrook:
## quest NPCs and props next to the buildings the village factory placed,
## quest areas over the home, tavern, green, barley and hill road, the old
## mill by the pond, the wolves in the barley, and the story events
## (lightning, the rider on the ridge, Hale's escort, the Wardens leaving).
## Must come after the Millbrook VillageSite and before Vegetation in the scene
## tree, so the old mill's spot is kept clear of trees.

const HOUND_SCENE := preload("res://actors/enemies/types/gloom_hound.tscn")
const ESCORT_SCENE := preload("res://actors/enemies/types/bramble_brute.tscn")
const HILL_ROAD := Vector2(10, -56)

@export var terrain_path: NodePath = ^"../Terrain"
@export var village_path: NodePath = ^"../Millbrook"
@export var player_path: NodePath = ^"../Player"

var _terrain: Terrain
var _quests: QuestManager
var _npcs: Dictionary = {}  # npc_id -> Node3D
var _spots: Dictionary = {}  # npc_id -> Vector3 where they normally stand
var _barley_center := Vector3.ZERO
var _flash: ColorRect
var _hounds: Array[Node] = []


func _ready() -> void:
	_terrain = get_node(terrain_path) as Terrain
	_quests = QuestManager.find(get_tree())
	var plan: VillagePlan = get_node(village_path).plan
	if _quests == null or plan == null:
		return
	_place(plan)
	_build_flash()
	_quests.story_event.connect(_on_story_event)
	_quests.quest_stage_changed.connect(_on_stage_changed)
	_quests.flag_changed.connect(func(_f: StringName, _v: Variant, _p: Variant) -> void: _sync_npcs())
	_quests.state_loaded.connect(_sync_npcs)
	_sync_npcs()
	if _quests.get_quest_stage(&"prologue") == &"wolves":
		_spawn_hounds.call_deferred()


# --- placement ---------------------------------------------------------------

func _place(plan: VillagePlan) -> void:
	var home := plan.first_of("home_farm")
	var tavern := plan.first_of("tavern")
	var farm := plan.first_of("farm")
	var field_owner := farm if farm != null else home
	var green := plan.center

	# Home: the kitchen chores happen in the yard by the front door.
	var door := _front(home, 2.5)
	_add_area(&"kitchen", door, Vector3(home.size.x + 2.0, 4, 6), home.yaw)
	_add_kitchen_props(door, home.yaw)
	_add_npc(&"home_bed", _front(home, 1.4, home.size.x * 0.32), "", true)
	_add_npc(&"tam", _front(home, 3.5, -2.5), "tam")

	# The green: Rook bothers Tam by the well, the Wardens gather, the children play.
	var side := plan.main_direction.orthogonal()
	_add_area(&"village_square", _at(green), Vector3(plan.green_radius * 2.0, 4, plan.green_radius * 2.0), 0.0)
	_add_npc(&"rook", _at(green + side * 2.6), "villager", false, 21, "child")
	_add_npc(&"warden_sergeant", _at(green - side * 3.0 + plan.main_direction * 1.5), "villager", false, 31, "militia")
	_add_npc(&"children", _at(green - plan.main_direction * 3.0), "villager", false, 22, "child")

	# Tavern.
	var tavern_front := _front(tavern, 2.5)
	_add_area(&"tavern", tavern_front, Vector3(tavern.size.x + 2.0, 4, 7), tavern.yaw)
	_add_npc(&"innkeeper", _front(tavern, 2.0, tavern.size.x * 0.3), "villager", false, 41, "merchant")
	_add_npc(&"old_man", _front(tavern, 2.2, -tavern.size.x * 0.3), "old_man")
	_add_npc(&"warden_lieutenant", _front(tavern, 4.0), "villager", false, 32, "militia")

	# Barley: the farm's field, with Farmer Hollis at the gate.
	var field := field_owner.field_center()
	_barley_center = _at(field)
	_add_area(&"barley", _barley_center, Vector3(field_owner.field_size.x, 4, field_owner.field_size.y), field_owner.yaw)
	var gate := field_owner.position + Vector2(sin(field_owner.yaw), cos(field_owner.yaw)) * (field_owner.field_offset * 0.5)
	_add_npc(&"farmer_hollis", _at(gate + Vector2(cos(field_owner.yaw), -sin(field_owner.yaw)) * (field_owner.size.x * 0.5 + 1.5)), "villager", false, 11, "farmer")

	# The hill road, partway up toward the ruins.
	_add_area(&"hill_road", _at(HILL_ROAD), Vector3(8, 4, 8), 0.0)

	# The old mill by the pond, where the hat can be hidden.
	var mill := _terrain.pond_center + Vector2(13, 6)
	_terrain.reserve_area(mill, 6.0, true)
	_add_old_mill(_at(mill))
	_add_npc(&"old_mill_floorboards", _at(mill) + Vector3(0, 0.05, 0), "", true)


## A point in front of a building's door, `out` metres from the wall, shifted
## `across` metres along the front.
func _front(b: VillagePlan.Building, out: float, across := 0.0) -> Vector3:
	var forward := Vector2(sin(b.yaw), cos(b.yaw))
	var right := Vector2(cos(b.yaw), -sin(b.yaw))
	return _at(b.position + forward * (b.size.z * 0.5 + out) + right * across)


func _at(p: Vector2) -> Vector3:
	return Vector3(p.x, _terrain.height_at(p.x, p.y), p.y)


func _add_area(id: StringName, at: Vector3, size: Vector3, yaw: float) -> void:
	var area := QuestArea.new()
	area.name = "Area_%s" % id
	area.area_id = id
	area.size = size
	area.position = at
	area.rotation.y = yaw
	add_child(area)


func _add_npc(id: StringName, at: Vector3, kind: String, is_prop := false, seed_value := 1, role := "") -> void:
	var body: Node3D
	if is_prop:
		body = Node3D.new()
	else:
		body = Npc.create(kind, seed_value, role)
	body.name = String(id).to_pascal_case()
	body.position = at
	add_child(body)
	var talk := QuestNpc.new()
	talk.name = "QuestNpc"
	talk.npc_id = id
	talk.prompt_height = 1.4 if is_prop else 2.3
	talk.verb = "Use" if is_prop else "Talk"
	body.add_child(talk)
	_npcs[id] = body
	_spots[id] = at
	if not is_prop and body.has_method("face_toward"):
		body.face_toward.call_deferred(at + Vector3(0, 0, 3))


func _add_kitchen_props(at: Vector3, yaw: float) -> void:
	var root := Node3D.new()
	root.position = at
	root.rotation.y = yaw
	add_child(root)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.5, 0.34, 0.2)
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.2, 0.2, 0.22)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(1.0, 0.5, 0.2)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.45, 0.15)
	# Table with a spoon, and an iron stove: the first two chores.
	_box(root, Vector3(1.8, 0.1, 1.0), Vector3(-1.6, 0.85, 0), wood)
	for leg in [Vector3(-2.35, 0.4, -0.4), Vector3(-0.85, 0.4, -0.4), Vector3(-2.35, 0.4, 0.4), Vector3(-0.85, 0.4, 0.4)]:
		_box(root, Vector3(0.1, 0.8, 0.1), leg, wood)
	_box(root, Vector3(0.35, 0.03, 0.06), Vector3(-1.6, 0.92, 0), iron)
	_box(root, Vector3(0.9, 0.9, 0.9), Vector3(1.8, 0.45, 0), iron)
	_box(root, Vector3(0.4, 0.25, 0.05), Vector3(1.8, 0.35, 0.46), glow)
	_box(root, Vector3(0.2, 1.2, 0.2), Vector3(1.95, 1.4, -0.25), iron)


func _add_old_mill(at: Vector3) -> void:
	var root := Node3D.new()
	root.name = "OldMill"
	root.position = at
	add_child(root)
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.58, 0.56, 0.54)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.42, 0.3, 0.2)
	var body := StaticBody3D.new()
	root.add_child(body)
	# Three broken walls around a plank floor, and a fallen waterwheel.
	for wall in [[Vector3(0, 1.0, -2.6), Vector3(5.4, 2.0, 0.5)], [Vector3(-2.6, 0.7, 0), Vector3(0.5, 1.4, 5.0)], [Vector3(2.6, 1.3, 0.6), Vector3(0.5, 2.6, 3.6)]]:
		_box(root, wall[1], wall[0], stone)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = wall[1]
		shape.shape = box
		shape.position = wall[0]
		body.add_child(shape)
	_box(root, Vector3(4.6, 0.1, 4.6), Vector3(0, 0.05, 0), wood)
	var wheel := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 1.6
	cylinder.bottom_radius = 1.6
	cylinder.height = 0.35
	cylinder.radial_segments = 12
	wheel.mesh = cylinder
	wheel.material_override = wood
	wheel.position = Vector3(-3.6, 0.6, 1.0)
	wheel.rotation = Vector3(0.3, 0.0, 1.2)
	root.add_child(wheel)


func _box(root: Node3D, size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	mesh.position = at
	root.add_child(mesh)
	return mesh


# --- story -------------------------------------------------------------------

## Who is where depends on the story so far.
func _sync_npcs() -> void:
	var s := _quests.story
	var stage := _quests.get_quest_stage(&"prologue")
	var walking := stage in [&"hill_road", &"lightning"]
	_set_visible(&"old_man", not s.is_set(&"old_man_struck"))
	_move(&"old_man", _at(HILL_ROAD) + Vector3(1.5, 0, 0) if walking else _spots.get(&"old_man", Vector3.ZERO))
	_set_visible(&"warden_sergeant", s.is_set(&"had_dream") and not s.is_set(&"prologue_done"))
	_set_visible(&"warden_lieutenant", _quests.is_active(&"hat_and_warden") and not s.is_set(&"drove_off_wardens"))


func _set_visible(id: StringName, shown: bool) -> void:
	var npc: Node3D = _npcs.get(id)
	if npc == null:
		return
	npc.visible = shown
	var talk := npc.get_node(^"QuestNpc") as QuestNpc
	talk.monitoring = shown
	if not shown:
		talk.player_in_range = false
	for child in npc.get_children():
		if child is CollisionShape3D:
			child.disabled = not shown


func _move(id: StringName, at: Vector3) -> void:
	var npc: Node3D = _npcs.get(id)
	if npc != null and npc.position != at:
		npc.position = at


func _on_stage_changed(quest_id: StringName, stage_id: StringName) -> void:
	_sync_npcs()
	if quest_id == &"prologue" and stage_id == &"wolves":
		_spawn_hounds()


func _spawn_hounds() -> void:
	for hound in _hounds:
		if is_instance_valid(hound):
			hound.queue_free()
	_hounds.clear()
	for i in 3:
		var hound := HOUND_SCENE.instantiate()
		var spot := Vector2(_barley_center.x, _barley_center.z) + Vector2(-3.0 + i * 3.0, 1.5 * (i % 2))
		hound.position = _at(spot) + Vector3(0, 0.5, 0)
		hound.set(&"pack_id", 7)
		get_parent().add_child(hound)
		_hounds.append(hound)


func _on_story_event(event_name: StringName) -> void:
	var player := get_node_or_null(player_path) as Node3D
	match event_name:
		&"lightning_strike":
			_flash.color.a = 1.0
			create_tween().tween_property(_flash, "color:a", 0.0, 1.4)
			if player != null:
				_lightning_bolt(player.global_position + Vector3(2.5, 0, -1.5))
		&"warden_rider_watches":
			var rider := Npc.create("villager", 33, "militia")
			var ridge := _terrain.hill_center + Vector2(-14, 10)
			rider.position = _at(ridge)
			add_child(rider)
			if player != null:
				rider.face_toward.call_deferred(player.global_position)
			get_tree().create_timer(6.0).timeout.connect(rider.queue_free)
		&"warden_escort_attack":
			if player != null:
				var hale: Node3D = _npcs.get(&"warden_lieutenant")
				var origin: Vector3 = hale.global_position if hale != null else player.global_position
				for i in 2:
					var escort := ESCORT_SCENE.instantiate()
					escort.set_meta(&"quest_type", "warden_escort")
					escort.position = origin + Vector3(-2.0 + i * 4.0, 0.5, -2.0)
					get_parent().add_child(escort)


func _lightning_bolt(at: Vector3) -> void:
	var bolt := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.25
	mesh.bottom_radius = 0.08
	mesh.height = 60.0
	bolt.mesh = mesh
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0.85, 0.9, 1.0)
	glow.emission_enabled = true
	glow.emission = Color(0.8, 0.9, 1.0)
	glow.emission_energy_multiplier = 12.0
	bolt.material_override = glow
	bolt.position = at + Vector3(0, 30, 0)
	add_child(bolt)
	var light := OmniLight3D.new()
	light.light_color = Color(0.8, 0.88, 1.0)
	light.light_energy = 16.0
	light.omni_range = 30.0
	light.position = at + Vector3(0, 3, 0)
	add_child(light)
	var tween := create_tween()
	tween.tween_property(light, "light_energy", 0.0, 0.8)
	tween.parallel().tween_property(bolt, "scale", Vector3(0.1, 1, 0.1), 0.6)
	tween.tween_callback(func() -> void:
		bolt.queue_free()
		light.queue_free())


func _build_flash() -> void:
	var overlay := CanvasLayer.new()
	overlay.layer = 15
	_flash = ColorRect.new()
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(_flash)
	add_child(overlay)
