class_name FireMotes
extends MultiMeshInstance3D
## A small pool of CPU-simulated motes in world space (embers, sparks or smoke
## wisps), spawned one at a time so a fast source can lay them evenly along
## its path, or pulled into a node (sparks sucked into a charging fist). One
## draw call, drawn with a FireKit mote or smoke material: INSTANCE_CUSTOM.x
## is a seed (the smoke's spin), .y the age as a fraction of the life.

## Constant acceleration in m/s² (negative y falls, positive rises).
var gravity := Vector3(0.0, -2.0, 0.0)
## Fraction of the velocity lost per second.
var drag := 2.0
## Sparks: the streak's length grows by this many metres per m/s of speed
## (0 keeps motes round).
var streak := 0.0
## How much a mote's size grows over its life (1 doubles it).
var grow := 0.0
## Motes home in on this node, pulled with `pull` (1/s²), and burn out on
## reaching it.
var attractor: Node3D
var pull := 0.0

var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _age := PackedFloat32Array()
var _life := PackedFloat32Array()
var _size := PackedFloat32Array()
var _seed := PackedFloat32Array()


static func create(capacity: int, material: Material) -> FireMotes:
	var motes := FireMotes.new()
	motes.top_level = true
	motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_custom_data = true
	multi.mesh = FireKit.quad()
	multi.instance_count = capacity
	multi.visible_instance_count = 0
	motes.multimesh = multi
	motes.material_override = material
	return motes


func spawn(at: Vector3, velocity: Vector3, life: float, size: float) -> void:
	if _pos.size() >= multimesh.instance_count:
		return
	_pos.append(at)
	_vel.append(velocity)
	_age.append(0.0)
	_life.append(maxf(life, 0.01))
	_size.append(size)
	_seed.append(randf() * TAU)


func alive() -> int:
	return _pos.size()


func _process(delta: float) -> void:
	var count := _pos.size()
	var homing := is_instance_valid(attractor) and attractor.is_inside_tree()
	var target := attractor.global_position if homing else Vector3.ZERO
	var keep := maxf(0.0, 1.0 - drag * delta)
	var i := 0
	while i < count:
		var age := _age[i] + delta
		var dead := age >= _life[i]
		if homing and not dead:
			var to_target := target - _pos[i]
			dead = to_target.length_squared() < 0.0016
			_vel[i] += to_target * pull * delta
		if dead:
			count -= 1
			_pos[i] = _pos[count]
			_vel[i] = _vel[count]
			_age[i] = _age[count]
			_life[i] = _life[count]
			_size[i] = _size[count]
			_seed[i] = _seed[count]
			continue
		_age[i] = age
		_vel[i] = _vel[i] * keep + gravity * delta
		_pos[i] += _vel[i] * delta
		i += 1
	if count != _pos.size():
		_pos.resize(count)
		_vel.resize(count)
		_age.resize(count)
		_life.resize(count)
		_size.resize(count)
		_seed.resize(count)
	_draw(count)


func _draw(count: int) -> void:
	var multi := multimesh
	var low := Vector3.INF
	var high := -Vector3.INF
	for j in count:
		var fraction := _age[j] / _life[j]
		var size := _size[j] * (1.0 + grow * fraction)
		var basis: Basis
		if streak > 0.0:
			var speed := _vel[j].length()
			var dir := _vel[j] / speed if speed > 0.001 else Vector3.UP
			var side := dir.cross(Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT).normalized()
			basis = Basis(side * size, dir * (size + speed * streak), side.cross(dir) * size)
		else:
			basis = Basis.from_scale(Vector3(size, size, size))
		multi.set_instance_transform(j, Transform3D(basis, _pos[j]))
		multi.set_instance_custom_data(j, Color(_seed[j], fraction, 0.0, 0.0))
		low = low.min(_pos[j])
		high = high.max(_pos[j])
	multi.visible_instance_count = count
	if count > 0:
		# world-space positions: keep culling and sorting honest
		var margin := Vector3.ONE * 0.6
		custom_aabb = AABB(low - margin, high - low + margin * 2.0)
