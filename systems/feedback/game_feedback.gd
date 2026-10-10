class_name GameFeedback
extends CanvasLayer
## The game's answer to everything the player does, so every action reads
## clearly on screen and by ear:
## - a crosshair that turns red over an enemy and gold over something you can
##   use magic on, and flicks out when a spell lands
## - damage numbers over enemies (bigger and gold on a crit), status words
##   ("Stunned!"), red numbers and a camera kick when the player is hurt
## - "+N XP" where a monster fell, a short hit-stop on each kill, a burst of
##   light on level-up, item and gold pickups
## - a toast with a chime for every finished quest objective
## - why a cast failed ("Not enough mana", "Recharging")
## - a synthesized sound for each of these (FeedbackSfx)
##
## GameSession adds one per play scene. It reads the player, the Progression,
## Items and Quests autoloads and every HealthComponent through signals only.

const TEXT := Color(0.96, 0.92, 0.82)
const GOLD := Color(1.0, 0.84, 0.42)
const XP_COLOR := Color(1.0, 0.78, 0.3)
const HURT := Color(1.0, 0.32, 0.28)
const HEAL := Color(0.45, 1.0, 0.45)
const ENEMY_AIM := Color(1.0, 0.35, 0.3)
const PROP_AIM := Color(1.0, 0.85, 0.35)
const BASE_HEIGHT := 900.0

const FAIL_TEXT := {
	&"no_resource": "Not enough power",
	&"cooldown": "Recharging",
	&"stunned": "Stunned!",
	&"no_target": "No target in reach",
}

## The player's root control; everything 2D sits in here and scales with the window.
var root: Control
var crosshair: FeedbackCrosshair
var toasts: VBoxContainer
var cast_message: Label

var _player: Node3D
var _caster: Node
var _aim: Node
var _camera: Camera3D
var _shake := 0.0
var _last_kill_position := Vector3.INF
var _last_kill_time := -10.0
var _last_hit_sound := -10.0
var _quiet_until := 0.0
var _gold := -1
var _cast_tween: Tween
var _hitstop_active := false
## Every popup this layer has spawned, newest last (tests read it).
var popups_shown: Array[String] = []
var toasts_shown: Array[String] = []


func _init() -> void:
	layer = 12
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	root = Control.new()
	root.name = "Root"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	crosshair = FeedbackCrosshair.new()
	crosshair.name = "Crosshair"
	root.add_child(crosshair)
	_build_toasts()
	_build_cast_message()
	_fit()
	get_viewport().size_changed.connect(_fit)

	add_to_group(&"enemy_listeners")
	_quiet_until = _now() + 1.5
	_bind_player.call_deferred()
	get_tree().node_added.connect(_on_node_added)
	for node in get_tree().root.find_children("HealthComponent", "", true, false):
		_watch_health(node)

	var progression := get_node_or_null(^"/root/Progression")
	if progression != null:
		progression.xp_gained.connect(_on_xp_gained)
		progression.leveled_up.connect(_on_leveled_up)
		progression.character_loaded.connect(func() -> void: _quiet_until = _now() + 1.0)
	var items := get_node_or_null(^"/root/Items")
	if items != null:
		_gold = items.inventory.gold
		items.item_picked_up.connect(_on_item_picked_up)
		items.gold_changed.connect(_on_gold_changed)
	var quests := QuestManager.find(get_tree())
	if quests != null:
		quests.objective_updated.connect(_on_objective_updated)
		quests.quest_completed.connect(func(_id: StringName) -> void: FeedbackSfx.play(self, &"level_up", -8.0, 1.25))


## Scales the 2D layer with the window so text stays readable on big screens.
func _fit() -> void:
	var size := get_viewport().get_visible_rect().size
	var s := maxf(size.y / BASE_HEIGHT, 1.0)
	root.scale = Vector2(s, s)
	root.size = size / s


func _bind_player() -> void:
	_player = get_tree().get_first_node_in_group(&"player") as Node3D
	if _player == null:
		return
	_caster = _player.get_node_or_null(^"SpellCaster")
	_aim = _player.get_node_or_null(^"PlayerCombatInput")
	_camera = _player.get_node_or_null(^"CameraPivot/SpringArm3D/Camera3D") as Camera3D
	if _caster != null:
		_caster.spell_cast.connect(_on_spell_cast)
		_caster.cast_failed.connect(_on_cast_failed)
	var health := _player.get_node_or_null(^"HealthComponent")
	if health != null:
		_watch_health(health)


func _process(delta: float) -> void:
	_update_crosshair()
	if _camera != null:
		if _shake > 0.0:
			_shake = maxf(_shake - delta * 2.5, 0.0)
			var amount := _shake * _shake * 0.18
			_camera.h_offset = randf_range(-amount, amount)
			_camera.v_offset = randf_range(-amount, amount)
		elif _camera.h_offset != 0.0 or _camera.v_offset != 0.0:
			_camera.h_offset = 0.0
			_camera.v_offset = 0.0


