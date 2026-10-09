class_name DialogueLine
extends Resource
## One node in a dialogue tree: a speaker's line and what follows it.
##
## A line with no text only routes: its effects run and the first passing
## branch (or [member next]) is taken at once. A line with choices waits for
## one; otherwise it continues to [member next], and an empty next ends the talk.

@export var id: StringName
## Speaker id from speakers.json, or "player". Empty keeps the dialogue's default speaker.
@export var speaker: StringName
@export_multiline var text := ""
@export var effects: Array[Dictionary] = []
@export var choices: Array[DialogueChoice] = []
@export var next: StringName
## [{"conditions": [...], "next": "line_id"}], checked in order before [member next].
@export var branches: Array[Dictionary] = []
