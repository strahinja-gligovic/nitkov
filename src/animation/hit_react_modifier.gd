class_name HitReactModifier
extends SkeletonModifier3D
## Additive reactions to blows, layered on top of whatever clip is playing.
## Presentation only.
##   bend    the torso and head bend away from a blow (the head a beat later),
##           on a spring whose feel each blow picks: NORMAL rocks and settles,
##           STIFF snaps and stops dead (frost), HARD throws the body further
##           and rebounds (fire). Even a hyperarmored heavy wind-up visibly
##           takes the hit, and a hit from the side rocks you sideways.
##   jitter  electric spasms (lightning): the body locks rigid, back arched
##           and arms flung out, while every joint twitches to a new angle
##           about 30 times a second, for as long as a bolt's jolt lasts (a
##           stun's spasms are AnimDirector.ShockJitter's).
##   shiver  a short, fine tremble through the spine and arms (frost).

enum Feel { NORMAL, STIFF, HARD }

## Bones that bend, base to tip, and their share of the bend.
var bones: Array[StringName] = []
var shares: Array[float] = []
## The head gets a second, slower spring for overlap.
var head_bone := &""
## Radians of bend at full strength (1.0).
var max_angle := deg_to_rad(22.0)

## Spasm bones: [name, twitch amplitude (radians), rigid pose (a skeleton-space
## rotation vector: the body faces +Z, its right is -X)]. The rigid pose
## arches the back, throws the head back and hunches the shoulders.
const JITTER_BONES := [
	[&"spine_01", 0.05, Vector3(-0.07, 0.0, 0.0)],
	[&"spine_02", 0.05, Vector3(-0.08, 0.0, 0.0)],
	[&"spine_03", 0.06, Vector3(-0.07, 0.0, 0.0)],
	[&"neck_01", 0.08, Vector3(-0.08, 0.0, 0.0)],
	[&"Head", 0.13, Vector3(-0.16, 0.0, 0.0)],
	[&"clavicle_l", 0.07, Vector3(0.0, 0.0, 0.2)],
	[&"clavicle_r", 0.07, Vector3(0.0, 0.0, -0.2)],
	[&"upperarm_l", 0.2, Vector3(0.0, 0.0, 0.2)],
	[&"upperarm_r", 0.2, Vector3(0.0, 0.0, -0.2)],
	[&"lowerarm_l", 0.24, Vector3(0.0, 0.0, 0.08)],
	[&"lowerarm_r", 0.24, Vector3(0.0, 0.0, -0.08)],
	[&"hand_l", 0.32, Vector3.ZERO],
	[&"hand_r", 0.32, Vector3.ZERO],
	[&"thigh_l", 0.05, Vector3.ZERO],
	[&"thigh_r", 0.05, Vector3.ZERO],
	[&"calf_l", 0.07, Vector3.ZERO],
	[&"calf_r", 0.07, Vector3.ZERO],
]
## The shiver's bones and their tremble amplitude (radians).
const SHIVER_BONES := [[&"spine_02", 0.035], [&"spine_03", 0.04], [&"Head", 0.06],
		[&"upperarm_l", 0.07], [&"upperarm_r", 0.07]]
## New spasm angles this many times a second.
const JITTER_RATE := 30.0

var _offset := Vector3.ZERO
var _velocity := Vector3.ZERO
var _head_offset := Vector3.ZERO
var _head_velocity := Vector3.ZERO
## The bend spring's current feel: torso omega/zeta, head omega/zeta.
var _spring := Vector4(20.0, 0.5, 12.0, 0.45)
var _jitter_left := 0.0
var _jitter_amount := 0.0
var _jitter_weight := 0.0
var _jitter_clock := 0.0
var _twitches: Array[Vector3] = []
var _shiver_left := 0.0
var _shiver_length := 0.0
var _shiver_amount := 0.0
var _time := 0.0


func setup(bend_bones: Array[StringName], bend_shares: Array[float], head: StringName) -> void:
	bones = bend_bones
	shares = bend_shares
	head_bone = head


## Kick the springs. `skeleton_dir` is the hit's push direction in skeleton
## space; `strength` ~0.4 for lights, ~1 for heavies and breaks.
func impulse(skeleton_dir: Vector3, strength: float, feel := Feel.NORMAL) -> void:
	var flat := Vector3(skeleton_dir.x, 0.0, skeleton_dir.z)
	if flat.length() < 0.001:
		return
	match feel:
		Feel.STIFF:
			# fast and heavily damped: out and back in a blink, no sway
			_spring = Vector4(38.0, 0.95, 26.0, 0.9)
			_velocity += flat.normalized() * strength * 24.0
			_head_velocity += flat.normalized() * strength * 16.0
		Feel.HARD:
			# a bigger throw that rebounds once
			_spring = Vector4(17.0, 0.42, 11.0, 0.4)
			_velocity += flat.normalized() * strength * 11.5
			_head_velocity += flat.normalized() * strength * 9.0
		_:
			_spring = Vector4(20.0, 0.5, 12.0, 0.45)
			_velocity += flat.normalized() * strength * 9.0
			_head_velocity += flat.normalized() * strength * 6.0


