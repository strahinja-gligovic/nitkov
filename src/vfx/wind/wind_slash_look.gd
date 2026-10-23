class_name WindSlashLook
extends Node3D
## Wind Slash's body: a crescent blade of air bowed forward like a parabola,
## as wide as what it hits (its radius plus a fighter's body). A thin shell
## with a white-hot cutting edge (wind_blade.gdshader), streaks rushing off
## its back, wingtip trails left in the air, and a few leaves and motes
## caught in it. -Z is the direction of flight; the Projectile places it
## every frame. finish() lets it come apart. Cosmetic only.

const BLADE_SHADER := preload("res://src/vfx/wind/wind_blade.gdshader")
const LINE_SHADER := preload("res://src/vfx/wind/wind_line.gdshader")

## The cutting edge's apex sits this far ahead of the projectile's centre.
const APEX := 0.3
## The wingtips trail this far behind the apex and rise this much.
const SWEEP := 0.95
const RISE := 0.4
## The shell's half-height and depth at its middle.
const THICK := 0.22
const DEPTH := 0.4
## Seconds the blade takes to spread to full width after leaving the hand.
const UNFURL := 0.07
const LEAVES := 3
const MOTES := 5

static var _blade_meshes := {}
static var _line_meshes := {}
static var _blade_material: ShaderMaterial
static var _line_material: ShaderMaterial
static var _tip_material: ShaderMaterial

var half_width := 1.35

var _time := 0.0
var _ending := -1.0
var _blade: MeshInstance3D
var _lines: MeshInstance3D
var _bits: MultiMeshInstance3D
var _light: OmniLight3D
var _tips: Array[WindRibbon] = []
var _seeds := PackedFloat32Array()


static func create(spell: ProjectileSpell) -> WindSlashLook:
	var look := WindSlashLook.new()
	look.half_width = maxf(spell.radius, 0.3) + 0.35
	return look


func _ready() -> void:
	_build_materials()
	var key := roundi(half_width * 100.0)
	if not _blade_meshes.has(key):
		_blade_meshes[key] = _blade_mesh(half_width)
		_line_meshes[key] = _streak_mesh(half_width)
	_blade = MeshInstance3D.new()
	_blade.mesh = _blade_meshes[key]
	_blade.material_override = _blade_material
	_blade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_blade.set_instance_shader_parameter(&"seed", randf() * 10.0)
	add_child(_blade)
	_lines = MeshInstance3D.new()
	_lines.mesh = _line_meshes[key]
	_lines.material_override = _line_material
	_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_lines)
	_bits = MultiMeshInstance3D.new()
	_bits.multimesh = WindParticles.make_multimesh(LEAVES + MOTES)
	_bits.material_override = WindParticles.shared_material()
	_bits.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bits.extra_cull_margin = 2.0
	add_child(_bits)
	for i in LEAVES + MOTES:
		_seeds.append(randf())
	for side in 2:
		_tips.append(WindRibbon.spawn(self, _tip_material, 0.14, 0.04))
	if randf() < 0.5:
		_lines.scale.x = -1.0  # mirror the shared streak layout now and then
	_light = OmniLight3D.new()
	_light.light_color = WindFx.COLOR
	_light.light_energy = 1.2
	_light.omni_range = 3.5
	_light.shadow_enabled = false
	add_child(_light)
	scale = Vector3(0.35, 1.0, 1.0)


func _process(delta: float) -> void:
	_time += delta
	var fade := 1.0
	if _ending >= 0.0:
		_ending += delta
		fade = 1.0 - clampf(_ending / 0.12, 0.0, 1.0)
		_light.light_energy = 1.2 * fade
		if _ending > 0.3:
			queue_free()
			return
	else:
		# spread from the hand to full width, then hold
		var open := clampf(_time / UNFURL, 0.0, 1.0)
		var width := lerpf(0.35, 1.0, 1.0 - pow(1.0 - open, 3.0))
		scale = Vector3(width, 1.0, 1.0)
		if open >= 1.0:
			for side in 2:
				_tips[side].add(global_transform * _blade_point(-1.0 if side == 0 else 1.0, 0.0, half_width))
	for part: GeometryInstance3D in [_blade, _lines]:
		part.set_instance_shader_parameter(&"anim_time", _time)
		part.set_instance_shader_parameter(&"fade", fade)
	_place_bits(fade)


## Ends the slash: the blade and its streaks fade at once while the wingtip
## trails linger and thin out.
func finish() -> void:
	if _ending < 0.0:
		_ending = 0.0


