extends Node3D
## Village lab: generate villages from each recipe and reroll them by seed.
##   N / B        next / previous seed
##   1, 2, 3      switch recipe
##   W            toggle war damage (same layout, story state changed)
##   Right drag   orbit      Wheel  zoom

const RECIPES := [
	"res://systems/procgen/village/recipes/millbrook.tres",
	"res://systems/procgen/village/recipes/hallows_rest.tres",
	"res://systems/procgen/village/recipes/vell_road_waystation.tres",
]

@export var seed_value := 1
@export var recipe_index := 0
@export var war_damage := false

var _ground := FlatGround.new()
var _village: Node3D
var _roads: Node3D
var _zoom := 70.0

@onready var _pivot: Node3D = $CameraPivot
@onready var _camera: Camera3D = $CameraPivot/Camera3D
@onready var _label: Label = %InfoLabel


func _ready() -> void:
	generate()


func generate() -> void:
	if _village != null:
		_village.queue_free()
		_roads.queue_free()
	var recipe: VillageRecipe = load(RECIPES[recipe_index])
	var state := {"damage": 0.75} if war_damage else {}
	var start := Time.get_ticks_usec()
	var plan := VillagePlanner.plan(recipe, seed_value, Vector2.ZERO, _ground, Vector2(0, 1), state)
	var planned := Time.get_ticks_usec()
	_village = VillageBuilder.build(plan)
	add_child(_village)
	_roads = VillageBuilder.build_roads(plan, _ground)
	add_child(_roads)
	var built := Time.get_ticks_usec()
	_label.text = "%s   seed %d%s\n%s\nplanned in %.1f ms (%d attempt%s), built in %.1f ms   %s\nN/B seed   1-3 recipe   W war damage   right-drag orbit   wheel zoom" % [
		recipe.display_name, seed_value, "   [war-torn]" if war_damage else "",
		plan.summary(),
		(planned - start) / 1000.0, plan.attempts, "" if plan.attempts == 1 else "s", (built - planned) / 1000.0,
		"valid" if plan.is_valid() else "INVALID: " + ", ".join(plan.problems),
	]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_N:
				seed_value += 1
			KEY_B:
				seed_value = maxi(seed_value - 1, 0)
			KEY_1, KEY_2, KEY_3:
				recipe_index = event.physical_keycode - KEY_1
			KEY_W:
				war_damage = not war_damage
			_:
				return
		generate()
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
		_pivot.rotation.y -= event.relative.x * 0.005
		_pivot.rotation.x = clampf(_pivot.rotation.x - event.relative.y * 0.005, -1.4, -0.15)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = maxf(_zoom * 0.9, 10.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = minf(_zoom * 1.1, 160.0)


func _process(delta: float) -> void:
	_camera.position.z = lerpf(_camera.position.z, _zoom, 1.0 - exp(-8.0 * delta))
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_pivot.rotation.y += delta * 0.05
