class_name DialogueData
extends Resource
## A conversation tree. Talking to an NPC plays the highest-priority dialogue
## for that NPC whose conditions pass (see QuestManager.talk_to).

@export var id: StringName
## NPC this conversation belongs to. Empty for scripted scenes (dreams, cutscenes).
@export var npc: StringName
## Default speaker for lines that don't name one. Defaults to [member npc].
@export var speaker: StringName
@export var priority := 0
@export var conditions: Array[Dictionary] = []
## Plays at most once per playthrough.
@export var once := false
@export var start: StringName = &"start"
## line id -> DialogueLine
@export var lines: Dictionary = {}


func get_line(line_id: StringName) -> DialogueLine:
	return lines.get(line_id)


func default_speaker() -> StringName:
	return speaker if speaker != &"" else npc