## Electric spasms for `seconds` at `amount` (1 = a full stun). A longer or
## stronger shock replaces a weaker one.
func jitter(seconds: float, amount := 1.0) -> void:
	if _jitter_left <= 0.0:
		_jitter_amount = 0.0
	_jitter_left = maxf(_jitter_left, seconds)
	_jitter_amount = maxf(_jitter_amount, amount)
	_jitter_clock = 1.0  # new angles right away


## A fine tremble through the spine and arms that dies out over `seconds`.
func shiver(seconds: float, amount := 1.0) -> void:
	_shiver_length = maxf(seconds, 0.05)
	_shiver_left = _shiver_length
	_shiver_amount = amount


## 0..1: how much the body is locked in a spasm right now.
func jitter_weight() -> float:
	return _jitter_weight


func reset() -> void:
	_offset = Vector3.ZERO
	_velocity = Vector3.ZERO
	_head_offset = Vector3.ZERO
	_head_velocity = Vector3.ZERO
	_jitter_left = 0.0
	_jitter_weight = 0.0
	_shiver_left = 0.0


func _process_modification_with_delta(delta: float) -> void:
	if delta > 0.0:
		_advance(delta)
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	for i in bones.size():
		_bend(skeleton, bones[i], _offset, shares[i])
	if head_bone != &"":
		_bend(skeleton, head_bone, _head_offset, 0.5)
	if _jitter_weight > 0.001:
		_apply_jitter(skeleton)
	if _shiver_left > 0.0:
		_apply_shiver(skeleton)


func _advance(delta: float) -> void:
	_time += delta
	# springs in small steps (the stiff feel would ring at low frame rates)
	var left := minf(delta, 0.1)
	while left > 0.0:
		var dt := minf(left, 1.0 / 240.0)
		left -= dt
		_velocity += (-_spring.x * _spring.x * _offset - 2.0 * _spring.y * _spring.x * _velocity) * dt
		_offset += _velocity * dt
		_head_velocity += (-_spring.z * _spring.z * _head_offset - 2.0 * _spring.w * _spring.z * _head_velocity) * dt
		_head_offset += _head_velocity * dt
	# the spasm locks in within a frame or two and lets go over ~0.12 s
	_jitter_left = maxf(_jitter_left - delta, 0.0)
	var target := _jitter_amount if _jitter_left > 0.0 else 0.0
	_jitter_weight = move_toward(_jitter_weight, target, delta / (0.03 if target > _jitter_weight else 0.12))
	if _jitter_weight > 0.0:
		_jitter_clock += delta
		if _jitter_clock >= 1.0 / JITTER_RATE:
			_jitter_clock = 0.0
			_twitches.resize(JITTER_BONES.size())
			for i in JITTER_BONES.size():
				var axis := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
				_twitches[i] = axis.normalized() * randf_range(0.35, 1.0) if axis.length() > 0.01 else Vector3.ZERO
	_shiver_left = maxf(_shiver_left - delta, 0.0)


## Rotates a bone so its top tips along `offset` (skeleton space), by
## |offset| * max_angle * share, on top of the animated pose.
func _bend(skeleton: Skeleton3D, bone_name: StringName, offset: Vector3, share: float) -> void:
	var angle := clampf(offset.length(), 0.0, 1.5) * max_angle * share
	if angle < 0.0005:
		return
	var bone := skeleton.find_bone(bone_name)
	if bone < 0:
		return
	var axis_skeleton := Vector3.UP.cross(offset.normalized())
	var global_basis := skeleton.get_bone_global_pose(bone).basis.orthonormalized()
	var axis_local := (global_basis.inverse() * axis_skeleton).normalized()
	skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone) * Quaternion(axis_local, angle))


func _apply_jitter(skeleton: Skeleton3D) -> void:
	if _twitches.size() != JITTER_BONES.size():
		return
	for i in JITTER_BONES.size():
		var entry: Array = JITTER_BONES[i]
		var turn: Vector3 = (entry[2] as Vector3 + _twitches[i] * (entry[1] as float)) * _jitter_weight
		_turn(skeleton, entry[0], turn)


func _apply_shiver(skeleton: Skeleton3D) -> void:
	var fade := _shiver_left / _shiver_length
	var strength := _shiver_amount * fade * fade
	for i in SHIVER_BONES.size():
		var entry: Array = SHIVER_BONES[i]
		var phase := _time * 88.0 + i * 1.9
		var turn := Vector3(sin(phase), 0.0, cos(phase * 1.3)) * (entry[1] as float) * strength
		_turn(skeleton, entry[0], turn)


## Turns a bone by a skeleton-space rotation vector, on top of its pose.
func _turn(skeleton: Skeleton3D, bone_name: StringName, rotation_vector: Vector3) -> void:
	var angle := rotation_vector.length()
	if angle < 0.0005:
		return
	var bone := skeleton.find_bone(bone_name)
	if bone < 0:
		return
	var global_basis := skeleton.get_bone_global_pose(bone).basis.orthonormalized()
	var turn := Basis(rotation_vector / angle, angle)
	var local := Quaternion(global_basis.inverse() * turn * global_basis)
	skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone) * local)
