class_name LightningCloud
extends Node3D
## The storm cloud a Lightning Strike calls down (LightningWarningFx). One
## lumpy, flat-bellied storm mass (a mesh built in code, so the ink outline
## only traces its silhouette and big folds, never a heap of balls) swells
## and thickens over the mark while wisps spiral in and merge into it. It is
## lit from inside by flashes of lightning: a hot patch on its belly in hard
## bands, more and more often as the strike nears, with arcs crawling across
## the underside. burst() lights the belly round the bolt in step with the
## strike's strobe; then the cloud tears apart and frees itself. Its origin
## is the cloud's centre. Drawn with lightning_puff.gdshader.

const REFRESH := 1.0 / 30.0
const BREAK_UP := 0.75
const WISPS := 11
## How far the belly sits below the centre, as a part of the height.
const BELLY := 0.32

## A few body meshes, shared by every cloud (built on first use).
static var _bodies: Array[ArrayMesh] = []

var radius := 2.5
## Seconds to gather (the strike's delay).
var gather := 0.9

var _body: MultiMeshInstance3D
var _wisps: MultiMeshInstance3D
var _arcs: LightningArc
var _width := 3.4
var _height := 1.7
var _from := PackedVector3Array()
var _to := PackedVector3Array()
var _size := PackedFloat32Array()
var _seed := PackedFloat32Array()
var _body_buffer := PackedFloat32Array()
var _wisp_buffer := PackedFloat32Array()
var _age := 0.0
var _burst_at := -1.0
var _spin := 0.0
var _next := 0.0
var _next_flash := 0.0
var _belly_left := 0.0
var _glow := 0.0
var _hot := Vector2.ZERO
var _hot_reach := 1.0


static func make(cloud_radius: float, gather_seconds: float) -> LightningCloud:
	var cloud := LightningCloud.new()
	cloud.name = "StormCloud"
	cloud.radius = cloud_radius
	cloud.gather = maxf(gather_seconds, 0.1)
	return cloud


func _ready() -> void:
	# wider than the circle, so it reads as the thing the bolt falls from
	_width = radius * 1.3
	_height = 1.7
	var material := LightningPuffs.shared_material(&"cloud")
	_body = _multimesh(_body_mesh(), 1, material)
	_body.extra_cull_margin = _width
	_body.rotation.y = randf() * TAU
	_wisps = _multimesh(LightningPuffs.sphere(), WISPS, material)
	_body_buffer.resize(LightningPuffs.STRIDE)
	_wisp_buffer.resize(WISPS * LightningPuffs.STRIDE)
	# billows spiral in from wide and settle on top of the body as its crown
	# (one in the middle), giving a cumulus outline above the flat belly
	for i in WISPS:
		var angle := TAU * (i + randf_range(-0.3, 0.3)) / (WISPS - 1)
		var out := Vector3(cos(angle), 0.0, sin(angle))
		# alternate big and small lobes, so the top outline is lumpy
		var big := i % 2 == 0
		var ring := 0.0 if i == WISPS - 1 else (randf_range(0.35, 0.5) if big else randf_range(0.66, 0.8))
		_from.append(out * _width * randf_range(1.3, 1.7) + Vector3.UP * randf_range(-0.6, 0.9))
		_to.append(out * _width * ring + Vector3.UP * _height * (0.55 if ring == 0.0 else (randf_range(0.35, 0.45) if big else 0.12)))
		_size.append(_width * (0.62 if ring == 0.0 else (randf_range(0.45, 0.55) if big else randf_range(0.3, 0.38))))
		_seed.append(randf())
	_arcs = LightningArc.new()
	_arcs.style(false, LightningFx.COLOR)
	add_child(_arcs)
	_update_puffs()


func _multimesh(mesh: Mesh, count: int, material: Material) -> MultiMeshInstance3D:
	var node := MultiMeshInstance3D.new()
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.extra_cull_margin = 3.0
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	multimesh.instance_count = count
	node.multimesh = multimesh
	add_child(node)
	return node


## One of the shared body meshes, scaled to this cloud.
func _body_mesh() -> ArrayMesh:
	if _bodies.size() < 3:
		_bodies.append(build_body(_bodies.size() * 7 + 3))
	var mesh := _bodies[randi() % _bodies.size()]
	return mesh


