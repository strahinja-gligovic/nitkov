class_name WindParticles
extends MultiMeshInstance3D
## A handful of wind-blown bits drawn as one MultiMesh
## (wind_particle.gdshader): cel dust puffs, tumbling leaves and stone chips,
## glowing motes. They're simulated here on the CPU in world space (gravity,
## drag toward the ambient `wind`, leaf flutter, an optional floor to settle
## on), and the node frees itself once the last one has died. Cosmetic only.

enum Kind { DUST, LEAF, CHIP, MOTE }

const SHADER := preload("res://src/vfx/wind/wind_particle.gdshader")
## How hard gravity pulls each kind: dust drifts up a little, leaves float
## down, chips drop, motes hang.
const WEIGHT: Array[float] = [-0.05, 0.14, 1.0, 0.0]
## Air drag per kind (1/s): dust and leaves lose their speed quickly.
const DRAG: Array[float] = [3.0, 2.2, 0.5, 2.5]

static var _material: ShaderMaterial
static var _quad: QuadMesh

var gravity := 9.8
## World height to settle on (-INF: no floor).
var floor_y := -INF
## The air everything drifts toward (m/s).
var wind := Vector3.ZERO
## Seconds to stay around even with nothing alive (more may be emitted).
var hold := 0.0

var _kind := PackedInt32Array()
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _axis := PackedVector3Array()
var _angle := PackedFloat32Array()
var _spin := PackedFloat32Array()
var _size := PackedFloat32Array()
var _grow := PackedFloat32Array()
var _age := PackedFloat32Array()
var _life := PackedFloat32Array()
var _seed := PackedFloat32Array()


## An empty system under `parent` with room for `capacity` particles.
static func spawn(parent: Node, capacity: int) -> WindParticles:
	var bits := WindParticles.new()
	bits.multimesh = make_multimesh(capacity)
	bits.material_override = shared_material()
	bits.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bits.extra_cull_margin = 2.0
	bits.top_level = true
	parent.add_child(bits)
	bits.global_transform = Transform3D.IDENTITY
	return bits


## A MultiMesh of quads with custom data, for wind_particle.gdshader.
static func make_multimesh(capacity: int) -> MultiMesh:
	if _quad == null:
		_quad = QuadMesh.new()
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = _quad
	multimesh.instance_count = capacity
	multimesh.visible_instance_count = 0
	return multimesh


static func shared_material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
	return _material


## The per-instance data the shader reads: kind, life 0..1, random, alpha.
static func custom(kind: Kind, life: float, random: float, alpha: float) -> Color:
	return Color(float(kind), life, random, alpha)


## Adds one particle at `at` (world) moving at `velocity`. `spin` is in
## radians per second around a random axis; `grow` is how much bigger it
## gets by the end of its life (dust billows).
func emit(kind: Kind, at: Vector3, velocity: Vector3, size: float, life: float, spin := 0.0, grow := 0.0) -> void:
	if _kind.size() >= multimesh.instance_count:
		return
	_kind.append(kind)
	_pos.append(at)
	_vel.append(velocity)
	_axis.append(Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized())
	_angle.append(randf() * TAU)
	_spin.append(spin * (1.0 if randf() < 0.5 else -1.0))
	_size.append(size)
	_grow.append(grow)
	_age.append(0.0)
	_life.append(maxf(life, 0.05))
	_seed.append(randf())


func _process(delta: float) -> void:
	hold -= delta
	var alive := 0
	for i in _kind.size():
		if _age[i] >= _life[i]:
			continue
		_age[i] += delta
		var kind := _kind[i]
		var velocity := _vel[i] + Vector3.DOWN * gravity * WEIGHT[kind] * delta
		velocity = wind + (velocity - wind) * exp(-DRAG[kind] * delta)
		var at := _pos[i] + velocity * delta
		if kind == Kind.LEAF:
			# leaves see-saw as they fall
			var sway := Vector3(_axis[i].z, 0.0, -_axis[i].x).normalized()
			at += sway * sin(_age[i] * 7.0 + _seed[i] * 20.0) * 1.4 * delta
		if at.y < floor_y + 0.03:
			at.y = floor_y + 0.03
			velocity = Vector3(velocity.x, 0.0, velocity.z) * 0.4
			_spin[i] *= 0.5
		_pos[i] = at
		_vel[i] = velocity
		_angle[i] += _spin[i] * delta
		var life := clampf(_age[i] / _life[i], 0.0, 1.0)
		var size := _size[i] * (1.0 + _grow[i] * life)
		var alpha := 1.0
		match kind:
			Kind.DUST:
				alpha = minf(life * 8.0, 1.0) * (1.0 - smoothstep(0.75, 1.0, life))
			Kind.MOTE:
				alpha = (1.0 - life) * (0.7 + 0.3 * sin(_age[i] * 40.0 + _seed[i] * 9.0))
			_:
				alpha = 1.0 - smoothstep(0.7, 1.0, life)
		var basis := Basis(_axis[i], _angle[i]).scaled(Vector3.ONE * size)
		multimesh.set_instance_transform(alive, Transform3D(basis, at))
		multimesh.set_instance_custom_data(alive, custom(kind, life, _seed[i], alpha))
		alive += 1
	multimesh.visible_instance_count = alive
	if alive == 0 and hold <= 0.0:
		queue_free()
