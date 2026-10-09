class_name QuestTracker
extends Control
## WoW-style quest list in the top-right corner: each active quest's title and
## its current objectives with counts. Done objectives turn green with a tick.

const KIND_MARKS := {&"main": "◆ ", &"key": "★ ", &"side": ""}
const MAX_QUESTS := 5

var manager: QuestManager

var _list: VBoxContainer
var _refresh_queued := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = QuestUiStyle.get_theme()
	_list = VBoxContainer.new()
	_list.name = "List"
	_list.anchor_left = 1.0
	_list.anchor_right = 1.0
	_list.offset_left = -360
	_list.offset_right = -24
	_list.offset_top = 24
	_list.add_theme_constant_override("separation", 14)
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_list)


func bind(p_manager: QuestManager) -> void:
	if manager:
		manager.quest_updated.disconnect(_on_quest_changed)
		manager.state_loaded.disconnect(refresh)
	manager = p_manager
	manager.quest_updated.connect(_on_quest_changed)
	manager.state_loaded.connect(refresh)
	refresh()


func refresh() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	if manager == null:
		return
	var shown := 0
	for quest in manager.get_active_quests():
		if shown >= MAX_QUESTS:
			break
		_list.add_child(_make_entry(manager.get_tracker_entry(quest.id)))
		shown += 1


## The lines currently shown, for tests: ["◆ Tricks", "  Nudge the spoon... ", ...]
func get_lines() -> Array[String]:
	var lines: Array[String] = []
	for entry in _list.get_children():
		for label in entry.get_children():
			if label is Label:
				lines.append(label.text)
	return lines


func _make_entry(entry: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title := Label.new()
	title.text = KIND_MARKS.get(entry["kind"], "") + entry["title"]
	title.add_theme_font_override("font", QuestUiStyle.serif_font())
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", QuestUiStyle.GOLD_BRIGHT)
	box.add_child(title)
	for objective: Dictionary in entry["objectives"]:
		var label := Label.new()
		var text: String = objective["text"]
		if objective["required"] > 1:
			text += " (%d/%d)" % [objective["count"], objective["required"]]
		if objective["optional"]:
			text += " (optional)"
		label.text = ("✓ " if objective["done"] else "• ") + text
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(320, 0)
		label.size_flags_horizontal = Control.SIZE_SHRINK_END
		label.add_theme_font_size_override("font_size", 16)
		var color := QuestUiStyle.PARCHMENT
		if objective["done"]:
			color = QuestUiStyle.GOOD
		elif objective["optional"]:
			color = QuestUiStyle.MUTED
		label.add_theme_color_override("font_color", color)
		box.add_child(label)
	return box


func _on_quest_changed(_id: StringName) -> void:
	# Several updates often land in one frame; redraw once.
	if not _refresh_queued:
		_refresh_queued = true
		_deferred_refresh.call_deferred()


func _deferred_refresh() -> void:
	_refresh_queued = false
	refresh()
