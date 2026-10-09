class_name QuestProgress
extends RefCounted
## Runtime state of one quest the player has started.

const ACTIVE := &"active"
const COMPLETED := &"completed"
const FAILED := &"failed"
## Quest states a condition can ask about. "done" means completed or failed.
const STATES_FOR_CONDITIONS: Array[StringName] = [&"not_started", &"active", &"completed", &"failed", &"done", &"started"]

var quest_id: StringName
var state: StringName = ACTIVE
var stage: StringName
## objective id -> count reached in the current stage
var counts: Dictionary = {}
## objective id -> true once done in the current stage
var done: Dictionary = {}
## Stages finished so far, in order.
var stage_history: Array[StringName] = []


func is_active() -> bool:
	return state == ACTIVE


func get_count(objective_id: StringName) -> int:
	return counts.get(objective_id, 0)


func is_objective_done(objective_id: StringName) -> bool:
	return done.get(objective_id, false)


func enter_stage(stage_id: StringName) -> void:
	stage = stage_id
	counts.clear()
	done.clear()


func to_dict() -> Dictionary:
	var count_data := {}
	for id in counts:
		count_data[String(id)] = counts[id]
	var done_ids: Array[String] = []
	for id in done:
		if done[id]:
			done_ids.append(String(id))
	var history: Array[String] = []
	for id in stage_history:
		history.append(String(id))
	return {"state": String(state), "stage": String(stage), "counts": count_data, "done": done_ids, "history": history}


static func from_dict(id: StringName, data: Dictionary) -> QuestProgress:
	var p := QuestProgress.new()
	p.quest_id = id
	p.state = StringName(data.get("state", "active"))
	p.stage = StringName(data.get("stage", ""))
	var count_data: Dictionary = data.get("counts", {})
	for key in count_data:
		p.counts[StringName(key)] = int(count_data[key])
	for key in data.get("done", []):
		p.done[StringName(key)] = true
	for key in data.get("history", []):
		p.stage_history.append(StringName(key))
	return p
