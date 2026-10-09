class_name StoryConditions
extends RefCounted
## Evaluates the condition dictionaries used by quests and dialogue.
## A list passes when every entry passes. Each entry is one of:
##
##   {"flag": "hat_hidden"}                         flag is truthy
##   {"flag": "wolves_killed", "min": 3}            numeric compare (also "max", "equals")
##   {"not_flag": "told_wardens"}                   flag is missing or falsy
##   {"quest": "prologue", "state": "completed"}    not_started, started, active, completed, failed, done
##   {"quest": "prologue", "stage": "tavern"}       quest is active at that stage
##   {"alignment": "law", "min": 25}                axis is law or good; "max" too
##   {"lean": "chaotic"}                            lawful, chaotic, good, evil or neutral (either axis)
##   {"standing": "wardens", "min": 10}             faction standing
##   {"level_min": 3}                               player level from Progression
##   {"any": [ ... ]}                               at least one passes
##   {"not": [ ... ]}                               the list as a whole fails


static func check_all(conditions: Array, manager: QuestManager) -> bool:
	for condition in conditions:
		if not check(condition, manager):
			return false
	return true


static func check(c: Dictionary, manager: QuestManager) -> bool:
	var story := manager.story
	if c.has("flag"):
		var value: Variant = story.get_flag(StringName(c["flag"]))
		if not _compare(value, c, true):
			return false
	if c.has("not_flag") and story.is_set(StringName(c["not_flag"])):
		return false
	if c.has("quest"):
		var id := StringName(c["quest"])
		var state := manager.get_quest_state(id)
		if c.has("state"):
			match StringName(c["state"]):
				&"done":
					if not state in [QuestProgress.COMPLETED, QuestProgress.FAILED]:
						return false
				&"started":
					if state == &"not_started":
						return false
				var wanted:
					if state != wanted:
						return false
		if c.has("stage") and (state != QuestProgress.ACTIVE or manager.get_quest_stage(id) != StringName(c["stage"])):
			return false
	if c.has("alignment"):
		if not _compare(story.alignment.get_axis(StringName(c["alignment"])), c, false):
			return false
	if c.has("lean"):
		var lean := StringName(c["lean"])
		match lean:
			&"lawful", &"chaotic":
				if story.alignment.law_lean() != lean:
					return false
			&"good", &"evil":
				if story.alignment.good_lean() != lean:
					return false
			&"neutral":
				if story.alignment.archetype() != &"true_neutral":
					return false
			_:
				return false
	if c.has("standing"):
		if not _compare(story.get_standing(StringName(c["standing"])), c, false):
			return false
	if c.has("level_min") and manager.get_player_level() < int(c["level_min"]):
		return false
	if c.has("any"):
		var passed := false
		for sub in c["any"]:
			if sub is Dictionary and check(sub, manager):
				passed = true
				break
		if not passed:
			return false
	if c.has("not"):
		var subs: Array = c["not"] if c["not"] is Array else [c["not"]]
		if check_all(subs, manager):
			return false
	return true


## With no comparator, [param truthy_default] decides: flags test truthiness, numbers pass.
static func _compare(value: Variant, c: Dictionary, truthy_default: bool) -> bool:
	var compared := false
	if c.has("equals"):
		compared = true
		var wanted: Variant = c["equals"]
		if typeof(wanted) in [TYPE_INT, TYPE_FLOAT] and typeof(value) in [TYPE_INT, TYPE_FLOAT]:
			if not is_equal_approx(float(value), float(wanted)):
				return false
		elif str(value) != str(wanted) or value == null:
			return false
	if c.has("min"):
		compared = true
		if not typeof(value) in [TYPE_INT, TYPE_FLOAT, TYPE_NIL] or float(value if value != null else 0) < float(c["min"]):
			return false
	if c.has("max"):
		compared = true
		if not typeof(value) in [TYPE_INT, TYPE_FLOAT, TYPE_NIL] or float(value if value != null else 0) > float(c["max"]):
			return false
	if not compared and truthy_default:
		return StoryState.is_truthy(value)
	return true
