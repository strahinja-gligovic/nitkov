class_name LightningArc
extends MeshInstance3D
## Jagged lines of electricity, drawn as camera-facing ribbons
## (lightning_arc.gdshader). Owners rebuild it whenever their arcs
## re-randomize: clear(), add() each path, commit(). It lives in world space
## (top_level) and the shader turns every strip toward the camera, so nothing
## here needs a camera and it runs headless. The static helpers build the
## shapes: jagged() paths by midpoint displacement, fork() branches,
## scatter() random directions.

const GLOW_SHADER := preload("res://src/vfx/lightning/lightning_arc.gdshader")
const INK_SHADER := preload("res://src/vfx/lightning/lightning_ink.gdshader")

static var _materials := {}

var _mesh := ArrayMesh.new()
var _vertices := PackedVector3Array()
var _normals := PackedVector3Array()
var _uvs := PackedVector2Array()
var _uv2s := PackedVector2Array()
var _indices := PackedInt32Array()


func _init() -> void:
	top_level = true
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 2.0
	material_override = shared_material(false)


## The shared ribbon material: glowing only, or `inked` (a dark comic outline
## drawn first, the glow over it) for the big bolts.
static func shared_material(inked: bool) -> Material:
	if _materials.has(inked):
		return _materials[inked]
	var glow := ShaderMaterial.new()
	glow.shader = GLOW_SHADER
	# drawn over every ink backing (and the additive glow loses nothing by it)
	glow.render_priority = 1
	var result: Material = glow
	if inked:
		# the big bolts stay a couple of pixels thick however far away
		glow.set_shader_parameter(&"min_pixels", 2.0)
		var ink := ShaderMaterial.new()
		ink.shader = INK_SHADER
		ink.set_shader_parameter(&"min_pixels", 2.0)
		ink.next_pass = glow
		result = ink
	_materials[inked] = result
	return result


## Switches to the inked look and sets the colour.
func style(inked: bool, tint: Color) -> void:
	material_override = shared_material(inked)
	set_instance_shader_parameter(&"tint", tint)


func set_brightness(value: float) -> void:
	set_instance_shader_parameter(&"brightness", value)


func clear() -> void:
	_vertices.clear()
	_normals.clear()
	_uvs.clear()
	_uv2s.clear()
	_indices.clear()


## Adds one path. `width` is its half-width in metres at the start, narrowing
## to width * (1 - taper) at the end; its brightness fades by `fade` the same
## way.
func add(points: PackedVector3Array, width: float, brightness := 1.0, taper := 0.0, fade := 0.0) -> void:
	var count := points.size()
	if count < 2:
		return
	var base := _vertices.size()
	var last := count - 1
	for i in count:
		var t := float(i) / last
		_append(points, i, last, t, Vector2(width * (1.0 - taper * t), brightness * (1.0 - fade * t)))
		if i > 0:
			_join(base + i * 2 - 2)


## Adds one path with its own half-width and brightness at every point.
func add_shaped(points: PackedVector3Array, widths: PackedFloat32Array, brights: PackedFloat32Array) -> void:
	var count := points.size()
	if count < 2:
		return
	var base := _vertices.size()
	var last := count - 1
	for i in count:
		_append(points, i, last, float(i) / last, Vector2(widths[i], brights[i]))
		if i > 0:
			_join(base + i * 2 - 2)


func _append(points: PackedVector3Array, i: int, last: int, t: float, shape: Vector2) -> void:
	var point := points[i]
	var tangent := (points[mini(i + 1, last)] - points[maxi(i - 1, 0)]).normalized()
	_vertices.append(point)
	_vertices.append(point)
	_normals.append(tangent)
	_normals.append(tangent)
	_uvs.append(Vector2(t, -1.0))
	_uvs.append(Vector2(t, 1.0))
	_uv2s.append(shape)
	_uv2s.append(shape)


