class_name LightningSparks
extends MultiMeshInstance3D
## Sparks thrown off by electricity: points with a velocity, gravity and air
## drag that bounce off a flat floor (`floor_y`), drawn in one MultiMesh as
## camera-facing streaks along their velocity (lightning_spark.gdshader).
## Spray more with emit(). It frees itself once the last spark is gone,
## unless `hold` keeps it waiting for more. Lives in world space.

const SHADER := preload("res://src/vfx/lightning/lightning_spark.gdshader")
const MAX_SPARKS := 128
const STRIDE := 16  # 12 floats of transform, 4 of custom data

static var _quad: QuadMesh
static var _material: ShaderMaterial

var gravity := 14.0
var drag := 1.5
var floor_y := -1000.0
var bounce := 0.45
## Stay alive while empty: an emitter that will spray more later.
var hold := false

var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _age := PackedFloat32Array()
var _life := PackedFloat32Array()
var _size := PackedFloat32Array()
var _buffer := PackedFloat32Array()


static func spawn(parent: Node, tint := LightningFx.COLOR, floor_height := -1000.0) -> LightningSparks:
	var sparks := LightningSparks.new()
	sparks.floor_y = floor_height
	sparks.set_instance_shader_parameter(&"tint", tint)
	parent.add_child(sparks)
	return sparks


func _init() -> void:
	if _material == null:
		_quad = QuadMesh.new()
		_material = ShaderMaterial.new()
		_material.shader = SHADER
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 1.5
	material_override = _material
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = _quad
	multimesh.instance_count = MAX_SPARKS
	multimesh.visible_instance_count = 0
	_buffer.resize(MAX_SPARKS * STRIDE)
	_buffer.fill(0.0)


## Throws `count` sparks from `at` into a cone `spread` radians around
## `direction`, at `speed.x`..`speed.y` m/s, each living `life.x`..`life.y`
## seconds.
func emit(at: Vector3, count: int, direction: Vector3, spread: float, speed: Vector2, life: Vector2, size := 0.035) -> void:
	for i in count:
		if _pos.size() >= MAX_SPARKS:
			return
		_pos.append(at)
		_vel.append(LightningArc.scatter(direction, spread) * randf_range(speed.x, speed.y))
		_age.append(0.0)
		_life.append(randf_range(life.x, life.y))
		_size.append(size * randf_range(0.7, 1.3))


## Adds one spark with an exact start and velocity.
func add(at: Vector3, velocity: Vector3, life: float, size := 0.035) -> void:
	if _pos.size() >= MAX_SPARKS:
		return
	_pos.append(at)
	_vel.append(velocity)
	_age.append(0.0)
	_life.append(life)
	_size.append(size)


func alive() -> int:
	return _pos.size()


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
			continue
		_age[i] = age
		var v := _vel[i]
		v.y -= gravity * delta
		v *= damping
		var p := _pos[i] + v * delta
		if p.y < floor_y and v.y < 0.0:
			p.y = floor_y + (floor_y - p.y) * bounce
			v = Vector3(v.x * 0.6, -v.y * bounce, v.z * 0.6)
		_pos[i] = p
		_vel[i] = v
		i += 1
	if n != _pos.size():
		_pos.resize(n)
		_vel.resize(n)
		_age.resize(n)
		_life.resize(n)
		_size.resize(n)
	if n == 0 and not hold:
		queue_free()
		return
	_upload()


func _upload() -> void:
	var n := _pos.size()
	for i in n:
		var o := i * STRIDE
		var s := _size[i]
		var p := _pos[i]
		var v := _vel[i]
		_buffer[o] = s
		_buffer[o + 3] = p.x
		_buffer[o + 5] = s
		_buffer[o + 7] = p.y
		_buffer[o + 10] = s
		_buffer[o + 11] = p.z
		_buffer[o + 12] = v.x
		_buffer[o + 13] = v.y
		_buffer[o + 14] = v.z
		_buffer[o + 15] = 1.0 - _age[i] / _life[i]
	multimesh.buffer = _buffer
	multimesh.visible_instance_count = n
