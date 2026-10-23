class_name HeadBuilder
extends RefCounted
## The outfits come without heads (hooded or open-collared, but empty), so a
## head is cut out of the matching base body: every triangle whose vertices
## all weigh at least half on Head + neck_01, plus the Eyes and Eyebrows
## meshes, packed into one skinned mesh. It keeps the base body's own Skin;
## the head and neck rests match the outfits', so it lands exactly in place.
## Open collars also take a "collar fill": the base body's upper chest near
## the neck, pushed slightly inward, so a deep duck never shows a hollow.
## Built once per body and kept.

const KEEP_BONES: Array[String] = ["Head", "neck_01"]
const MIN_WEIGHT := 0.5

static var _cache := {}  # key -> [ArrayMesh, Skin]


## [mesh, skin] for a head cut from `body_scene` (whose body mesh node is
## `body_node`). `fill` describes the collar fill, or {} for none:
## {bones: Array[String], min_y: float, radius: float, inset: float}.
static func build(body_scene: PackedScene, body_node: String, fill := {}) -> Array:
	var key := "%s|%s|%s" % [body_scene.resource_path, body_node, fill]
	if _cache.has(key):
		return _cache[key]
	var scene := body_scene.instantiate()
	var body := scene.find_child(body_node, true, false) as MeshInstance3D
	var mesh := ArrayMesh.new()
	var skin: Skin = null
	if body:
		skin = body.skin.duplicate() as Skin
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _trim(body.mesh, body.skin, fill))
		mesh.surface_set_material(0, body.mesh.surface_get_material(0))
		for extra in ["Eyes", "Eyebrows"]:
			var part := scene.find_child(extra, true, false) as MeshInstance3D
			if part == null:
				continue
			for surface in part.mesh.get_surface_count():
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _plain(part.mesh.surface_get_arrays(surface)))
				mesh.surface_set_material(mesh.get_surface_count() - 1, part.mesh.surface_get_material(surface))
	else:
		push_warning("HeadBuilder: no %s in %s" % [body_node, body_scene.resource_path])
	scene.free()
	_cache[key] = [mesh, skin]
	return _cache[key]


## The head surface's arrays: kept triangles only, vertices compacted.
static func _trim(source: Mesh, skin: Skin, fill: Dictionary) -> Array:
	var arrays := source.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var per_vertex := bones.size() / vertices.size()
	var core := _binds(skin, KEEP_BONES)
	var fill_bones: Array[String] = KEEP_BONES.duplicate()
	for bone_name: String in fill.get("bones", []):
		fill_bones.append(bone_name)
	var filling := _binds(skin, fill_bones)
	var neck := Vector2.ZERO
	for bind in skin.get_bind_count():
		if skin.get_bind_name(bind) == &"neck_01":
			var at := skin.get_bind_pose(bind).affine_inverse().origin
			neck = Vector2(at.x, at.z)
	var head_weight := PackedFloat32Array()
	head_weight.resize(vertices.size())
	var kind := PackedByteArray()  # 0 drop, 1 head, 2 collar fill
	kind.resize(vertices.size())
	for v in vertices.size():
		var on_head := 0.0
		var on_fill := 0.0
		for k in per_vertex:
			var bone := bones[v * per_vertex + k]
			if core.has(bone):
				on_head += weights[v * per_vertex + k]
			if filling.has(bone):
				on_fill += weights[v * per_vertex + k]
		head_weight[v] = on_head
		if on_head >= MIN_WEIGHT:
			kind[v] = 1
		elif not fill.is_empty() and on_fill >= MIN_WEIGHT and vertices[v].y >= float(fill["min_y"]) \
				and Vector2(vertices[v].x, vertices[v].z).distance_to(neck) <= float(fill["radius"]):
			kind[v] = 2
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var remap := PackedInt32Array()
	remap.resize(vertices.size())
	remap.fill(-1)
	var order := PackedInt32Array()
	var new_index := PackedInt32Array()
	for t in range(0, index.size(), 3):
		if kind[index[t]] == 0 or kind[index[t + 1]] == 0 or kind[index[t + 2]] == 0:
			continue
		for k in 3:
			var v := index[t + k]
			if remap[v] < 0:
				remap[v] = order.size()
				order.append(v)
			new_index.append(remap[v])
	var out := _plain(arrays)
	for slot in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_COLOR,
			Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS]:
		if out[slot] != null:
			out[slot] = _pick(out[slot], order, vertices.size())
	var kept: PackedVector3Array = out[Mesh.ARRAY_VERTEX]
	for i in order.size():
		var v := order[i]
		if kind[v] == 2:
			# tuck the fill inward, fading to nothing where it meets the neck
			var fade := clampf(1.0 - head_weight[v] / MIN_WEIGHT, 0.0, 1.0)
			kept[i] = vertices[v] - normals[v] * float(fill.get("inset", 0.0)) * fade
	out[Mesh.ARRAY_VERTEX] = kept
	out[Mesh.ARRAY_INDEX] = new_index
	return out


static func _binds(skin: Skin, names: Array[String]) -> Dictionary:
	var out := {}
	for bind in skin.get_bind_count():
		if String(skin.get_bind_name(bind)) in names:
			out[bind] = true
	return out


## A surface's arrays without the extra CUSTOM channels nothing here uses.
static func _plain(source: Array) -> Array:
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	for slot in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_COLOR,
			Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS, Mesh.ARRAY_INDEX]:
		out[slot] = source[slot]
	return out


## The entries of `order` from a per-vertex packed array of any stride.
static func _pick(values: Variant, order: PackedInt32Array, vertex_count: int) -> Variant:
	var stride: int = values.size() / vertex_count
	var out: Variant = values.duplicate()
	out.resize(order.size() * stride)
	var j := 0
	for v in order:
		for k in stride:
			out[j] = values[v * stride + k]
			j += 1
	return out