## Leaves and motes riding the blade: each slides from the middle out to a
## wingtip and tumbles, then starts over.
func _place_bits(fade: float) -> void:
	var multimesh := _bits.multimesh
	for i in LEAVES + MOTES:
		var random := _seeds[i]
		var leaf := i < LEAVES
		var cycle := fposmod(random * 3.7 + _time * (1.6 if leaf else 2.6), 1.0)
		var side := -1.0 if i % 2 == 0 else 1.0
		var c := side * lerpf(0.05, 1.05, cycle)
		var s := (random * 2.0 - 1.0) * 0.8
		var at := _blade_point(clampf(c, -1.0, 1.0), s, half_width) + Vector3(0.0, 0.0, 0.12 + 0.25 * cycle)
		var alpha := sin(cycle * PI) * fade
		var basis := Basis.IDENTITY
		var size := 0.05
		if leaf:
			var axis := Vector3(random - 0.5, 1.0, 0.6 - random).normalized()
			basis = Basis(axis, _time * (9.0 + random * 8.0) + random * TAU)
			size = 0.16
		# undo the unfurl squash so the bits keep their shape
		basis = Basis.from_scale(Vector3(1.0 / maxf(scale.x, 0.05), 1.0, 1.0)) * basis.scaled(Vector3.ONE * size)
		multimesh.set_instance_transform(i, Transform3D(basis, at))
		var kind := WindParticles.Kind.LEAF if leaf else WindParticles.Kind.MOTE
		multimesh.set_instance_custom_data(i, WindParticles.custom(kind, cycle, random, alpha))
	multimesh.visible_instance_count = LEAVES + MOTES


## A point on the shell: `c` runs tip to tip (-1..1), `s` from the lower rim
## over the cutting edge (0) to the upper rim (1).
static func _blade_point(c: float, s: float, reach: float) -> Vector3:
	var taper := pow(maxf(1.0 - pow(absf(c), 2.2), 0.0), 0.75)
	var edge := Vector3(reach * c, RISE * c * c, -APEX + SWEEP * c * c)
	return edge + Vector3(0.0, THICK * taper * s, DEPTH * taper * s * s)


## The crescent shell (see wind_blade.gdshader for its UVs).
static func _blade_mesh(reach: float) -> ArrayMesh:
	var columns := 40
	var rows := 10
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for i in columns + 1:
		var u := float(i) / columns
		var c := u * 2.0 - 1.0
		for j in rows + 1:
			var v := float(j) / rows
			var s := v * 2.0 - 1.0
			vertices.append(_blade_point(c, s, reach))
			var along := _blade_point(clampf(c + 0.01, -1.0, 1.0), s, reach) - _blade_point(clampf(c - 0.01, -1.0, 1.0), s, reach)
			var across := _blade_point(c * 0.98, s + 0.01, reach) - _blade_point(c * 0.98, s - 0.01, reach)
			var normal := along.cross(across)
			normals.append(normal.normalized() if normal.length() > 0.000001 else Vector3.BACK)
			uvs.append(Vector2(u, v))
			if i > 0 and j > 0:
				var a := (i - 1) * (rows + 1) + j - 1
				var b := a + rows + 1
				indices.append_array([a, b, a + 1, a + 1, b, b + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.custom_aabb = AABB(Vector3(-reach - 0.3, -0.6, -0.8), Vector3(reach * 2.0 + 0.6, 1.2, 4.0))
	return mesh


## Streaks rushing back off the blade's rims: they start on the shell and
## stream out behind it, fanning slightly toward the wingtips.
static func _streak_mesh(reach: float) -> ArrayMesh:
	var paths: Array[PackedVector3Array] = []
	var widths := PackedFloat32Array()
	for i in 8:
		var c := randf_range(-0.7, 0.7)
		var s := randf_range(0.75, 0.95) * (1.0 if i % 2 == 0 else -1.0)
		var start := _blade_point(c, s, reach)
		var length := lerpf(1.6, 0.7, absf(c)) * randf_range(0.7, 1.1)
		var path := PackedVector3Array()
		for k in 6:
			var t := float(k) / 5.0
			path.append(start + Vector3(c * 0.25 * t * length, 0.0, t * length))
		paths.append(path)
		widths.append(randf_range(0.018, 0.03))
	return WindMeshes.lines(paths, widths, 0.45)


static func _build_materials() -> void:
	if _blade_material:
		return
	_blade_material = ShaderMaterial.new()
	_blade_material.shader = BLADE_SHADER
	_line_material = ShaderMaterial.new()
	_line_material.shader = LINE_SHADER
	_line_material.set_shader_parameter(&"energy", 1.1)
	_line_material.set_shader_parameter(&"dash_fill", 0.55)
	_line_material.set_shader_parameter(&"scroll", 5.0)
	_line_material.set_shader_parameter(&"tail_fade", 1.0)
	_tip_material = ShaderMaterial.new()
	_tip_material.shader = LINE_SHADER
	_tip_material.set_shader_parameter(&"energy", 1.2)
	_tip_material.set_shader_parameter(&"core_width", 0.25)
	_tip_material.set_shader_parameter(&"head_fade", 0.02)
	_tip_material.set_shader_parameter(&"tail_fade", 0.6)
