class_name GameHud
extends Control
## In-game HUD: health orb, path resource orb (mana, arcana or strain), XP bar,
## an eight-slot spell bar with cooldowns, a cast bar for long casts, the
## character frame, and the level-up banner.
##
## Call bind() with the player's HealthComponent, SpellCaster and progression
## node (one node can fill several roles, as UiMockPlayer does).

signal character_sheet_requested
signal talents_requested

const KEY_HINTS := ["LMB", "RMB", "1", "2", "3", "4", "5", "6"]
const ORB_SIZE := 132.0

var health_source: Object
var caster_source: Object
var progression_source: Object

var health_orb: UiOrb
var resource_orb: UiOrb
var health_label: Label
var resource_label: Label
var xp_bar: ProgressBar
var cast_bar: ProgressBar
var cast_label: Label
var slots: Array[UiSpellSlot] = []
var name_label: Label
var level_label: Label
var points_button: Button
var talent_button: Button
var banner: VBoxContainer
var banner_title: Label
var banner_text: Label

var _vignette: TextureRect
var _bar: Array = []
var _cast_total := 0.0
var _cast_elapsed := -1.0
var _resource_kind: StringName = &"mana"
var _stats: Dictionary = {}
var _banner_tween: Tween
var _vignette_tween: Tween


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiTheme.get_theme()
	_build()


func bind(health: Object, caster: Object, progression: Object) -> void:
	unbind()
	health_source = health
	caster_source = caster
	progression_source = progression
	UiBind.connect_all(health_source, self, "_on_health_")
	UiBind.connect_all(caster_source, self, "_on_caster_")
	UiBind.connect_all(progression_source, self, "_on_progress_")
	_pull_initial()


func unbind() -> void:
	UiBind.disconnect_all(health_source, self, "_on_health_")
	UiBind.disconnect_all(caster_source, self, "_on_caster_")
	UiBind.disconnect_all(progression_source, self, "_on_progress_")


func _pull_initial() -> void:
	var cur: Variant = UiBind.read(health_source, ["current_health", "current", "health"], 0.0)
	var mx: Variant = UiBind.read(health_source, ["max_health", "maximum", "max"], 1.0)
	_on_health_health_changed(float(cur), float(mx))
	health_orb.snap()
	_on_caster_bar_changed()
	var res: Variant = UiBind.read(caster_source, ["caster_resource"])
	var rcur: Variant = UiBind.read(caster_source, ["current_resource", "resource_current"])
	var rmax: Variant = UiBind.read(caster_source, ["max_resource", "resource_max"])
	if res is Object:
		rcur = UiBind.read(res, ["current", "value"], rcur)
		rmax = UiBind.read(res, ["maximum", "max_value"], rmax)
	if rcur != null and rmax != null:
		_on_caster_resource_changed(float(rcur), float(rmax))
	resource_orb.snap()
	_on_progress_stats_changed()


# --- Health ---

func _on_health_health_changed(current: float, maximum: float) -> void:
	health_orb.ratio = current / maxf(maximum, 1.0)
	health_label.text = "%d / %d" % [roundi(current), roundi(maximum)]
	health_orb.tooltip_text = "Health %d / %d" % [roundi(current), roundi(maximum)]


func _on_health_damaged(_hit: Variant = null, amount: float = 0.0) -> void:
	if amount <= 0.0:
		return
	if _vignette_tween:
		_vignette_tween.kill()
	_vignette.modulate.a = clampf(0.35 + amount / 60.0, 0.35, 1.0)
	_vignette_tween = create_tween()
	_vignette_tween.tween_property(_vignette, "modulate:a", 0.0, 0.6).set_ease(Tween.EASE_OUT)


# --- Spell caster ---

func _on_caster_resource_changed(current: float, maximum: float) -> void:
	_resource_kind = _read_resource_kind()
	var color := UiTheme.resource_color(_resource_kind)
	resource_orb.fill_color = color
	resource_orb.ratio = current / maxf(maximum, 1.0)
	resource_orb.overfill = _resource_kind == &"strain" and current > maximum
	resource_label.text = "%d / %d" % [roundi(current), roundi(maximum)]
	var rname := UiTheme.resource_name(_resource_kind)
	resource_orb.tooltip_text = "%s %d / %d" % [rname, roundi(current), roundi(maximum)]
	if _resource_kind == &"strain":
		resource_orb.tooltip_text += "\nStrain builds as you cast and fades when you stop. Past capacity you overstrain: +25% damage, but each cast hurts you."


