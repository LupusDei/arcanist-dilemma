class_name QuestStage
extends Resource
## One step of a quest: a journal line and the objectives that finish it.
##
## When the stage is done its on_complete effects run, then the first branch
## whose conditions pass picks the next stage; otherwise [member next] does.
## An empty next (or "@complete") completes the quest and "@fail" fails it.

const COMPLETE := &"@complete"
const FAIL := &"@fail"

@export var id: StringName
## Journal text for this step.
@export_multiline var description := ""
@export var objectives: Array[QuestObjective] = []
## &"all": every required objective. &"any": the first required objective done
## (for stages that can be finished by talk, stealth or combat).
@export var complete_when: StringName = &"all"
@export var on_enter: Array[Dictionary] = []
@export var on_complete: Array[Dictionary] = []
@export var next: StringName
## [{"conditions": [...], "next": "stage_id"}], checked in order before [member next].
@export var branches: Array[Dictionary] = []


func get_objective(objective_id: StringName) -> QuestObjective:
	for objective in objectives:
		if objective.id == objective_id:
			return objective
	return null


func required_objectives() -> Array[QuestObjective]:
	var result: Array[QuestObjective] = []
	for objective in objectives:
		if not objective.optional:
			result.append(objective)
	return result
