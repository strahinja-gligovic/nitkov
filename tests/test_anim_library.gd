extends GutTest
## AnimLibrary's clip surgery: retargeting between rest poses and splicing.

var _skeleton: Skeleton3D


func before_each() -> void:
	_skeleton = Skeleton3D.new()
	_add("root", -1, Transform3D.IDENTITY)
	_add("pelvis", 0, Transform3D(Basis(), Vector3(0, 1, 0)))
	_add("spine_01", 1, Transform3D(Basis(Vector3.RIGHT, 0.2), Vector3(0, 0.2, 0)))
	_add("Head", 2, Transform3D(Basis(Vector3.RIGHT, -0.1), Vector3(0, 0.5, 0)))


func after_each() -> void:
	_skeleton.free()


func test_retarget_to_the_same_rest_changes_nothing() -> void:
	var clip := _wave()
	var rest := _global_rests(_skeleton)
	var out := AnimLibrary.retarget(clip, rest, 1.0, _skeleton, {})
	var track := out.find_track(NodePath("Armature/Skeleton3D:spine_01"), Animation.TYPE_ROTATION_3D)
	assert_true(track >= 0)
	var q: Quaternion = out.rotation_track_interpolate(track, 0.5)
	var original: Quaternion = clip.rotation_track_interpolate(0, 0.5)
	assert_almost_eq(q.angle_to(original), 0.0, 0.002)


func test_retarget_keeps_the_global_motion_on_a_different_rest() -> void:
	# the source was authored on a spine bent 0.5 rad further forward
	var source_rest := _global_rests(_skeleton)
	var bend := Quaternion(Vector3.RIGHT, 0.5)
	source_rest["spine_01"] = (source_rest["spine_01"] as Quaternion) * bend
	source_rest["Head"] = (source_rest["Head"] as Quaternion) * bend
	var clip := Animation.new()
	clip.length = 1.0
	var spine := clip.add_track(Animation.TYPE_ROTATION_3D)
	clip.track_set_path(spine, NodePath("Armature/Skeleton3D:spine_01"))
	# at rest in the source = the source's rest rotation
	clip.rotation_track_insert_key(spine, 0.0, _skeleton.get_bone_rest(2).basis.get_rotation_quaternion() * bend)
	var out := AnimLibrary.retarget(clip, source_rest, 1.0, _skeleton, {})
	var q: Quaternion = out.rotation_track_interpolate(out.find_track(NodePath("Armature/Skeleton3D:spine_01"), Animation.TYPE_ROTATION_3D), 0.0)
	assert_almost_eq(q.angle_to(_skeleton.get_bone_rest(2).basis.get_rotation_quaternion()), 0.0, 0.002,
			"the source's rest pose becomes the target's rest pose")


func test_retarget_renames_and_drops_unknown_bones() -> void:
	var clip := Animation.new()
	clip.length = 1.0
	for bone_name in ["head", "head_leaf"]:
		var track := clip.add_track(Animation.TYPE_ROTATION_3D)
		clip.track_set_path(track, NodePath("Armature/Skeleton3D:%s" % bone_name))
		clip.rotation_track_insert_key(track, 0.0, Quaternion.IDENTITY)
	var rest := _global_rests(_skeleton)
	rest["head"] = rest["Head"]
	var out := AnimLibrary.retarget(clip, rest, 1.0, _skeleton, {"head": "Head"})
	assert_eq(out.get_track_count(), 1)
	assert_eq(String(out.track_get_path(0)), "Armature/Skeleton3D:Head")


func test_retarget_scales_pelvis_height_and_drops_other_positions() -> void:
	var clip := Animation.new()
	clip.length = 1.0
	for bone_name in ["pelvis", "spine_01"]:
		var track := clip.add_track(Animation.TYPE_POSITION_3D)
		clip.track_set_path(track, NodePath("Armature/Skeleton3D:%s" % bone_name))
		clip.position_track_insert_key(track, 0.0, Vector3(0, 2, 0))
	var out := AnimLibrary.retarget(clip, _global_rests(_skeleton), 2.0, _skeleton, {})
	assert_eq(out.get_track_count(), 1, "spine keeps its own length")
	assert_almost_eq(out.position_track_interpolate(0, 0.0), Vector3(0, 1, 0), Vector3.ONE * 0.0001,
			"source pelvis 2 m high, ours 1 m: halved")


func test_splice_flows_from_one_clip_into_the_other() -> void:
	var a := _constant(Quaternion(Vector3.UP, 0.0), 1.0)
	var b := _constant(Quaternion(Vector3.UP, 1.0), 2.0)
	var out := AnimLibrary.splice(a, 0.5, b, 0.2, 1.2, 0.1)
	assert_almost_eq(out.length, 0.4 + 1.0, 0.0001)
	var track := out.find_track(NodePath("Armature/Skeleton3D:spine_01"), Animation.TYPE_ROTATION_3D)
	assert_almost_eq(out.rotation_track_interpolate(track, 0.2).get_angle(), 0.0, 0.001, "first clip before the blend")
	assert_almost_eq(out.rotation_track_interpolate(track, 0.9).get_angle(), 1.0, 0.001, "second clip after it")
	var mid := out.rotation_track_interpolate(track, 0.45).get_angle()
	assert_between(mid, 0.05, 0.95, "crossfaded in between")


func _add(bone_name: String, parent: int, rest: Transform3D) -> void:
	var index := _skeleton.get_bone_count()
	_skeleton.add_bone(bone_name)
	_skeleton.set_bone_parent(index, parent)
	_skeleton.set_bone_rest(index, rest)


func _global_rests(skeleton: Skeleton3D) -> Dictionary:
	var out := {}
	for bone in skeleton.get_bone_count():
		out[skeleton.get_bone_name(bone)] = skeleton.get_bone_global_rest(bone).basis.get_rotation_quaternion()
	return out


func _wave() -> Animation:
	var clip := Animation.new()
	clip.length = 1.0
	var track := clip.add_track(Animation.TYPE_ROTATION_3D)
	clip.track_set_path(track, NodePath("Armature/Skeleton3D:spine_01"))
	clip.rotation_track_insert_key(track, 0.0, Quaternion(Vector3.RIGHT, 0.2))
	clip.rotation_track_insert_key(track, 1.0, Quaternion(Vector3.RIGHT, 0.9))
	return clip


func _constant(q: Quaternion, length: float) -> Animation:
	var clip := Animation.new()
	clip.length = length
	var track := clip.add_track(Animation.TYPE_ROTATION_3D)
	clip.track_set_path(track, NodePath("Armature/Skeleton3D:spine_01"))
	clip.rotation_track_insert_key(track, 0.0, q)
	clip.rotation_track_insert_key(track, length, q)
	return clip
