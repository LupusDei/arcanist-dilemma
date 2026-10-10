extends SceneTree
## Writes the rest skeleton of every body, build and age as JSON for the sculptor (tools/gen_bodies.py).
##   godot --headless --path . --script res://actors/characters/tools/dump_skeletons.gd -- out.json


func _init() -> void:
	var out := {}
	for body in CharacterStyle.BODIES:
		for build in CharacterStyle.ids(CharacterStyle.BUILDS):
			for age in [1, 0]:
				var spec := CharacterSpec.new()
				spec.body = body
				spec.build = build
				spec.age = age
				var rig := CharacterBuilder.build(spec)
				var joints := {}
				for entry in CharacterBuilder.JOINTS:
					var j: Node3D = rig.joints[entry[0]]
					var g: Transform3D = j.transform
					var n := j.get_parent() as Node3D
					while n != rig.body_root:
						g = n.transform * g
						n = n.get_parent() as Node3D
					var b := g.basis.orthonormalized()
					joints[entry[0]] = {
						"parent": entry[1],
						"origin": [g.origin.x, g.origin.y, g.origin.z],
						"basis": [b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z],
					}
				var dims := {}
				for k in rig.dims:
					dims[k] = rig.dims[k]
				out["%s_%s_%s" % [body, build, "child" if age <= 0 else "adult"]] = {"joints": joints, "dims": dims}
				rig.free()
	var f := FileAccess.open(OS.get_cmdline_user_args()[0], FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "  "))
	f.close()
	print("wrote ", out.size(), " skeletons")
	quit(0)
