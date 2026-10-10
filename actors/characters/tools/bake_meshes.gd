extends SceneTree
## Bakes the sculptor's .acm files into the .res meshes CharacterMeshes loads.
##   godot --headless --path . --script res://actors/characters/tools/bake_meshes.gd -- <acm dir>
## Files keep their relative path: <acm dir>/heads/boy_round_adult.acm -> meshes/heads/boy_round_adult.res.


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("usage: -- <acm dir>")
		quit(1)
		return
	var src: String = args[0]
	var count := 0
	for rel in _walk(src, ""):
		var mesh := CharacterMeshes.from_acm(src.path_join(rel))
		if mesh == null:
			quit(1)
			return
		var out := CharacterMeshes.DIR + rel.get_basename() + ".res"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out.get_base_dir()))
		var err := ResourceSaver.save(mesh, out, ResourceSaver.FLAG_COMPRESS)
		if err != OK:
			push_error("can't save %s: %s" % [out, err])
			quit(1)
			return
		count += 1
	print("baked %d meshes" % count)
	quit(0)


func _walk(root: String, rel: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(root.path_join(rel))
	for d in dir.get_directories():
		out.append_array(_walk(root, rel.path_join(d) if rel != "" else d))
	for f in dir.get_files():
		if f.ends_with(".acm"):
			out.append(rel.path_join(f) if rel != "" else f)
	return out