func shake(strength: float) -> void:
	_shake = clampf(maxf(_shake, strength), 0.0, 1.0)


# --- crosshair ---------------------------------------------------------------

func _update_crosshair() -> void:
	var playing := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not get_tree().paused
	crosshair.visible = playing and _player != null
	if not crosshair.visible:
		return
	crosshair.position = root.size * 0.5
	var color := TEXT
	if _aim != null and _aim.has_method(&"get_aim_point"):
		var target := aimed_target()
		if target != null:
			color = PROP_AIM if target.team == &"prop" else ENEMY_AIM
	crosshair.tint = color


## The enemy or prop under the crosshair, if any.
func aimed_target() -> HealthComponent:
	if _aim == null:
		return null
	var point: Vector3 = _aim.get_aim_point()
	if _player != null and point.distance_to(_player.global_position) > 45.0:
		return null
	for target in HealthComponent.find_in_radius(get_tree(), point, 1.2, &"player"):
		return target
	return null


# --- health ------------------------------------------------------------------

func _on_node_added(node: Node) -> void:
	if node.name == &"HealthComponent":
		_watch_health.call_deferred(node)


func _watch_health(health: Node) -> void:
	if not is_instance_valid(health) or not health.has_signal(&"damaged"):
		return
	if health.has_meta(&"feedback_watched"):
		return
	health.set_meta(&"feedback_watched", true)
	var body := health.get_parent()
	if body != null and body.is_in_group(&"player"):
		health.damaged.connect(_on_player_damaged)
		health.healed.connect(_on_player_healed)
		return
	if health.get(&"team") == &"prop":
		return
	health.damaged.connect(_on_enemy_damaged.bind(health))
	if health.has_signal(&"status_applied"):
		health.status_applied.connect(_on_enemy_status.bind(health))


func _on_enemy_damaged(hit: Object, amount: float, health: Node) -> void:
	if amount < 1.0 or not is_instance_valid(health):
		return
	var crit: bool = hit != null and bool(hit.get(&"is_crit"))
	var color := GOLD if crit else TEXT
	var spell: Variant = hit.get(&"spell") if hit != null else null
	if spell is SpellData and not crit:
		color = TEXT.lerp(spell.get_color(), 0.35)
	var text := ("%d!" % roundi(amount)) if crit else str(roundi(amount))
	popup(_target_position(health) + Vector3(randf_range(-0.4, 0.4), 0.3, 0.0), text, color, 1.5 if crit else 1.0)
	crosshair.hit_marker(crit)
	var t := _now()
	if t - _last_hit_sound > 0.05:
		_last_hit_sound = t
		FeedbackSfx.play(self, &"crit" if crit else &"hit", -8.0, randf_range(0.9, 1.15))


func _on_enemy_status(kind: int, _duration: float, health: Node) -> void:
	var word := ""
	match kind:
		Status.Kind.STUN:
			word = "Stunned!"
		Status.Kind.SLOW:
			word = "Slowed"
		Status.Kind.ROOT:
			word = "Rooted"
		Status.Kind.BURN:
			word = "Burning"
		Status.Kind.CHARM:
			word = "Charmed"
	if not word.is_empty() and is_instance_valid(health):
		popup(_target_position(health) + Vector3(0, 0.9, 0), word, Color(0.55, 0.8, 1.0), 1.1, 1.6)


func _on_player_damaged(_hit: Object, amount: float) -> void:
	if amount < 1.0 or _player == null:
		return
	popup(_player.global_position + Vector3(0.5, 2.0, 0), "-%d" % roundi(amount), HURT, 1.1)
	shake(0.35 + minf(amount / 30.0, 0.5))
	FeedbackSfx.play(self, &"hurt", -5.0, randf_range(0.9, 1.1))


func _on_player_healed(amount: float) -> void:
	if amount >= 5.0 and _player != null:
		popup(_player.global_position + Vector3(-0.5, 2.0, 0), "+%d" % roundi(amount), HEAL, 1.0)


func _target_position(health: Node) -> Vector3:
	if health.has_method(&"get_target_position"):
		return health.get_target_position() + Vector3(0, 0.8, 0)
	var body := health.get_parent() as Node3D
	return body.global_position + Vector3(0, 1.8, 0) if body != null else Vector3.ZERO


# --- kills, XP and level-ups --------------------------------------------------

func on_enemy_died(enemy: Node, _xp_value: int, _loot: Array) -> void:
	if enemy is Node3D:
		_last_kill_position = (enemy as Node3D).global_position + Vector3(0, 2.2, 0)
		_last_kill_time = _now()
		_spawn_ring(_last_kill_position - Vector3(0, 1.8, 0), Color(1.0, 0.8, 0.5), 1.8)
	FeedbackSfx.play(self, &"kill", -4.0)
	shake(0.25)
	hitstop(0.07)


