class_name LightningDebris
extends MultiMeshInstance3D
## Chunks of ground a strike tears up: faceted toon rocks in one MultiMesh
## that tumble, fall, bounce off the floor and shrink away. Opaque, so they
## take the ink outline. Frees itself when the last one is gone.

const MAX_CHUNKS := 32
const STRIDE := 12
const COLOR := Color(0.3, 0.24, 0.3)

static var _rock: SphereMesh
static var _material: ShaderMaterial

var gravity := 16.0
var floor_y := 0.0

var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _axis := PackedVector3Array()
var _spin := PackedFloat32Array()
var _turn := PackedFloat32Array()
var _size := PackedVector3Array()
var _age := PackedFloat32Array()
var _life := PackedFloat32Array()
var _buffer := PackedFloat32Array()


static func spawn(parent: Node, floor_height: float) -> LightningDebris:
	if _rock == null:
		_rock = SphereMesh.new()
		_rock.radius = 0.5
		_rock.height = 1.0
		_rock.radial_segments = 5
		_rock.rings = 3
		_material = ToonMaterials.make(COLOR)
	var debris := LightningDebris.new()
	debris.floor_y = floor_height
	parent.add_child(debris)
	return debris


func _init() -> void:
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 2.0
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = _rock
	multimesh.instance_count = MAX_CHUNKS
	multimesh.visible_instance_count = 0
	material_override = _material
	_buffer.resize(MAX_CHUNKS * STRIDE)
	_buffer.fill(0.0)


## Throws `count` chunks up out of a ring round `at`.
func throw(at: Vector3, count: int, ring: float, speed: Vector2, size: Vector2) -> void:
	for i in count:
		if _pos.size() >= MAX_CHUNKS:
			return
		var out := LightningArc.along_surface(Vector3.UP)
		_pos.append(at + out * ring * randf_range(0.2, 1.0) + Vector3.UP * 0.1)
		_vel.append((out * randf_range(0.3, 0.8) + Vector3.UP).normalized() * randf_range(speed.x, speed.y))
		_axis.append(LightningArc.scatter(Vector3.UP, PI))
		_spin.append(randf_range(6.0, 16.0))
		_turn.append(randf() * TAU)
		var s := randf_range(size.x, size.y)
		_size.append(Vector3(s * randf_range(0.8, 1.3), s * randf_range(0.6, 1.0), s * randf_range(0.8, 1.3)))
		_age.append(0.0)
		_life.append(randf_range(0.9, 1.4))


func _process(delta: float) -> void:
	var n := _pos.size()
	var i := 0
	while i < n:
		var age := _age[i] + delta
		if age >= _life[i]:
			n -= 1
			_pos[i] = _pos[n]
			_vel[i] = _vel[n]
			_axis[i] = _axis[n]
			_spin[i] = _spin[n]
			_turn[i] = _turn[n]
			_size[i] = _size[n]
			_age[i] = _age[n]
			_life[i] = _life[n]
			continue
		_age[i] = age
		var v := _vel[i]
		v.y -= gravity * delta
		var p := _pos[i] + v * delta
		if p.y < floor_y + _size[i].y * 0.4 and v.y < 0.0:
			p.y = floor_y + _size[i].y * 0.4
			v = Vector3(v.x * 0.55, -v.y * 0.35, v.z * 0.55)
			_spin[i] *= 0.5
		_pos[i] = p
		_vel[i] = v
		_turn[i] += _spin[i] * delta
		i += 1
	if n != _pos.size():
		_pos.resize(n)
		_vel.resize(n)
		_axis.resize(n)
		_spin.resize(n)
		_turn.resize(n)
		_size.resize(n)
		_age.resize(n)
		_life.resize(n)
	if n == 0:
		queue_free()
		return
	for k in n:
		var shrink := clampf((_life[k] - _age[k]) / 0.3, 0.0, 1.0)
		var basis := Basis(_axis[k], _turn[k]) * Basis.from_scale(_size[k] * shrink)
		var o := k * STRIDE
		var p := _pos[k]
		_buffer[o] = basis.x.x
		_buffer[o + 1] = basis.y.x
		_buffer[o + 2] = basis.z.x
		_buffer[o + 3] = p.x
		_buffer[o + 4] = basis.x.y
		_buffer[o + 5] = basis.y.y
		_buffer[o + 6] = basis.z.y
		_buffer[o + 7] = p.y
		_buffer[o + 8] = basis.x.z
		_buffer[o + 9] = basis.y.z
		_buffer[o + 10] = basis.z.z
		_buffer[o + 11] = p.z
	multimesh.buffer = _buffer
	multimesh.visible_instance_count = n
