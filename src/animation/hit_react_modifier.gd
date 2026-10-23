class_name HitReactModifier
extends SkeletonModifier3D
## Additive, spring-driven bend of the torso and head along the direction a
## hit came from, layered on top of whatever clip is playing. Even a
## hyperarmored heavy wind-up visibly takes the hit, and a hit from the side
## rocks you sideways instead of always backward. Presentation only.

## Bones that bend, base to tip, and their share of the bend.
var bones: Array[StringName] = []
var shares: Array[float] = []
## The head gets a second, slower spring for overlap.
var head_bone := &""
## Radians of bend at full strength (1.0).
var max_angle := deg_to_rad(22.0)

var _offset := Vector3.ZERO
var _velocity := Vector3.ZERO
var _head_offset := Vector3.ZERO
var _head_velocity := Vector3.ZERO


func setup(bend_bones: Array[StringName], bend_shares: Array[float], head: StringName) -> void:
	bones = bend_bones
	shares = bend_shares
	head_bone = head


## Kick the springs. `skeleton_dir` is the hit's push direction in skeleton
## space; `strength` ~0.4 for lights, ~1 for heavies and breaks.
func impulse(skeleton_dir: Vector3, strength: float) -> void:
	var flat := Vector3(skeleton_dir.x, 0.0, skeleton_dir.z)
	if flat.length() < 0.001:
		return
	_velocity += flat.normalized() * strength * 9.0
	_head_velocity += flat.normalized() * strength * 6.0


func reset() -> void:
	_offset = Vector3.ZERO
	_velocity = Vector3.ZERO
	_head_offset = Vector3.ZERO
	_head_velocity = Vector3.ZERO


func _process_modification_with_delta(delta: float) -> void:
	if delta > 0.0:
		# torso: omega 20, zeta 0.5 (peaks ~80 ms in); head: omega 12, zeta 0.45
		_velocity += (-400.0 * _offset - 20.0 * _velocity) * delta
		_offset += _velocity * delta
		_head_velocity += (-144.0 * _head_offset - 10.8 * _head_velocity) * delta
		_head_offset += _head_velocity * delta
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	for i in bones.size():
		_bend(skeleton, bones[i], _offset, shares[i])
	if head_bone != &"":
		_bend(skeleton, head_bone, _head_offset, 0.5)


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