## Freezes the action for a moment so a kill lands with weight.
func hitstop(seconds: float) -> void:
	if _hitstop_active or DisplayServer.get_name() == "headless":
		return
	_hitstop_active = true
	Engine.time_scale = 0.08
	await get_tree().create_timer(seconds, true, false, true).timeout
	Engine.time_scale = 1.0
	_hitstop_active = false


func _on_xp_gained(amount: int, source: String) -> void:
	if amount <= 0 or _player == null or source in ["debug", "load"]:
		return
	var at := _player.global_position + Vector3(0, 2.6, 0)
	if source == "kill" and _now() - _last_kill_time < 0.5 and _last_kill_position != Vector3.INF:
		at = _last_kill_position
	popup(at, "+%d XP" % amount, XP_COLOR, 1.25, 2.2)


func _on_leveled_up(level: int) -> void:
	FeedbackSfx.play(self, &"level_up", -2.0)
	if _player == null:
		return
	var at := _player.global_position
	popup(at + Vector3(0, 3.2, 0), "Level %d!" % level, GOLD, 2.2, 3.0)
	_spawn_ring(at + Vector3(0, 0.1, 0), GOLD, 4.0, 0.9)
	_spawn_pillar(at)
	shake(0.3)


# --- items -------------------------------------------------------------------

func _on_item_picked_up(item: Object) -> void:
	if _player == null or item == null or not item.has_method(&"get_display_name"):
		return
	var color: Color = item.get_color() if item.has_method(&"get_color") else TEXT
	popup(_player.global_position + Vector3(0, 2.3, 0), "+ %s" % item.get_display_name(), color, 1.0, 2.0)
	FeedbackSfx.play(self, &"pickup", -6.0)


func _on_gold_changed(gold: int) -> void:
	var delta := gold - _gold if _gold >= 0 else 0
	_gold = gold
	if delta <= 0 or _now() < _quiet_until or _player == null:
		return
	popup(_player.global_position + Vector3(0.6, 2.0, 0), "+%d gold" % delta, GOLD, 1.0)
	FeedbackSfx.play(self, &"gold", -8.0)


# --- quests ------------------------------------------------------------------

func _on_objective_updated(quest_id: StringName, objective_id: StringName, count: int, required: int) -> void:
	var quests := QuestManager.find(get_tree())
	if quests == null:
		return
	var objective := _find_objective(quests, quest_id, objective_id)
	if objective == null or objective.hidden:
		return
	if count >= required:
		toast("✓  " + objective.description, true)
		FeedbackSfx.play(self, &"objective", -4.0)
	else:
		toast("%s  %d / %d" % [objective.description, count, required], false)
		FeedbackSfx.play(self, &"chime", -10.0)


func _find_objective(quests: QuestManager, quest_id: StringName, objective_id: StringName) -> QuestObjective:
	var quest := quests.database.get_quest(quest_id)
	if quest == null:
		return null
	for stage in quest.stages:
		var objective := stage.get_objective(objective_id)
		if objective != null:
			return objective
	return null


