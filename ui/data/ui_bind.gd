class_name UiBind
extends RefCounted
## Loose binding between UI screens and the game systems. Screens never import
## the combat or progression classes; they read fields by name and connect to
## whichever signals a source actually has, so the mock and the real systems
## are interchangeable.


## Returns the first of [param keys] present on a Dictionary or Object.
static func read(obj: Variant, keys: Array, default: Variant = null) -> Variant:
	if obj is Dictionary:
		for k in keys:
			if obj.has(k):
				return obj[k]
			if obj.has(StringName(k)):
				return obj[StringName(k)]
	elif obj is Object and is_instance_valid(obj):
		for k in keys:
			var v: Variant = obj.get(k)
			if v != null:
				return v
	return default


## Connects every signal on [param source] that [param target] has a
## "<prefix><signal name>" method for. Returns the connected signal names.
static func connect_all(source: Object, target: Object, prefix: String) -> PackedStringArray:
	var connected: PackedStringArray = []
	if source == null:
		return connected
	for info in source.get_signal_list():
		var method: String = prefix + info.name
		if target.has_method(method):
			var callable := Callable(target, method)
			if not source.is_connected(info.name, callable):
				source.connect(info.name, callable)
			connected.append(info.name)
	return connected


static func disconnect_all(source: Object, target: Object, prefix: String) -> void:
	if source == null or not is_instance_valid(source):
		return
	for info in source.get_signal_list():
		var callable := Callable(target, prefix + info.name)
		if target.has_method(prefix + info.name) and source.is_connected(info.name, callable):
			source.disconnect(info.name, callable)


## Display name of a spell, whether it is a SpellData resource, a mock or a Dictionary.
static func spell_name(spell: Variant) -> String:
	return str(read(spell, ["display_name", "spell_name", "title", "id"], "Spell"))


static func spell_color(spell: Variant) -> Color:
	var c: Variant = read(spell, ["color", "icon_color", "tint"])
	if c is Color:
		return c
	var school := str(read(spell, ["damage_type", "school", "element"], "")).to_lower()
	match school:
		"fire":
			return Color(0.95, 0.4, 0.12)
		"cold":
			return Color(0.45, 0.75, 1.0)
		"lightning":
			return Color(0.7, 0.75, 1.0)
		"force":
			return Color(0.75, 0.62, 0.45)
		"mind":
			return Color(0.85, 0.4, 0.85)
	return Color(0.6, 0.45, 0.95)
