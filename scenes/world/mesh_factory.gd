class_name MeshFactory
## Builds the low-poly placeholder meshes that dress the world: trees, rocks,
## grass and flowers. Everything is driven by a RandomNumberGenerator so the
## variants are the same on every run.


static func broadleaf_tree(rng: RandomNumberGenerator, trunk_material: Material, leaf_material: Material) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var trunk_height := rng.randf_range(2.4, 3.4)

	var trunk := SurfaceTool.new()
	trunk.append_from(_cylinder(0.16, 0.3, trunk_height, 7), 0, Transform3D(Basis.IDENTITY, Vector3(0, trunk_height * 0.5, 0)))
	trunk.commit(mesh)
	mesh.surface_set_material(0, trunk_material)

	var leaves := SurfaceTool.new()
	var crown := Vector3(0, trunk_height + 0.7, 0)
	leaves.append_from(_lumpy_sphere(1.7, rng.randi()), 0, Transform3D(Basis.IDENTITY, crown + Vector3(0, 0.5, 0)))
	for blob in rng.randi_range(3, 5):
		var offset := Vector3(rng.randf_range(-1.2, 1.2), rng.randf_range(-0.4, 1.3), rng.randf_range(-1.2, 1.2))
		leaves.append_from(_lumpy_sphere(rng.randf_range(0.95, 1.45), rng.randi()), 0, Transform3D(Basis.IDENTITY, crown + offset))
	leaves.commit(mesh)
	mesh.surface_set_material(1, leaf_material)
	return mesh


static func pine_tree(rng: RandomNumberGenerator, trunk_material: Material, leaf_material: Material) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var trunk_height := rng.randf_range(1.8, 2.4)

	var trunk := SurfaceTool.new()
	trunk.append_from(_cylinder(0.1, 0.22, trunk_height, 6), 0, Transform3D(Basis.IDENTITY, Vector3(0, trunk_height * 0.5, 0)))
	trunk.commit(mesh)
	mesh.surface_set_material(0, trunk_material)

	var leaves := SurfaceTool.new()
	var y := trunk_height * 0.6
	var radius := rng.randf_range(1.7, 2.1)
	for tier in rng.randi_range(3, 4):
		var height := radius * 1.25
		leaves.append_from(_cylinder(0.0, radius, height, 8), 0, Transform3D(Basis.IDENTITY, Vector3(0, y + height * 0.5, 0)))
		y += height * 0.55
		radius *= 0.74
	leaves.commit(mesh)
	mesh.surface_set_material(1, leaf_material)
	return mesh


## Faceted boulder with a flattened base. Unit-ish size; scale per instance.
static func rock(rng: RandomNumberGenerator, material: Material) -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radial_segments = 9
	sphere.rings = 6
	var arrays := sphere.get_mesh_arrays()
	var source: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]

	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 1.2
	var stretch := Vector3(rng.randf_range(0.9, 1.3), rng.randf_range(0.55, 0.8), rng.randf_range(0.8, 1.1))

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0xFFFFFFFF)  # flat shading
	for index in indices:
		var direction := source[index].normalized()
		var vertex := direction * (1.0 + noise.get_noise_3dv(direction * 2.0) * 0.35) * stretch
		vertex.y = maxf(vertex.y, -0.3)
		st.add_vertex(vertex)
	st.generate_normals()
	var mesh := st.commit()
	mesh.surface_set_material(0, material)
	return mesh


## A tuft of upright blades. UV.y runs 0 at the root to 1 at the tip for the shader.
static func grass_tuft(rng: RandomNumberGenerator, material: Material) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	for blade in 7:
		var angle := rng.randf() * TAU
		var root := Vector3(rng.randf_range(-0.18, 0.18), 0.0, rng.randf_range(-0.18, 0.18))
		var side := Vector3(cos(angle), 0.0, sin(angle)) * rng.randf_range(0.035, 0.06)
		var tip := root + Vector3(rng.randf_range(-0.12, 0.12), rng.randf_range(0.3, 0.6), rng.randf_range(-0.12, 0.12))
		vertices.append(root - side)
		vertices.append(root + side)
		vertices.append(tip)
		uvs.append(Vector2(0, 0))
		uvs.append(Vector2(1, 0))
		uvs.append(Vector2(0.5, 1))
		for i in 3:
			normals.append(Vector3.UP)
	return _mesh_from(vertices, normals, uvs, material)


## A thin stem with a star-shaped head. UV.y is 1 on the head so the shader can tint it.
static func flower(material: Material) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var head_height := 0.32
	var stem := Vector3(0.015, 0, 0)
	for v in [-stem, stem, Vector3(0, head_height, 0)]:
		vertices.append(v)
		uvs.append(Vector2(0, 0))
		normals.append(Vector3.UP)
	for angle in [0.0, PI / 4.0]:
		var basis := Basis(Vector3.UP, angle)
		var corners := [Vector3(-0.08, 0, -0.08), Vector3(0.08, 0, -0.08), Vector3(0.08, 0, 0.08), Vector3(-0.08, 0, 0.08)]
		for tri in [[0, 1, 2], [0, 2, 3]]:
			for c in tri:
				vertices.append(basis * corners[c] + Vector3(0, head_height, 0))
				uvs.append(Vector2(0, 1))
				normals.append(Vector3.UP)
	return _mesh_from(vertices, normals, uvs, material)


static func _mesh_from(vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, material: Material) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	return mesh


static func _cylinder(top_radius: float, bottom_radius: float, height: float, segments: int) -> CylinderMesh:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = top_radius
	cylinder.bottom_radius = bottom_radius
	cylinder.height = height
	cylinder.radial_segments = segments
	cylinder.rings = 1
	return cylinder


## Sphere pushed in and out by noise so canopies read as soft, lumpy foliage.
static func _lumpy_sphere(radius: float, seed_value: int) -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radial_segments = 12
	sphere.rings = 7
	var arrays := sphere.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 1.4
	for i in vertices.size():
		var direction := vertices[i].normalized()
		vertices[i] = direction * radius * (1.0 + noise.get_noise_3dv(direction) * 0.3) * Vector3(1.0, 0.85, 1.0)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var st := SurfaceTool.new()
	st.create_from_arrays(arrays)
	st.generate_normals()
	return st.commit()
