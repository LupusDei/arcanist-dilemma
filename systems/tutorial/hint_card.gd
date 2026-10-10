class_name HintCard
extends CanvasLayer
## The opening's teaching card: a large panel above the spell bar with the
## key to press drawn as a keycap, a title and one or two plain sentences.
## When the player does the thing it turns green with a check and a chime,
## then slides away. It can also pulse a spell slot on the HUD so the key and
## the spell it casts are linked on screen.
##
## Scales with the window height so it stays readable on large screens.

const BASE_HEIGHT := 900.0
const PARCHMENT := Color(0.96, 0.92, 0.82)
const GOLD := Color(1.0, 0.84, 0.45)
const DONE := Color(0.55, 0.95, 0.5)

var hint_id: StringName = &""
var root: Control
var panel: PanelContainer
var keys_box: HBoxContainer
var title_label: Label
var text_label: Label
## The HUD control to pulse (a spell slot), or null.
var highlight: Control

var _style: StyleBoxFlat
var _tween: Tween
var _pulse: Control
var _time := 0.0
var _completing := false


func _init() -> void:
	layer = 12
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	root = Control.new()
	root.name = "Root"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_pulse = Control.new()
	_pulse.name = "SlotPulse"
	_pulse.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pulse.draw.connect(_draw_pulse)
	add_child(_pulse)
	_build()
	_fit()
	get_viewport().size_changed.connect(_fit)
	panel.visible = false


func _process(delta: float) -> void:
	_time += delta
	_pulse.queue_redraw()


func is_showing() -> bool:
	return panel.visible and not hint_id.is_empty()


## Shows a hint. keys are keycap labels ("2", "Left click", "Shift").
func show_hint(id: StringName, title: String, text: String, keys: Array = [], slot: Control = null) -> void:
	if id == hint_id and panel.visible and not _completing:
		return
	hint_id = id
	_completing = false
	highlight = slot
	title_label.text = title
	title_label.add_theme_color_override("font_color", GOLD)
	text_label.text = text
	_style.border_color = GOLD
	for child in keys_box.get_children():
		child.queue_free()
	for key in keys:
		keys_box.add_child(_keycap(str(key)))
	keys_box.visible = not keys.is_empty()
	panel.visible = true
	if _tween:
		_tween.kill()
	panel.modulate.a = 0.0
	panel.position.y = 30.0
	_tween = create_tween()
	_tween.tween_property(panel, "modulate:a", 1.0, 0.25)
	_tween.parallel().tween_property(panel, "position:y", 0.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	FeedbackSfx.play(self, &"hint", -10.0)


## The player did it: green check, chime, then the card leaves.
func complete() -> void:
	if not is_showing() or _completing:
		return
	_completing = true
	highlight = null
	title_label.text = "✓  " + title_label.text
	title_label.add_theme_color_override("font_color", DONE)
	_style.border_color = DONE
	FeedbackSfx.play(self, &"chime", -6.0)
	if _tween:
		_tween.kill()
	panel.pivot_offset = panel.size * 0.5
	_tween = create_tween()
	_tween.tween_property(panel, "scale", Vector2(1.06, 1.06), 0.1)
	_tween.tween_property(panel, "scale", Vector2.ONE, 0.15)
	_tween.tween_interval(0.6)
	_tween.tween_property(panel, "modulate:a", 0.0, 0.35)
	_tween.tween_callback(_clear)


## Takes the card away without the check (the moment passed).
func dismiss() -> void:
	if not panel.visible or _completing:
		return
	highlight = null
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(panel, "modulate:a", 0.0, 0.25)
	_tween.tween_callback(_clear)
	hint_id = &""


func _clear() -> void:
	panel.visible = false
	panel.scale = Vector2.ONE
	hint_id = &""
	_completing = false


func _fit() -> void:
	var size := get_viewport().get_visible_rect().size
	var s := GameFeedback.ui_scale(self)
	root.scale = Vector2(s, s)
	root.size = size / s
	_pulse.size = size


func _draw_pulse() -> void:
	if highlight == null or not is_instance_valid(highlight) or not highlight.is_visible_in_tree() or not panel.visible:
		return
	var rect := highlight.get_global_rect()
	var t := 0.5 + 0.5 * sin(_time * 6.0)
	var grow := 3.0 + 5.0 * t
	_pulse.draw_rect(rect.grow(grow), Color(GOLD, 0.35 + 0.5 * t), false, 3.0)
	_pulse.draw_rect(rect.grow(grow + 4.0), Color(GOLD, 0.15 * t), false, 2.0)


func _build() -> void:
	var anchor := Control.new()
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	anchor.offset_top = -330
	anchor.offset_bottom = -175
	anchor.offset_left = -390
	anchor.offset_right = 390
	root.add_child(anchor)
	var holder := VBoxContainer.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.alignment = BoxContainer.ALIGNMENT_END
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor.add_child(holder)

	panel = PanelContainer.new()
	panel.name = "Hint"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_style = StyleBoxFlat.new()
	_style.bg_color = Color(0.06, 0.05, 0.07, 0.88)
	_style.border_color = GOLD
	_style.set_border_width_all(3)
	_style.set_corner_radius_all(10)
	_style.content_margin_left = 22
	_style.content_margin_right = 26
	_style.content_margin_top = 14
	_style.content_margin_bottom = 16
	_style.shadow_color = Color(0, 0, 0, 0.4)
	_style.shadow_size = 8
	panel.add_theme_stylebox_override("panel", _style)
	holder.add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	panel.add_child(row)
	keys_box = HBoxContainer.new()
	keys_box.add_theme_constant_override("separation", 6)
	keys_box.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(keys_box)
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", 4)
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(words)
	title_label = Label.new()
	title_label.add_theme_font_override("font", _serif())
	title_label.add_theme_font_size_override("font_size", 30)
	title_label.add_theme_color_override("font_color", GOLD)
	words.add_child(title_label)
	text_label = Label.new()
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.custom_minimum_size = Vector2(540, 0)
	text_label.add_theme_font_size_override("font_size", 22)
	text_label.add_theme_color_override("font_color", PARCHMENT)
	words.add_child(text_label)


func _keycap(text: String) -> PanelContainer:
	var cap := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.93, 0.89, 0.8)
	style.border_color = Color(0.55, 0.48, 0.36)
	style.border_width_bottom = 5
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.set_corner_radius_all(7)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 4
	style.content_margin_bottom = 6
	cap.add_theme_stylebox_override("panel", style)
	cap.custom_minimum_size = Vector2(52, 52)
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 26 if text.length() <= 2 else 20)
	label.add_theme_color_override("font_color", Color(0.12, 0.1, 0.08))
	cap.add_child(label)
	return cap


static var _serif_font: SystemFont



static func _serif() -> Font:
	if _serif_font == null:
		_serif_font = SystemFont.new()
		_serif_font.font_names = PackedStringArray(["Palatino", "Georgia", "Book Antiqua", "Times New Roman", "serif"])
		_serif_font.font_weight = 600
	return _serif_font