func _read_resource_kind() -> StringName:
	var res: Variant = UiBind.read(caster_source, ["caster_resource", "resource_kind"])
	if res is String or res is StringName:
		return StringName(str(res).to_lower())
	if res is Object:
		return StringName(str(UiBind.read(res, ["kind", "id", "resource_name"], "mana")).to_lower())
	return &"mana"


func _on_caster_bar_changed() -> void:
	var bar: Variant = UiBind.read(caster_source, ["action_bar"], [])
	_bar = bar if bar is Array else []
	for i in slots.size():
		var spell: Variant = _bar[i] if i < _bar.size() else null
		slots[i].spell = spell
		slots[i].cooldown_remaining = 0.0
		if spell != null and caster_source and caster_source.has_method("get_cooldown_remaining"):
			var rem: float = caster_source.get_cooldown_remaining(spell)
			if rem > 0.0:
				slots[i].start_cooldown(maxf(rem, float(UiBind.read(spell, ["cooldown"], rem))))
				slots[i].cooldown_remaining = rem


func _slot_for(spell: Variant) -> UiSpellSlot:
	var i := _bar.find(spell)
	return slots[i] if i >= 0 and i < slots.size() else null


func _on_caster_spell_cast(spell: Variant) -> void:
	var slot := _slot_for(spell)
	if slot:
		slot.flash()
	_end_cast()


func _on_caster_cooldown_started(spell: Variant, duration: float) -> void:
	var slot := _slot_for(spell)
	if slot:
		slot.start_cooldown(duration)


func _on_caster_cast_started(spell: Variant, cast_time: float) -> void:
	if cast_time <= 0.0:
		return
	_cast_total = cast_time
	_cast_elapsed = 0.0
	cast_label.text = UiBind.spell_name(spell)
	cast_bar.value = 0.0
	cast_bar.modulate = Color.WHITE
	cast_bar.visible = true


func _on_caster_cast_interrupted() -> void:
	if cast_bar.visible:
		cast_label.text = "Interrupted"
		cast_bar.modulate = Color(1, 0.4, 0.35)
		_cast_elapsed = -1.0
		var t := create_tween()
		t.tween_interval(0.5)
		t.tween_callback(_end_cast)


func _on_caster_cast_failed(spell: Variant, _reason: Variant = "") -> void:
	var slot := _slot_for(spell)
	if slot:
		slot.fail()


func _end_cast() -> void:
	_cast_elapsed = -1.0
	cast_bar.visible = false


func _process(delta: float) -> void:
	if _cast_elapsed < 0.0:
		return
	_cast_elapsed += delta
	var progress := _cast_elapsed / maxf(_cast_total, 0.01)
	if caster_source and caster_source.has_method("get_cast_progress"):
		progress = caster_source.get_cast_progress()
	cast_bar.value = clampf(progress, 0.0, 1.0) * 100.0


# --- Progression ---
# Progression payloads are not settled yet, so every handler re-reads the
# whole picture from get_stats() and takes the arguments only as a fallback.

func _on_progress_xp_gained(_amount: Variant = 0, xp: Variant = null, xp_to_next: Variant = null) -> void:
	_on_progress_stats_changed()
	if not progression_source or not progression_source.has_method("get_stats"):
		if xp != null and xp_to_next != null:
			_set_xp(int(xp), int(xp_to_next))


func _on_progress_leveled_up(level: Variant = 0, _b: Variant = null, _c: Variant = null) -> void:
	_on_progress_stats_changed()
	show_level_up(int(level) if level else int(_stats.get("level", 1)))


