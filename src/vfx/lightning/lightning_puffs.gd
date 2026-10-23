class_name LightningPuffs
extends MultiMeshInstance3D
## Billowing toon puffs in one MultiMesh (lightning_puff.gdshader): the dust
## a strike kicks up, smoke curling off a scorch. Each puff drifts on its own
## velocity (with drag and a slow rise), swells to its size and dissolves
## through noise with a dark edge over its life. Frees itself when the last
## one is gone. LightningCloud draws its billows with the same material.

const SHADER := preload("res://src/vfx/lightning/lightning_puff.gdshader")
const MAX_PUFFS := 32
const STRIDE := 16  # 12 floats of transform, 4 of custom data
## [dark, light] tones per palette.
const PALETTES := {
	&"dust": [Color(0.3, 0.22, 0.28), Color(0.64, 0.52, 0.54)],
	&"smoke": [Color(0.12, 0.09, 0.15), Color(0.34, 0.29, 0.39)],
	&"cloud": [Color(0.09, 0.07, 0.15), Color(0.38, 0.32, 0.54)],
}

static var _sphere: SphereMesh
static var _materials := {}

var drag := 2.5
## Upward acceleration (m/s^2): dust settles slowly, smoke climbs.
var rise := 0.4
## Part of each life after which a puff starts to dissolve.
var fade_from := 0.25
## Vertical squash of every puff.
var squash := 0.85

var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _age := PackedFloat32Array()
var _life := PackedFloat32Array()
var _size := PackedFloat32Array()
var _seed := PackedFloat32Array()
var _shade := PackedFloat32Array()
var _buffer := PackedFloat32Array()


static func shared_material(palette: StringName) -> ShaderMaterial:
	if _materials.has(palette):
		return _materials[palette]
	var tones: Array = PALETTES[palette]
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter(&"dark_color", tones[0])
	material.set_shader_parameter(&"light_color", tones[1])
	_materials[palette] = material
	return material


## A unit-diameter sphere, coarse enough to stay cheap, round enough to
## band cleanly.
static func sphere() -> SphereMesh:
	if _sphere == null:
		_sphere = SphereMesh.new()
		_sphere.radius = 0.5
		_sphere.height = 1.0
		_sphere.radial_segments = 14
		_sphere.rings = 7
	return _sphere


static func spawn(parent: Node, palette: StringName) -> LightningPuffs:
	var puffs := LightningPuffs.new()
	puffs.material_override = shared_material(palette)
	parent.add_child(puffs)
	return puffs


func _init() -> void:
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 2.0
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = sphere()
	multimesh.instance_count = MAX_PUFFS
	multimesh.visible_instance_count = 0
	_buffer.resize(MAX_PUFFS * STRIDE)
	_buffer.fill(0.0)


## One puff from `at`, drifting at `velocity`, `size` metres across at its
## fullest, gone after `life` seconds.
func emit(at: Vector3, velocity: Vector3, size: float, life: float, shade := -1.0) -> void:
	if _pos.size() >= MAX_PUFFS:
		return
	_pos.append(at)
	_vel.append(velocity)
	_age.append(0.0)
	_life.append(maxf(life, 0.05))
	_size.append(size)
	_seed.append(randf())
	_shade.append(randf_range(0.35, 1.0) if shade < 0.0 else shade)


func _process(delta: float) -> void:
	var n := _pos.size()
	var i := 0
	var damping := 1.0 / (1.0 + drag * delta)
	while i < n:
		var age := _age[i] + delta
		if age >= _life[i]:
			n -= 1
			_pos[i] = _pos[n]
			_vel[i] = _vel[n]
			_age[i] = _age[n]
			_life[i] = _life[n]
			_size[i] = _size[n]
			_seed[i] = _seed[n]
			_shade[i] = _shade[n]
			continue
		_age[i] = age
		var v := _vel[i] * damping
		v.y += rise * delta
		_vel[i] = v
		_pos[i] += v * delta
		i += 1
	if n != _pos.size():
		# (packed arrays are values: each one is resized by name)
		_pos.resize(n)
		_vel.resize(n)
		_age.resize(n)
		_life.resize(n)
		_size.resize(n)
		_seed.resize(n)
		_shade.resize(n)
	if n == 0:
		queue_free()
		return
	for k in n:
		var t := _age[k] / _life[k]
		var swell := 1.0 - pow(1.0 - minf(t / 0.35, 1.0), 3.0)
		var s := _size[k] * (0.3 + 0.7 * swell)
		write(_buffer, k, _pos[k], Vector3(s, s * squash, s), smoothstep(fade_from, 1.0, t), 0.0, _seed[k], _shade[k])
	multimesh.buffer = _buffer
	multimesh.visible_instance_count = n


## Writes one puff into a MultiMesh buffer laid out like this one's.
static func write(buffer: PackedFloat32Array, index: int, at: Vector3, scale: Vector3, dissolve: float, glow: float,
		seed: float, shade: float) -> void:
	var o := index * STRIDE
	buffer[o] = scale.x
	buffer[o + 3] = at.x
	buffer[o + 5] = scale.y
	buffer[o + 7] = at.y
	buffer[o + 10] = scale.z
	buffer[o + 11] = at.z
	buffer[o + 12] = dissolve
	buffer[o + 13] = glow
	buffer[o + 14] = seed
	buffer[o + 15] = shade
