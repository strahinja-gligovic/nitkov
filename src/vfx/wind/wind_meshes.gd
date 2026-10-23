class_name WindMeshes
extends RefCounted
## Procedural meshes for the wind effects: bundles of streak lines, flat
## rings, lathed spear and vortex shapes and sprays of flying streaks. The
## callers cache what they build; nothing here is per frame.


## Streak lines through each path's points (local space), for
## wind_line.gdshader: NORMAL is the line's direction, UV.x runs head (0) to
## tail (1), UV2 = (width, dash coordinate). `widths[i]` is line i's width at
## its head (it tapers to 40% at the tail); `dash_length` is metres per dash
## and each line's dashes start at a random phase.
static func lines(paths: Array[PackedVector3Array], widths: PackedFloat32Array, dash_length := 0.5) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for line in paths.size():
		var path := paths[line]
		var count := path.size()
		if count < 2:
			continue
		var phase := randf()
		var travelled := 0.0
		var first := vertices.size()
		for i in count:
			if i > 0:
				travelled += path[i].distance_to(path[i - 1])
			var direction := path[mini(i + 1, count - 1)] - path[maxi(i - 1, 0)]
			var along := float(i) / float(count - 1)
			var w := widths[line] * lerpf(1.0, 0.4, along)
			for side in 2:
				vertices.append(path[i])
				normals.append(direction.normalized())
				uvs.append(Vector2(along, float(side)))
				uv2s.append(Vector2(w, travelled / dash_length + phase))
				colors.append(Color.WHITE)
			if i > 0:
				var a := first + (i - 1) * 2
				indices.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2])
	return _build(vertices, normals, uvs, uv2s, colors, indices)


## A flat ring in the XZ plane, `inner` to 1.0 in radius: UV.x runs around
## (0..1), UV.y from the inner (0) to the outer edge (1).
static func annulus(inner: float, segments := 48) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for i in segments + 1:
		var u := float(i) / segments
		var direction := Vector3(sin(u * TAU), 0.0, cos(u * TAU))
		vertices.append_array([direction * inner, direction])
		normals.append_array([Vector3.UP, Vector3.UP])
		uvs.append_array([Vector2(u, 0.0), Vector2(u, 1.0)])
		if i > 0:
			var a := (i - 1) * 2
			indices.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2])
	return _build(vertices, normals, uvs, PackedVector2Array(), PackedColorArray(), indices)


## A surface of revolution around the Z axis through `profile` points
## (x = z position, y = radius): UV.x runs around, UV.y along the profile.
static func lathe(profile: PackedVector2Array, segments := 16) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var rows := profile.size()
	for j in rows:
		var slope := profile[mini(j + 1, rows - 1)] - profile[maxi(j - 1, 0)]
		for i in segments + 1:
			var u := float(i) / segments
			var radial := Vector3(cos(u * TAU), sin(u * TAU), 0.0)
			vertices.append(radial * profile[j].y + Vector3(0.0, 0.0, profile[j].x))
			# the outward normal leans back against the profile's slope
			normals.append((radial * slope.x - Vector3(0.0, 0.0, slope.y)).normalized())
			uvs.append(Vector2(u, float(j) / float(rows - 1)))
			if j > 0 and i > 0:
				var a := (j - 1) * (segments + 1) + i - 1
				var b := a + segments + 1
				indices.append_array([a, b, a + 1, a + 1, b, b + 1])
	return _build(vertices, normals, uvs, PackedVector2Array(), PackedColorArray(), indices)


## Streaks that fly out from where they start, for wind_spray.gdshader. Each
## entry of `streaks` is [start: Vector3, direction: Vector3, travel: float,
## length scale 0..1, width scale 0..1, delay 0..1].
static func spray(streaks: Array) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for streak: Array in streaks:
		var start: Vector3 = streak[0]
		var direction: Vector3 = (streak[1] as Vector3).normalized()
		var first := vertices.size()
		var random := randf()
		for along in 2:
			for side in 2:
				vertices.append(start)
				normals.append(direction)
				uvs.append(Vector2(float(along), float(side)))
				uv2s.append(Vector2(streak[2], random))
				colors.append(Color(streak[3], streak[4], streak[5], 1.0))
		indices.append_array([first, first + 1, first + 2, first + 1, first + 3, first + 2])
	var mesh := _build(vertices, normals, uvs, uv2s, colors, indices)
	mesh.custom_aabb = AABB(Vector3.ONE * -9.0, Vector3.ONE * 18.0)
	return mesh


## `count` directions spread evenly over a sphere (a Fibonacci spiral), with
## a little jitter.
static func sphere_directions(count: int, jitter := 0.15) -> Array[Vector3]:
	var directions: Array[Vector3] = []
	var golden := PI * (3.0 - sqrt(5.0))
	for i in count:
		var y := 1.0 - (float(i) + 0.5) / count * 2.0
		var r := sqrt(maxf(1.0 - y * y, 0.0))
		var theta := golden * i
		var direction := Vector3(cos(theta) * r, y, sin(theta) * r)
		direction += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * jitter
		directions.append(direction.normalized())
	return directions


static func _build(vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array,
		uv2s: PackedVector2Array, colors: PackedColorArray, indices: PackedInt32Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	if not uv2s.is_empty():
		arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	if not colors.is_empty():
		arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