func _join(a: int) -> void:
	_indices.append(a)
	_indices.append(a + 1)
	_indices.append(a + 2)
	_indices.append(a + 1)
	_indices.append(a + 3)
	_indices.append(a + 2)


## Uploads what was added since clear().
func commit() -> void:
	_mesh.clear_surfaces()
	if _indices.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	arrays[Mesh.ARRAY_TEX_UV2] = _uv2s
	arrays[Mesh.ARRAY_INDEX] = _indices
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


# --- shapes ------------------------------------------------------------------

## A jagged path from `from` to `to` by midpoint displacement: `levels`
## halvings (2^levels segments), the first kick up to `sway` x the length to
## the side, each finer level about half as far. With a `surface` normal the
## kicks stay in that plane, lifting only slightly off it (arcs crawling
## along a wall or the floor).
static func jagged(from: Vector3, to: Vector3, levels: int, sway: float, surface := Vector3.ZERO) -> PackedVector3Array:
	var points := PackedVector3Array([from, to])
	var along := to - from
	var length := along.length()
	if length < 0.0001:
		return points
	var dir := along / length
	var side: Vector3
	var lift: Vector3
	var lift_min := -1.0
	if surface != Vector3.ZERO:
		side = dir.cross(surface)
		side = side.normalized() if side.length() > 0.001 else _perpendicular(dir)
		lift = surface * 0.35
		lift_min = 0.0
	else:
		side = _perpendicular(dir)
		lift = dir.cross(side)
	var kick := length * sway
	for level in levels:
		var count := points.size()
		var next := PackedVector3Array()
		next.resize(count * 2 - 1)
		for i in count - 1:
			var a := points[i]
			next[i * 2] = a
			next[i * 2 + 1] = (a + points[i + 1]) * 0.5 + side * randf_range(-kick, kick) \
					+ lift * randf_range(lift_min * kick, kick)
		next[count * 2 - 2] = points[count - 1]
		points = next
		kick *= 0.55
	return points


## A branch off `path`: it leaves from a random point between `span.x` and
## `span.y` of the way along, heads off up to `angle` radians from the
## path's overall direction (within the `surface` plane, if one is given)
## and runs `reach` metres.
static func fork(path: PackedVector3Array, reach: float, angle: float, levels := 3, sway := 0.2,
		surface := Vector3.ZERO, span := Vector2(0.15, 0.8)) -> PackedVector3Array:
	var last := path.size() - 1
	var i := clampi(roundi(randf_range(span.x, span.y) * last), 0, last)
	var start := path[i]
	var overall := (path[last] - path[0]).normalized()
	var out: Vector3
	if surface != Vector3.ZERO:
		var axis := surface.normalized()
		out = overall.rotated(axis, randf_range(0.35, 1.0) * angle * (1.0 if randf() < 0.5 else -1.0))
	else:
		out = scatter(overall, angle)
		# never straight back along the path
		if out.dot(overall) < 0.2:
			out = (out + overall).normalized()
	return jagged(start, start + out * reach, levels, sway, surface)


## A random direction within `spread` radians of `direction` (uniform over
## the cone's cap; PI for any direction).
static func scatter(direction: Vector3, spread: float) -> Vector3:
	var dir := direction.normalized()
	if spread <= 0.0 or dir == Vector3.ZERO:
		return dir
	var side := _perpendicular(dir)
	var up := dir.cross(side)
	var turn := randf() * TAU
	var tilt := acos(lerpf(1.0, cos(minf(spread, PI)), randf()))
	return (dir * cos(tilt) + (side * cos(turn) + up * sin(turn)) * sin(tilt)).normalized()


## A random direction along a surface (perpendicular to `normal`).
static func along_surface(normal: Vector3) -> Vector3:
	var side := _perpendicular(normal)
	return side.rotated(normal.normalized(), randf() * TAU)


static func _perpendicular(dir: Vector3) -> Vector3:
	return dir.cross(Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT).normalized()
