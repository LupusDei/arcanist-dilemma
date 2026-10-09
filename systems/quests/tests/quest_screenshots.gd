extends SceneTree
## Captures screenshots of the quest sandbox for the docs: the tracker, the old
## man's first line, and a choice with alignment hints.
## Run: xvfb-run godot --path . --rendering-driver opengl3 --script res://systems/quests/tests/quest_screenshots.gd

const OUT := "res://systems/quests/docs/"

var _sandbox: Node


func _initialize() -> void:
	_sandbox = load("res://systems/quests/sandbox/quest_sandbox.tscn").instantiate()
	root.add_child(_sandbox)
	_run.call_deferred()


func _run() -> void:
	await _frames(20)
	var quests: QuestManager = _sandbox.quests
	var ui: QuestUI = _sandbox.ui
	ui.dialogue_box.chars_per_second = 0.0
	_sandbox.player.global_position = Vector3(-2, 1, 5)
	await _frames(30)
	await _shot("tracker.png")

	quests.goto_stage(&"prologue", &"bully")
	quests.talk_to(&"rook")
	quests.active_dialogue.advance()
	quests.active_dialogue.advance()
	await _frames(10)
	await _shot("dialogue_choices.png")
	quests.active_dialogue.stop()

	quests.goto_stage(&"prologue", &"stranger")
	_sandbox.player.global_position = Vector3(10.5, 1, 20)
	quests.notify_reached(&"tavern")
	quests.talk_to(&"old_man")
	quests.active_dialogue.advance()
	await _frames(10)
	await _shot("old_man.png")
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(OUT + file))
	print("saved ", file)
