extends GutTest
## The procedural layers really move the bones of an assembled character.
## Modifier results exist only while the skeleton holds its final pose, so
## the pose is read from its skeleton_updated signal.

var rig: CharacterRig
var _final := {}


func before_each() -> void:
	rig = CharacterRig.build(GameData.characters[&"warden"])
	add_child_autofree(rig)
	rig.skeleton.skeleton_updated.connect(_capture)


func test_stride_twist_turns_the_hips_and_keeps_the_chest() -> void:
	await _settle()
	var hips_before := _yaw(&"pelvis")
	var chest_before := _yaw(&"spine_03")
	var stride := StrideTwistModifier.new()
	rig.skeleton.add_child(stride)
	stride.leg_yaw = 1.0
	stride.amount = 1.0
	await _settle(90)
	assert_almost_eq(absf(wrapf(_yaw(&"pelvis") - hips_before, -PI, PI)), 1.0, 0.1, "the hips turn by the leg yaw")
	assert_almost_eq(wrapf(_yaw(&"spine_03") - chest_before, -PI, PI), 0.0, 0.1, "the chest stays on the aim")


func test_lean_tips_the_chest_forward_and_keeps_the_feet() -> void:
	await _settle()
	var head_before: Vector3 = _final[&"Head"].origin
	var foot_before: Vector3 = _final[&"ball_l"].origin
	var lean := LeanModifier.new()
	rig.skeleton.add_child(lean)
	lean.pitch = 0.4
	await _settle()
	var head: Vector3 = _final[&"Head"].origin
	assert_gt(head.z - head_before.z, 0.15, "the head moves forward (+Z in skeleton space)")
	assert_almost_eq(_final[&"ball_l"].origin, foot_before, Vector3.ONE * 0.001, "the feet stay put")


## Keeps the skeleton updating (as an animation would) for some frames.
func _settle(frames := 3) -> void:
	for i in frames:
		var pelvis := rig.skeleton.find_bone("pelvis")
		rig.skeleton.set_bone_pose_rotation(pelvis, rig.skeleton.get_bone_pose_rotation(pelvis))
		rig.skeleton.advance(1.0 / 60.0)
		await wait_frames(1)


func _capture() -> void:
	for bone_name in [&"pelvis", &"spine_03", &"Head", &"ball_l"]:
		_final[bone_name] = rig.skeleton.get_bone_global_pose(rig.skeleton.find_bone(bone_name))


func _yaw(bone_name: StringName) -> float:
	var forward := (_final[bone_name] as Transform3D).basis * Vector3.BACK
	return atan2(forward.x, forward.z)
