class_name UiSession
extends RefCounted
## Hands the created character from the menus to the game scene without an
## autoload (project.godot belongs to the foundation agent). Read
## UiSession.character in the player or world scene to apply the look.

## Keys: name, sex, face, skin, hair, hair_color, eyes, build (see UiCharacterPresets).
static var character: Dictionary = {}


static func has_character() -> bool:
	return not character.is_empty()
