class_name FrostBits
extends MultiMeshInstance3D
## Cosmetic bits simulated here and drawn as one MultiMesh: ice CHUNKs
## (tumbling, bouncing off the floor, flashing white at birth and crumbling
## at the end), SPARKLEs (twinkling glitter) or mist PUFFs (swelling,
## drifting and eroding). Positions are in this node's space: world space
## for a burst made with world_burst(), the parent's space otherwise. A
## burst frees itself once its last bit is gone; a `pooled` emitter (the
## spike's glitter) recycles its slots and lives until its owner frees it.

enum Kind { CHUNK, SPARKLE, PUFF }

const HIDDEN_BASIS := Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)

var kind := Kind.CHUNK
## Pull along -Y in m/s² (chunks fall, glitter settles; negative rises).
var gravity := 0.0
## Fraction of speed lost per second.
var drag := 0.0
## Chunks bounce off this height (the floor under the burst).
var floor_y := -1.0e9
var bounce := 0.3
## Chunk tumbling speed (rad/s, random up to this).
var spin := 10.0
## Puffs swell to this multiple of their size over their life.
var swell := 2.2
## When the slots run out, recycle the oldest instead of dropping bits.
var pooled := false

var _capacity := 0
var _next := 0
var _added := false
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _size := PackedVector3Array()
var _axis := PackedVector3Array()
var _angle := PackedFloat32Array()
var _spin := PackedFloat32Array()
var _age := PackedFloat32Array()
var _life := PackedFloat32Array()
var _seed := PackedFloat32Array()
var _violet := PackedFloat32Array()


## A burst of up to `capacity` bits of one kind, with the shared mesh and
## material for it. Chunks are `glass` (no ink outline) unless they are big
## enough for one.
static func make(bit_kind: Kind, capacity: int, glass := true) -> FrostBits:
	var bits := FrostBits.new()
	bits.kind = bit_kind
	var mesh: Mesh
	var material: Material
	match bit_kind:
		Kind.CHUNK:
			mesh = FrostKit.chunk_mesh(randi() % 3)
			material = FrostKit.chunk_material(glass)
		Kind.SPARKLE:
			mesh = FrostKit.quad_mesh()
			material = FrostKit.glint_material()
		_:
			mesh = FrostKit.quad_mesh()
			material = FrostKit.puff_material()
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	multimesh.instance_count = capacity
	bits.multimesh = multimesh
	bits.material_override = material
	bits.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bits._capacity = capacity
	bits._pos.resize(capacity)
	bits._vel.resize(capacity)
	bits._size.resize(capacity)
	bits._axis.resize(capacity)
	bits._angle.resize(capacity)
	bits._spin.resize(capacity)
	bits._age.resize(capacity)
	bits._life.resize(capacity)
	bits._seed.resize(capacity)
	bits._violet.resize(capacity)
	for i in capacity:
		multimesh.set_instance_transform(i, Transform3D(HIDDEN_BASIS, Vector3.ZERO))
	return bits


## A burst in world space, added to `world` (positions are global).
static func world_burst(world: Node, bit_kind: Kind, capacity: int, glass := true) -> FrostBits:
	var bits := make(bit_kind, capacity, glass)
	bits.top_level = true
	world.add_child(bits)
	bits.global_transform = Transform3D.IDENTITY
	return bits


## Adds one bit `delay` seconds from now. `size` scales the mesh (chunks:
## per axis; sparkles and puffs: x is the diameter).
func add(at: Vector3, velocity: Vector3, size: Vector3, life: float, delay := 0.0, violet := 0.0) -> void:
	var i := _next
	if _life[i] > 0.0 and not pooled:
		return  # full
	_next = (_next + 1) % _capacity
	_pos[i] = at
	_vel[i] = velocity
	_size[i] = size
	_life[i] = maxf(life, 0.01)
	_age[i] = -delay
	_axis[i] = FrostKit.random_direction()
	_angle[i] = randf() * TAU
	_spin[i] = randf_range(-spin, spin)
	_seed[i] = randf()
	_violet[i] = violet
	_added = true


func _process(delta: float) -> void:
	var instances := multimesh
	var alive := 0
	var damp := maxf(1.0 - drag * delta, 0.0)
	for i in _capacity:
		var life := _life[i]
		if life <= 0.0:
			continue
		var age := _age[i] + delta
		_age[i] = age
		if age < 0.0:
			alive += 1
			continue
		if age >= life:
			_life[i] = 0.0
			instances.set_instance_transform(i, Transform3D(HIDDEN_BASIS, _pos[i]))
			continue
		alive += 1
		var t := age / life
		var velocity := _vel[i]
		velocity.y -= gravity * delta
		velocity *= damp
		var at := _pos[i] + velocity * delta
		var size := _size[i]
		match kind:
			Kind.CHUNK:
				var half := size.y * 0.35
				if at.y < floor_y + half and velocity.y < 0.0:
					at.y = floor_y + half
					velocity = Vector3(velocity.x * 0.55, -velocity.y * bounce, velocity.z * 0.55)
					_spin[i] *= 0.6
				var crumble := smoothstep(0.62, 1.0, t)
				var basis := Basis(_axis[i], _angle[i] + _spin[i] * age) * Basis.from_scale(size * (1.0 - 0.3 * crumble))
				instances.set_instance_transform(i, Transform3D(basis, at))
				instances.set_instance_custom_data(i, Color(crumble * 1.02, clampf(1.0 - age / 0.07, 0.0, 1.0), _violet[i], _seed[i]))
			Kind.SPARKLE:
				var twinkle := 0.55 + 0.45 * sin(age * 34.0 + _seed[i] * TAU)
				var fade := (1.0 - t * t) * clampf(age / 0.05, 0.0, 1.0)
				instances.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * size.x * twinkle), at))
				instances.set_instance_custom_data(i, Color(fade, _seed[i] * TAU + age * 1.5, _violet[i], _seed[i]))
			_:
				var grow := 1.0 + (swell - 1.0) * (1.0 - (1.0 - t) * (1.0 - t))
				var fade_in := clampf(age / 0.06, 0.0, 1.0)
				instances.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * size.x * grow), at))
				instances.set_instance_custom_data(i, Color(t, _seed[i], fade_in, _violet[i]))
		_vel[i] = velocity
		_pos[i] = at
	if alive == 0 and _added and not pooled:
		queue_free()
