class_name StrideTwistModifier
extends SkeletonModifier3D
## Directional running from forward-only clips. Fighters always face their
## aim, but the clip libraries only run forward, so the legs are turned
## toward where the body is actually going: the pelvis yaws by `leg_yaw` and
## the spine twists back by the same amount, spread over its bones, so the
## chest stays on the aim. Backpedalling plays the runs in reverse with the
## hips turned toward the backward diagonal (AnimDirector decides both).

## Target hip yaw in radians (+ = legs toward the right). Set every frame.
var leg_yaw := 0.0
## 0..1: fades the whole effect (standing still, mid-swing...).
var amount := 0.0
var pelvis_bone := &"pelvis"
## Spine bones, bottom to top, and the share of the counter-twist each takes.
var spine_bones: Array[StringName] = [&"spine_01", &"spine_02", &"spine_03"]
var spine_shares: Array[float] = [0.4, 0.35, 0.25]

var _yaw := 0.0
var _yaw_velocity := 0.0


func reset() -> void:
	_yaw = 0.0
	_yaw_velocity = 0.0


func _process_modification_with_delta(delta: float) -> void:
	if delta > 0.0:
		# a quick, slightly soft spring: the hips swing round, they don't snap
		var target := leg_yaw * amount
		_yaw_velocity += (225.0 * (target - _yaw) - 27.0 * _yaw_velocity) * delta
		_yaw += _yaw_velocity * delta
	if absf(_yaw) < 0.002:
		return
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	# the character's up, in skeleton space: from the pelvis to the head at rest
	_twist(skeleton, pelvis_bone, -_yaw)
	for i in spine_bones.size():
		_twist(skeleton, spine_bones[i], _yaw * spine_shares[i])


## Turns a bone about the skeleton's vertical axis, on top of its pose.
## (Positive angles turn counter-clockwise seen from above, i.e. to the left.)
func _twist(skeleton: Skeleton3D, bone_name: StringName, angle: float) -> void:
	var bone := skeleton.find_bone(bone_name)
	if bone < 0:
		return
	var global_basis := skeleton.get_bone_global_pose(bone).basis.orthonormalized()
	var axis_local := (global_basis.inverse() * Vector3.UP).normalized()
	skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone) * Quaternion(axis_local, angle))
