extends SceneTree
## Renders a contact sheet of creation looks, each in its own live portrait, to
## review every option side by side.
##   xvfb-run godot --rendering-driver opengl3 --path . --script res://actors/characters/preview/look_sheet.gd -- out.png faces|hair|skins|builds|eyes

var frames := 0
var out := ""


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0]
	var sheet: String = args[1] if args.size() > 1 else "faces"
	var looks: Array = []
	var zoom := 1.0
	var cols := 4
	match sheet:
		"faces":
			for sex in 2:
				for face in 4:
					looks.append({"sex": sex, "face": face, "skin": [1, 3, 0, 4][face], "hair": [1, 0, 2, 3][face] if sex == 1 else [1, 0, 4, 5][face], "hair_color": [1, 0, 2, 3][face], "eyes": face, "build": 1})
		"hair":
			cols = 6
			zoom = 0.82
			for sex in 2:
				for hair in 6:
					looks.append({"sex": sex, "face": hair % 4, "skin": (hair + sex) % 6, "hair": hair, "hair_color": (hair * 5 + sex) % 6, "eyes": hair, "build": 1})
		"skins":
			cols = 6
			zoom = 0.9
			for sex in 2:
				for skin in 6:
					looks.append({"sex": sex, "face": (skin + sex) % 4, "skin": skin, "hair": [1, 2][sex], "hair_color": skin, "eyes": (skin + 2) % 6, "build": 1})
		"builds":
			cols = 6
			zoom = 0.0
			for sex in 2:
				for build in 3:
					looks.append({"sex": sex, "face": build, "skin": build + 1, "hair": [1, 3][sex], "hair_color": 1, "eyes": 2, "build": build})
		"eyes":
			cols = 6
			for sex in 2:
				for eyes in 6:
					looks.append({"sex": sex, "face": 0, "skin": 1, "hair": [0, 2][sex], "hair_color": 1, "eyes": eyes, "build": 1})
	var rows := ceili(looks.size() / float(cols))
	var cell := Vector2i(260, 400) if zoom < 0.5 else Vector2i(260, 300)
	root.size = Vector2i(cell.x * cols, cell.y * rows)
	var grid := GridContainer.new()
	grid.columns = cols
	grid.add_theme_constant_override("h_separation", 0)
	grid.add_theme_constant_override("v_separation", 0)
	root.add_child(grid)
	for look in looks:
		var p := CharacterPortrait3D.new()
		p.custom_minimum_size = cell
		grid.add_child(p)
		p.character = look
		p.sway = false
		p.set_zoom(zoom, -0.3)


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 40:
		root.get_texture().get_image().save_png(out)
		print("saved ", out)
		return true
	return false
