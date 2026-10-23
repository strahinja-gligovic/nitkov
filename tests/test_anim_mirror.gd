extends GutTest
## AnimMirror: a mirrored clip puts every joint where its twin was, reflected.

var _skeleton: Skeleton3D


func before_each() -> void:
	_skeleton = Skeleton3D.new()
	_bone("root", -1, Transform3D.IDENTITY)
	_bone("spine", 0, Transform3D(Basis(), Vector3(0, 1, 0)))
	# deliberately different local axes on each side, like real rigs
	_bone("upperarm_l", 1, Transform3D(Basis(Vector3.BACK, deg_to_rad(-80.0)), Vector3(0.2, 0.4, 0)))
	_bone("upperarm_r", 1, Transform3D(Basis(Vector3.BACK, deg_to_rad(80.0)) * Basis(Vector3.RIGHT, PI), Vector3(-0.2, 0.4, 0)))
	_bone("hand_l", 2, Transform3D(Basis(), Vector3(0, 0.6, 0)))
	_bone("hand_r", 3, Transform3D(Basis(), Vector3(0, -0.6, 0)))


func after_each() -> void:
	_skeleton.free()


func test_twin_names() -> void:
	assert_eq(AnimMirror.twin_name("upperarm_l"), "upperarm_r")
	assert_eq(AnimMirror.twin_name("hand_r"), "hand_l")
	assert_eq(AnimMirror.twin_name("spine"), "spine")


func test_rest_skeleton_is_symmetric_as_built() -> void:
	var rest := AnimMirror._rest_globals(_skeleton)
	var left := rest[_skeleton.find_bone("hand_l")].origin
	var right := rest[_skeleton.find_bone("hand_r")].origin
	assert_almost_eq(left, Vector3(-right.x, right.y, right.z), Vector3.ONE * 0.0001)


func test_raised_left_arm_becomes_raised_right_arm() -> void:
	var clip := Animation.new()
	clip.length = 1.0
	var arm := clip.add_track(Animation.TYPE_ROTATION_3D)
	clip.track_set_path(arm, NodePath("Skeleton3D:upperarm_l"))
	var rest_q := _skeleton.get_bone_rest(2).basis.get_rotation_quaternion()
	clip.rotation_track_insert_key(arm, 0.0, rest_q)
	clip.rotation_track_insert_key(arm, 1.0, rest_q * Quaternion(Vector3.BACK, deg_to_rad(60.0)) * Quaternion(Vector3.UP, 0.7))
	var spine := clip.add_track(Animation.TYPE_ROTATION_3D)
	clip.track_set_path(spine, NodePath("Skeleton3D:spine"))
	clip.rotation_track_insert_key(spine, 0.0, Quaternion.IDENTITY)
	clip.rotation_track_insert_key(spine, 1.0, Quaternion(Vector3.UP, 0.5) * Quaternion(Vector3.BACK, 0.2))

	var mirrored := AnimMirror.mirror(clip, _skeleton)
	for t in [0.0, 0.5, 1.0]:
		var before := _joint_positions(clip, t)
		var after := _joint_positions(mirrored, t)
		for bone_name in ["spine", "upperarm_l", "upperarm_r", "hand_l", "hand_r"]:
			var source: Vector3 = before[AnimMirror.twin_name(bone_name)]
			assert_almost_eq(after[bone_name], Vector3(-source.x, source.y, source.z), Vector3.ONE * 0.0005,
					"%s at %.1f" % [bone_name, t])


func test_mirroring_twice_gives_the_original_back() -> void:
	var clip := Animation.new()
	clip.length = 1.0
	var arm := clip.add_track(Animation.TYPE_ROTATION_3D)
	clip.track_set_path(arm, NodePath("Skeleton3D:upperarm_r"))
	var rest_q := _skeleton.get_bone_rest(3).basis.get_rotation_quaternion()
	clip.rotation_track_insert_key(arm, 0.0, rest_q)
	clip.rotation_track_insert_key(arm, 1.0, rest_q * Quaternion(Vector3.RIGHT, 1.1))
	var twice := AnimMirror.mirror(AnimMirror.mirror(clip, _skeleton), _skeleton)
	var before := _joint_positions(clip, 1.0)
	var after := _joint_positions(twice, 1.0)
	for bone_name: String in before:
		assert_almost_eq(after[bone_name], before[bone_name], Vector3.ONE * 0.0005, bone_name)


func _bone(bone_name: String, parent: int, rest: Transform3D) -> void:
	var index := _skeleton.get_bone_count()
	_skeleton.add_bone(bone_name)
	_skeleton.set_bone_parent(index, parent)
	_skeleton.set_bone_rest(index, rest)


func _joint_positions(clip: Animation, t: float) -> Dictionary:
	var tracks := AnimMirror._bone_tracks(clip, _skeleton)
	var globals := AnimMirror._globals(_skeleton, AnimMirror._sample(clip, _skeleton, tracks, t))
	var out := {}
	for bone in _skeleton.get_bone_count():
		out[_skeleton.get_bone_name(bone)] = globals[bone].origin
	return out
