extends SceneTree
## Fuzz test for the village factory: plans many seeds per recipe on flat ground
## and checks every plan is valid, has its anchors, and is repeatable.
## Run: godot --headless --path . --script res://tests/procgen_test.gd

const RECIPES := [
	"res://systems/procgen/village/recipes/millbrook.tres",
	"res://systems/procgen/village/recipes/hallows_rest.tres",
	"res://systems/procgen/village/recipes/vell_road_waystation.tres",
]
const SEEDS := 200


func _initialize() -> void:
	var ground := FlatGround.new()
	var failures := 0
	for path in RECIPES:
		var recipe: VillageRecipe = load(path)
		var invalid := 0
		var retried := 0
		var total_buildings := 0
		var start := Time.get_ticks_usec()
		for seed_value in SEEDS:
			var plan := VillagePlanner.plan(recipe, seed_value, Vector2.ZERO, ground)
			total_buildings += plan.buildings.size()
			if plan.attempts > 1:
				retried += 1
			if not plan.is_valid():
				invalid += 1
				if invalid <= 3:
					printerr("  %s seed %d: %s" % [recipe.display_name, seed_value, ", ".join(plan.problems)])
		var ms := (Time.get_ticks_usec() - start) / 1000.0
		print("%-22s %d/%d valid, %d needed a retry, %.1f buildings avg, %.1f ms per village" % [
			recipe.display_name, SEEDS - invalid, SEEDS, retried, float(total_buildings) / SEEDS, ms / SEEDS])
		if invalid > 0:
			failures += 1

		# Same seed, same village. Story state changes details, not the layout.
		var a := VillagePlanner.plan(recipe, 42, Vector2.ZERO, ground)
		var b := VillagePlanner.plan(recipe, 42, Vector2.ZERO, ground)
		var burned := VillagePlanner.plan(recipe, 42, Vector2.ZERO, ground, Vector2.ZERO, {"damage": 0.8, "bleed": 0.0})
		if a.fingerprint() != b.fingerprint():
			printerr("  %s: seed 42 gave two different villages" % recipe.display_name)
			failures += 1
		if burned.buildings.size() != a.buildings.size() or burned.buildings[0].position != a.buildings[0].position:
			printerr("  %s: story state changed the layout" % recipe.display_name)
			failures += 1

	print("PROCGEN TEST PASSED" if failures == 0 else "PROCGEN TEST FAILED")
	quit(1 if failures else 0)