func _on_progress_stats_changed(stats: Variant = null, _b: Variant = null) -> void:
	if progression_source and progression_source.has_method("get_stats"):
		_stats = progression_source.get_stats()
	elif stats is Dictionary:
		_stats = stats
	if _stats.is_empty():
		return
	name_label.text = str(_stats.get("name", "Arcanist"))
	level_label.text = "Level %d · %s" % [int(_stats.get("level", 1)), path_title(_stats)]
	_set_xp(int(_stats.get("xp", 0)), int(_stats.get("xp_to_next", 1)))
	var points := int(_stats.get("unspent_attribute_points", 0))
	points_button.visible = points > 0
	points_button.text = "+%d attribute point%s  (C)" % [points, "" if points == 1 else "s"]
	var open_rows := open_talent_rows(_stats)
	talent_button.visible = open_rows > 0
	talent_button.text = "Talent choice ready  (K)"


func _set_xp(xp: int, to_next: int) -> void:
	xp_bar.max_value = maxi(to_next, 1)
	xp_bar.value = xp
	xp_bar.tooltip_text = "Experience %d / %d  (%d%%)" % [xp, to_next, roundi(100.0 * xp / maxf(to_next, 1))]


static func path_title(stats: Dictionary) -> String:
	var path := str(stats.get("path", ""))
	var spec := str(stats.get("specialization", ""))
	if path == "" or path == "arcanist" or path == "none":
		return "Arcanist"
	return ("%s %s" % [spec.capitalize(), path.capitalize()]).strip_edges()


## Talent rows the player has reached but not picked.
static func open_talent_rows(stats: Dictionary) -> int:
	var tree: Dictionary = stats.get("talent_tree", {})
	var choices: Array = stats.get("talent_choices", [])
	var count := 0
	var rows: Array = tree.get("rows", [])
	for i in rows.size():
		if int(stats.get("level", 1)) >= int(rows[i].level) and (i >= choices.size() or int(choices[i]) < 0):
			count += 1
	return count


