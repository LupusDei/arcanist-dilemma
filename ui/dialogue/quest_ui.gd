class_name QuestUI
extends CanvasLayer
## The story's screens: the dialogue box, the quest tracker and short notices
## ("New quest", "Quest complete", "Your choice leans Lawful").
## Drop res://ui/dialogue/quest_ui.tscn into the game scene once; it finds the
## QuestManager (the "Quests" autoload) through its group.
##
## While a conversation is open the game is paused and the mouse is freed.

## Pause the game while a conversation is open.
@export var pause_during_dialogue := true
## Show "Your choice leans ..." after choices that move alignment.
@export var show_alignment_hints := true
@export var notice_seconds := 3.0

var manager: QuestManager
var dialogue_box: DialogueBox
var tracker: QuestTracker

var _notice: Label
var _notice_tween: Tween
var _mouse_mode_before := Input.MOUSE_MODE_CAPTURED
var _paused_by_us := false


func _init() -> void:
	layer = 11
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	tracker = QuestTracker.new()
	tracker.name = "QuestTracker"
	add_child(tracker)
	dialogue_box = DialogueBox.new()
	dialogue_box.name = "DialogueBox"
	add_child(dialogue_box)
	dialogue_box.closed.connect(_on_dialogue_closed)

	# Notices sit in a full-screen overlay so UiScale can size it with the rest.
	var overlay := Control.new()
	overlay.name = "Overlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	_notice = Label.new()
	_notice.name = "Notice"
	_notice.theme = QuestUiStyle.get_theme()
	_notice.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_notice.offset_top = 110
	_notice.offset_left = -500
	_notice.offset_right = 500
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.add_theme_font_override("font", QuestUiStyle.serif_font())
	_notice.add_theme_font_size_override("font_size", 34)
	_notice.add_theme_constant_override("outline_size", 10)
	_notice.modulate.a = 0.0
	overlay.add_child(_notice)
	UiScale.fit(self)

	var found := QuestManager.find(get_tree())
	if found:
		bind(found)
	else:
		# The manager may be added after us (tests, sandbox).
		_bind_later.call_deferred()


func bind(p_manager: QuestManager) -> void:
	manager = p_manager
	tracker.bind(manager)
	manager.dialogue_started.connect(_on_dialogue_started)
	manager.quest_started.connect(_on_quest_started)
	manager.quest_completed.connect(_on_quest_completed)
	manager.quest_failed.connect(_on_quest_failed)
	manager.alignment_changed.connect(_on_alignment_changed)
	if manager.active_dialogue:
		_on_dialogue_started(manager.active_dialogue)


func show_notice(text: String, color := QuestUiStyle.GOLD_BRIGHT) -> void:
	_notice.text = text
	_notice.add_theme_color_override("font_color", color)
	if _notice_tween:
		_notice_tween.kill()
	_notice_tween = create_tween()
	_notice_tween.tween_property(_notice, "modulate:a", 1.0, 0.25)
	_notice_tween.tween_interval(notice_seconds)
	_notice_tween.tween_property(_notice, "modulate:a", 0.0, 0.6)


func get_notice() -> String:
	return _notice.text


func _bind_later() -> void:
	if manager == null:
		var found := QuestManager.find(get_tree())
		if found:
			bind(found)


func _on_dialogue_started(runner: DialogueRunner) -> void:
	if not dialogue_box.is_open():
		_mouse_mode_before = Input.mouse_mode
	dialogue_box.open(runner)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if pause_during_dialogue and not get_tree().paused:
		get_tree().paused = true
		_paused_by_us = true


func _on_dialogue_closed() -> void:
	# A queued conversation (e.g. a dream after sleeping) opens straight after.
	if manager and manager.is_in_dialogue():
		return
	if _paused_by_us:
		get_tree().paused = false
		_paused_by_us = false
	Input.mouse_mode = _mouse_mode_before


func _on_quest_started(quest_id: StringName) -> void:
	show_notice("New quest: %s" % manager.database.get_quest(quest_id).title)


func _on_quest_completed(quest_id: StringName) -> void:
	show_notice("Quest complete: %s" % manager.database.get_quest(quest_id).title, QuestUiStyle.GOOD)


func _on_quest_failed(quest_id: StringName) -> void:
	show_notice("Quest failed: %s" % manager.database.get_quest(quest_id).title, QuestUiStyle.BAD)


func _on_alignment_changed(_law: float, _good: float, source: String) -> void:
	if not show_alignment_hints or source in ["reset", "load"]:
		return
	var history := manager.story.alignment.history
	if history.is_empty():
		return
	var last: Dictionary = history[-1]
	var hint := Alignment.describe_shift(float(last["law"]), float(last["good"]))
	if not hint.is_empty():
		show_notice("Your choice leans %s" % hint, QuestUiStyle.lean_color(hint))
