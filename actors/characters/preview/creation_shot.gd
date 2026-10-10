extends SceneTree
## Screenshots the character creation screen with a given look, for review.
##   xvfb-run godot --rendering-driver opengl3 --path . --script res://actors/characters/preview/creation_shot.gd -- out.png sex,face,skin,hair,hair_color,eyes,build [zoom] [yaw]

var frames := 0
var out := ""
var creation: Control


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0]
	root.size = Vector2i(1600, 900)
	creation = load("res://ui/menus/character_creation.gd").new()
	root.add_child(creation)
	var v := args[1].split(",") if args.size() > 1 else PackedStringArray()
	var keys := ["sex", "face", "skin", "hair", "hair_color", "eyes", "build"]
	var c: Dictionary = creation.character.duplicate()
	for i in mini(v.size(), keys.size()):
		c[keys[i]] = int(v[i])
	c["name"] = "Ilsa" if int(c.get("sex", 0)) == 1 else "Bram"
	creation.character = c
	creation.set_character_name(c["name"])
	var zoom := float(args[2]) if args.size() > 2 else 0.25
	var yaw := float(args[3]) if args.size() > 3 else -0.35
	creation.portrait.set_zoom(zoom, yaw)


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 30:
		root.get_texture().get_image().save_png(out)
		print("saved ", out)
		return true
	return false