func show_level_up(level: int) -> void:
	banner_title.text = "Level %d" % level
	var lines: PackedStringArray = ["+%d attribute points" % UiStats.POINTS_PER_LEVEL]
	if level == 5:
		lines.append("Choose your path: wizard, mage or sorcerer")
	elif level == 10:
		lines.append("Choose your specialization and first talent")
	elif level > 10 and level % 2 == 0:
		lines.append("A new talent row opens")
	if level >= 5:
		lines.append("+1 step of spell growth")
	banner_text.text = "\n".join(lines)
	if _banner_tween:
		_banner_tween.kill()
	banner.visible = true
	banner.modulate.a = 0.0
	banner.scale = Vector2(0.85, 0.85)
	_banner_tween = create_tween()
	_banner_tween.set_parallel(true)
	_banner_tween.tween_property(banner, "modulate:a", 1.0, 0.3)
	_banner_tween.tween_property(banner, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_banner_tween.chain().tween_interval(2.6)
	_banner_tween.chain().tween_property(banner, "modulate:a", 0.0, 0.8)
	_banner_tween.chain().tween_callback(banner.hide)


# --- Layout ---

func _build() -> void:
	_vignette = TextureRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	grad.colors = PackedColorArray([Color(0.7, 0, 0, 0), Color(0.7, 0, 0, 0), Color(0.7, 0.02, 0.02, 0.75)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.05, 1.05)
	_vignette.texture = tex
	_vignette.modulate.a = 0.0
	add_child(_vignette)

	_build_frame()
	_build_dock()
	_build_banner()


func _build_frame() -> void:
	var frame := VBoxContainer.new()
	frame.name = "CharacterFrame"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.position = Vector2(20, 16)
	frame.add_theme_constant_override("separation", 2)
	add_child(frame)
	name_label = Label.new()
	name_label.theme_type_variation = &"HeaderLabel"
	name_label.text = "Arcanist"
	frame.add_child(name_label)
	level_label = Label.new()
	level_label.text = "Level 1 · Arcanist"
	frame.add_child(level_label)
	points_button = Button.new()
	points_button.name = "PointsButton"
	points_button.visible = false
	points_button.focus_mode = Control.FOCUS_NONE
	points_button.add_theme_color_override("font_color", UiTheme.GOOD)
	points_button.pressed.connect(func(): character_sheet_requested.emit())
	frame.add_child(points_button)
	talent_button = Button.new()
	talent_button.name = "TalentButton"
	talent_button.visible = false
	talent_button.focus_mode = Control.FOCUS_NONE
	talent_button.add_theme_color_override("font_color", UiTheme.GOLD_BRIGHT)
	talent_button.pressed.connect(func(): talents_requested.emit())
	frame.add_child(talent_button)
	for b in [points_button, talent_button]:
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN


func _build_dock() -> void:
	var outer := VBoxContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.offset_bottom = -10
	outer.alignment = BoxContainer.ALIGNMENT_END
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(outer)

	var dock := HBoxContainer.new()
	dock.name = "Dock"
	dock.alignment = BoxContainer.ALIGNMENT_CENTER
	dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dock.add_theme_constant_override("separation", 14)
	outer.add_child(dock)

	health_orb = UiOrb.new()
	health_orb.name = "HealthOrb"
	health_orb.custom_minimum_size = Vector2(ORB_SIZE, ORB_SIZE)
	health_orb.fill_color = UiTheme.HEALTH
	health_label = _orb_label(health_orb)
	dock.add_child(health_orb)

	var center := VBoxContainer.new()
	center.alignment = BoxContainer.ALIGNMENT_END
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_theme_constant_override("separation", 6)
	dock.add_child(center)

	cast_bar = ProgressBar.new()
	cast_bar.name = "CastBar"
	cast_bar.show_percentage = false
	cast_bar.custom_minimum_size = Vector2(0, 18)
	cast_bar.visible = false
	var cast_fill := StyleBoxFlat.new()
	cast_fill.bg_color = UiTheme.GOLD
	cast_bar.add_theme_stylebox_override("fill", cast_fill)
	cast_label = Label.new()
	cast_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	cast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cast_label.add_theme_font_size_override("font_size", 13)
	cast_bar.add_child(cast_label)
	var cast_wrap := MarginContainer.new()
	cast_wrap.add_theme_constant_override("margin_left", 120)
	cast_wrap.add_theme_constant_override("margin_right", 120)
	cast_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cast_wrap.add_child(cast_bar)
	center.add_child(cast_wrap)

	var bar_panel := PanelContainer.new()
	var bar_style := UiTheme.panel_style(Color(0.05, 0.045, 0.06, 0.88), UiTheme.GOLD_DIM, 2, 6)
	bar_style.set_content_margin_all(8)
	bar_panel.add_theme_stylebox_override("panel", bar_style)
	center.add_child(bar_panel)
	var bar_box := VBoxContainer.new()
	bar_box.add_theme_constant_override("separation", 8)
	bar_panel.add_child(bar_box)

	var hotbar := HBoxContainer.new()
	hotbar.name = "Hotbar"
	hotbar.add_theme_constant_override("separation", 6)
	bar_box.add_child(hotbar)
	for i in KEY_HINTS.size():
		var slot := UiSpellSlot.new()
		slot.name = "Slot%d" % i
		slot.key_hint = KEY_HINTS[i]
		hotbar.add_child(slot)
		slots.append(slot)
		if i == 1:
			# Gap between the mouse spells and the number keys.
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(10, 0)
			gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hotbar.add_child(gap)

	xp_bar = ProgressBar.new()
	xp_bar.name = "XpBar"
	xp_bar.show_percentage = false
	xp_bar.custom_minimum_size = Vector2(0, 9)
	xp_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	bar_box.add_child(xp_bar)

	resource_orb = UiOrb.new()
	resource_orb.name = "ResourceOrb"
	resource_orb.custom_minimum_size = Vector2(ORB_SIZE, ORB_SIZE)
	resource_orb.fill_color = UiTheme.resource_color(&"mana")
	resource_label = _orb_label(resource_orb)
	dock.add_child(resource_orb)


func _orb_label(orb: UiOrb) -> Label:
	orb.size_flags_vertical = Control.SIZE_SHRINK_END
	var l := Label.new()
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_constant_override("outline_size", 5)
	orb.add_child(l)
	return l


func _build_banner() -> void:
	banner = VBoxContainer.new()
	banner.name = "LevelUpBanner"
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner.offset_top = 150
	banner.offset_left = -300
	banner.offset_right = 300
	banner.pivot_offset = Vector2(300, 60)
	banner.visible = false
	add_child(banner)
	banner_title = Label.new()
	banner_title.theme_type_variation = &"TitleLabel"
	banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_child(banner_title)
	banner_text = Label.new()
	banner_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_text.add_theme_font_size_override("font_size", 19)
	banner.add_child(banner_text)
