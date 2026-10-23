class_name BreathModifier
extends SkeletonModifier3D
## Slow, additive breathing on the chest (and a hint in the shoulders), so a
## fighter standing still is never a statue. When winded it breathes harder
## and faster and the head droops a little. Reads stamina; writes only bones.

var chest_bone := &""
var head_bone := &""
## 0 = fresh, 1 = completely winded; set by FighterVisual every frame.
var winded := 0.0
## Fades breathing out during big actions.
var amount := 1.0

var _phase := 0.0


func _process_modification_with_delta(delta: float) -> void:
	var rate := lerpf(0.3, 0.55, winded)
	_phase = fmod(_phase + delta * TAU * rate, TAU)
	var skeleton := get_skeleton()
	if skeleton == null or amount <= 0.0:
		return
	var depth := deg_to_rad(lerpf(1.6, 4.0, winded)) * amount
	_pitch(skeleton, chest_bone, sin(_phase) * depth)
	_pitch(skeleton, head_bone, deg_to_rad(5.0) * winded * amount - sin(_phase) * depth * 0.5)


## Nods a bone around the character's left-right axis.
func _pitch(skeleton: Skeleton3D, bone_name: StringName, angle: float) -> void:
	var bone := skeleton.find_bone(bone_name)
	if bone < 0 or absf(angle) < 0.00005:
		return
	var global_basis := skeleton.get_bone_global_pose(bone).basis.orthonormalized()
	var axis_local := (global_basis.inverse() * Vector3.RIGHT).normalized()
	skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone) * Quaternion(axis_local, angle))