func toast(text: String, done: bool) -> void:
	toasts_shown.append(text)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.05, 0.07, 0.82)
	style.border_color = Color(0.5, 0.9, 0.45) if done else Color(0.78, 0.62, 0.34)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_color", Color(0.7, 1.0, 0.6) if done else TEXT)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 6)
	panel.add_child(label)
	toasts.add_child(panel)
	panel.modulate.a = 0.0
	panel.pivot_offset = Vector2(150, 20)
	panel.scale = Vector2(1.25, 1.25)
	var tween := panel.create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 0.15)
	tween.parallel().tween_property(panel, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(2.4 if done else 1.4)
	tween.tween_property(panel, "modulate:a", 0.0, 0.5)
	tween.tween_callback(panel.queue_free)
	while toasts.get_child_count() > 3:
		toasts.get_child(0).free()


# --- casting -----------------------------------------------------------------

func _on_spell_cast(spell: Resource) -> void:
	var id := StringName(spell.get(&"id")) if spell != null else &""
	match id:
		&"spark":
			FeedbackSfx.play(self, &"spark", -12.0, randf_range(0.95, 1.1))
		&"nudge":
			FeedbackSfx.play(self, &"whoosh", -3.0)
		&"jolt":
			FeedbackSfx.play(self, &"zap", -5.0)
		_:
			var delivery: int = int(spell.get(&"delivery")) if spell != null else 0
			FeedbackSfx.play(self, &"spark" if delivery == SpellData.Delivery.PROJECTILE else &"zap", -9.0)


func _on_cast_failed(spell: Resource, reason: StringName) -> void:
	if reason == &"cooldown" and _caster != null and spell == _caster.get_cantrip():
		return  # clicking faster than the cantrip fires isn't worth a message
	var text: String = FAIL_TEXT.get(reason, "")
	if reason == &"cooldown" and spell != null:
		text = "%s is recharging" % spell.get(&"display_name")
	elif reason == &"no_resource" and _caster != null and _caster.get(&"caster_resource") != null:
		text = "Not enough %s" % String(_caster.caster_resource.get_display_name()).to_lower()
	if text.is_empty():
		return
	cast_message.text = text
	if _cast_tween:
		_cast_tween.kill()
	cast_message.modulate.a = 1.0
	_cast_tween = create_tween()
	_cast_tween.tween_interval(0.9)
	_cast_tween.tween_property(cast_message, "modulate:a", 0.0, 0.4)
	FeedbackSfx.play(self, &"dud", -10.0)


# --- world popups and effects -------------------------------------------------

## Floating text in the world that rises and fades. Keeps a constant size on
## screen so it is readable at any distance.
func popup(at: Vector3, text: String, color: Color, size_scale := 1.0, seconds := 1.2) -> Label3D:
	popups_shown.append(text)
	var parent := _world_parent()
	if parent == null:
		return null
	var label := Label3D.new()
	label.text = text
	label.font_size = 56
	label.outline_size = 14
	label.modulate = color
	label.outline_modulate = Color(0.05, 0.03, 0.02, 0.9)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.00055 * size_scale
	label.render_priority = 10
	label.outline_render_priority = 9
	parent.add_child(label)
	label.global_position = at
	label.scale = Vector3.ONE * 1.6
	var tween := label.create_tween()
	tween.tween_property(label, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, "global_position", at + Vector3(0, 1.1, 0), seconds).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, "modulate:a", 0.0, seconds * 0.4).set_delay(seconds * 0.6)
	tween.tween_callback(label.queue_free)
	return label


func _spawn_ring(at: Vector3, color: Color, radius: float, seconds := 0.45) -> void:
	var parent := _world_parent()
	if parent == null:
		return
	var ring := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.85
	mesh.outer_radius = 1.0
	mesh.rings = 32
	ring.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(color, 0.85)
	ring.material_override = material
	parent.add_child(ring)
	ring.global_position = at
	ring.scale = Vector3(0.2, 0.2, 0.2)
	var tween := ring.create_tween()
	tween.tween_property(ring, "scale", Vector3(radius, 0.3, radius), seconds).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.parallel().tween_property(material, "albedo_color:a", 0.0, seconds)
	tween.tween_callback(ring.queue_free)


func _spawn_pillar(at: Vector3) -> void:
	var parent := _world_parent()
	if parent == null:
		return
	var pillar := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.9
	mesh.bottom_radius = 0.9
	mesh.height = 14.0
	mesh.cap_top = false
	mesh.cap_bottom = false
	pillar.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(1.0, 0.85, 0.45, 0.45)
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	pillar.material_override = material
	parent.add_child(pillar)
	pillar.global_position = at + Vector3(0, 7.0, 0)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.85, 0.5)
	light.light_energy = 6.0
	light.omni_range = 9.0
	parent.add_child(light)
	light.global_position = at + Vector3(0, 1.5, 0)
	var tween := pillar.create_tween()
	tween.tween_property(pillar, "scale", Vector3(0.1, 1.0, 0.1), 1.2).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(material, "albedo_color:a", 0.0, 1.2)
	tween.parallel().tween_property(light, "light_energy", 0.0, 1.2)
	tween.tween_callback(func() -> void:
		pillar.queue_free()
		light.queue_free())


func _world_parent() -> Node:
	if _player != null and is_instance_valid(_player) and _player.get_parent() != null:
		return _player.get_parent()
	return get_tree().current_scene


func _build_toasts() -> void:
	toasts = VBoxContainer.new()
	toasts.name = "Toasts"
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	toasts.add_theme_constant_override("separation", 8)
	toasts.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toasts.anchor_top = 0.22
	toasts.anchor_bottom = 0.22
	toasts.offset_left = -500
	toasts.offset_right = 500
	root.add_child(toasts)


func _build_cast_message() -> void:
	cast_message = Label.new()
	cast_message.name = "CastMessage"
	cast_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cast_message.set_anchors_preset(Control.PRESET_CENTER)
	cast_message.offset_left = -300
	cast_message.offset_right = 300
	cast_message.offset_top = 40
	cast_message.offset_bottom = 80
	cast_message.add_theme_font_size_override("font_size", 24)
	cast_message.add_theme_color_override("font_color", Color(1.0, 0.6, 0.5))
	cast_message.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	cast_message.add_theme_constant_override("outline_size", 6)
	cast_message.modulate.a = 0.0
	cast_message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cast_message)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