## A storm-cloud mass of unit size (x and z in -1..1, y about -BELLY..0.9):
## a sphere pushed out by round lumps on top and round the sides, with a
## flat belly. Normals are smoothed so the toon bands follow the lumps.
static func build_body(seed_value: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var lumps: Array[Vector4] = []  # direction xyz, strength w
	# big billows round the sides scallop the outline seen from below;
	# smaller ones heap up the top
	for i in 12:
		var y := rng.randf_range(-0.1, 0.3)
		var angle := TAU * (i + rng.randf_range(-0.25, 0.25)) / 12.0
		var flat := sqrt(maxf(1.0 - y * y, 0.0))
		lumps.append(Vector4(cos(angle) * flat, y, sin(angle) * flat, rng.randf_range(0.22, 0.5)))
	for i in 7:
		var y := rng.randf_range(0.45, 0.95)
		var angle := rng.randf() * TAU
		var flat := sqrt(maxf(1.0 - y * y, 0.0))
		lumps.append(Vector4(cos(angle) * flat, y, sin(angle) * flat, rng.randf_range(0.2, 0.4)))
	var rings := 18
	var segments := 36
	var vertices := PackedVector3Array()
	for r in rings + 1:
		var polar := PI * r / rings
		for s in segments + 1:
			var azimuth := TAU * s / segments
			var dir := Vector3(sin(polar) * cos(azimuth), cos(polar), sin(polar) * sin(azimuth))
			var push := 1.0
			for lump in lumps:
				var d := dir.dot(Vector3(lump.x, lump.y, lump.z))
				push += lump.w * pow(maxf(d, 0.0), 18.0)
			var point := dir * push
			# a low, flat body: the crown billows on top give the cloud its height
			point.y = maxf(point.y * (0.36 if point.y > 0.0 else 0.62), -BELLY)
			vertices.append(point)
	var indices := PackedInt32Array()
	var row := segments + 1
	for r in rings:
		for s in segments:
			var a := r * row + s
			indices.append_array([a, a + row, a + 1, a + 1, a + row, a + row + 1])
	# the seam column duplicates the first: share its position
	for r in rings + 1:
		vertices[r * row + segments] = vertices[r * row]
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	for t in range(0, indices.size(), 3):
		var a := vertices[indices[t]]
		var face := (vertices[indices[t + 2]] - a).cross(vertices[indices[t + 1]] - a)
		for k in 3:
			normals[indices[t + k]] += face
	for r in rings + 1:
		var shared := normals[r * row] + normals[r * row + segments]
		normals[r * row] = shared
		normals[r * row + segments] = shared
	for i in normals.size():
		normals[i] = normals[i].normalized() if normals[i].length() > 1e-6 else Vector3.UP
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## The bolt leaves the cloud: its belly lights up round the bolt, then the
## cloud breaks apart.
func burst() -> void:
	if _burst_at >= 0.0:
		return
	_burst_at = _age


## The belly's light after the bolt leaves: on-off-on with the bolt's strobe
## (LightningStrikeFx), then flickering out.
static func _burst_level(since: float) -> float:
	if since < 0.05:
		return 1.0
	if since < 0.085:
		return 0.15
	if since < 0.16:
		return 0.95
	return maxf(0.0, 1.0 - (since - 0.16) / 0.22) * randf_range(0.4, 1.0)


func _process(delta: float) -> void:
	_age += delta
	if _burst_at >= 0.0 and _age - _burst_at > BREAK_UP:
		queue_free()
		return
	var p := clampf(_age / gather, 0.0, 1.0)
	_spin += delta * lerpf(1.1, 0.3, p)
	_glow = maxf(_glow - delta * 9.0, 0.0)
	if _burst_at >= 0.0:
		_hot = Vector2.ZERO
		_hot_reach = 1.15
		_glow = _burst_level(_age - _burst_at)
	else:
		_next_flash -= delta
		if _next_flash <= 0.0:
			_next_flash = randf_range(0.5, 1.4) / lerpf(3.0, 20.0, p * p)
			_flash()
	_next -= delta
	_belly_left -= delta
	if _next <= 0.0:
		_next = REFRESH
		_redraw_belly(p)
	_update_puffs()


## Lightning inside: a patch of the belly flares (in the body's unit space).
func _flash() -> void:
	var angle := randf() * TAU
	_hot = Vector2(cos(angle), sin(angle)) * randf_range(0.0, 0.7)
	_hot_reach = randf_range(0.35, 0.6)
	_glow = randf_range(0.8, 1.0)
	if randf() < 0.55:
		_belly_left = REFRESH * 2.0


## Arcs crawling across the cloud's underside, now and then.
func _redraw_belly(p: float) -> void:
	_arcs.clear()
	if _belly_left > 0.0 or (_burst_at >= 0.0 and _age - _burst_at < 0.25):
		var swell := _swell()
		var below := Vector3.DOWN * (BELLY * _height * swell + 0.08)
		for i in 1 + int(p * 2.0):
			var a := _belly_point(swell) + below
			var b := _belly_point(swell) + below
			if a.distance_to(b) > 0.8:
				_arcs.add(LightningArc.jagged(global_transform * a, global_transform * b, 4, 0.22), 0.025, 1.0, 0.5, 0.3)
	_arcs.commit()


func _belly_point(swell: float) -> Vector3:
	var angle := randf() * TAU
	return Vector3(cos(angle), 0.0, sin(angle)) * _width * swell * sqrt(randf()) * 0.75


func _form() -> float:
	return 1.0 - pow(1.0 - clampf(_age / gather, 0.0, 1.0), 3.0)


func _swell() -> float:
	if _burst_at >= 0.0:
		return 1.0 + clampf((_age - _burst_at) / BREAK_UP, 0.0, 1.0) * 0.2
	return lerpf(0.45, 1.0, _form())


func _update_puffs() -> void:
	var form := _form()
	var swell := _swell()
	# a thin mass that thickens into a solid cloud, then tears apart after
	# the strike
	var dissolve := 0.6 * pow(1.0 - form, 1.5)
	if _burst_at >= 0.0:
		dissolve = smoothstep(0.05, 1.0, (_age - _burst_at) / BREAK_UP)
	var w := _width * swell
	LightningPuffs.write(_body_buffer, 0, Vector3.ZERO, Vector3(w, _height * swell, w), dissolve, _glow, 0.37, 0.45)
	_body.multimesh.buffer = _body_buffer
	# (the hot patch in mesh space: the body is scaled by w and turned)
	var hot := Vector2(_hot.x, _hot.y)
	_body.set_instance_shader_parameter(&"hotspot", Vector4(hot.x, 0.0, hot.y, _hot_reach))
	# the crown spirals in and settles; it tears away with the body
	for i in WISPS:
		var at := _from[i].lerp(_to[i] * swell, form).rotated(Vector3.UP, _spin * 0.3)
		var s := _size[i] * lerpf(0.4, 1.0, form) * (swell if _burst_at >= 0.0 else 1.0)
		LightningPuffs.write(_wisp_buffer, i, at, Vector3(s, s * 0.7, s), dissolve, _glow * 0.25, _seed[i],
				0.75 + 0.02 * i)
	_wisps.multimesh.buffer = _wisp_buffer
