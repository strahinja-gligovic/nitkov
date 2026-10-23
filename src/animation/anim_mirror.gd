class_name AnimMirror
extends RefCounted
## Bakes a left/right mirrored copy of a skeletal clip, e.g. a right-handed
## throw played from the left (gauntlet) hand. It works in skeleton space, so
## it doesn't care how each bone's local axes happen to be oriented: at every
## key time it poses the bones, reflects each bone's global transform across
## the body's mid-plane onto its opposite-side twin (`_l` <-> `_r`), and
## converts back to local poses.


## Returns the mirrored clip. `skeleton` supplies bone names, parents and
## rests (it is only read, never posed).
static func mirror(source: Animation, skeleton: Skeleton3D) -> Animation:
	var count := skeleton.get_bone_count()
	var rest_global := _rest_globals(skeleton)
	var reflect := _reflection(skeleton, rest_global)
	var twin := PackedInt32Array()
	var correction: Array[Basis] = []
	for bone in count:
		var other := skeleton.find_bone(twin_name(skeleton.get_bone_name(bone)))
		twin.append(other if other >= 0 else bone)
		# maps the twin's (reflected) bone axes onto this bone's own axes
		correction.append(rest_global[twin[bone]].basis.inverse() * reflect * rest_global[bone].basis)

	var tracks := _bone_tracks(source, skeleton)
	var times := _key_times(source, tracks)
	var out := Animation.new()
	out.length = source.length
	out.loop_mode = source.loop_mode
	out.step = source.step
	var written := {}  # bone -> [path, position track, rotation track, scale track]
	for bone: int in tracks:
		var other := twin[bone]
		if not written.has(other):
			var path: String = tracks[bone][0].replace(":" + skeleton.get_bone_name(bone), ":" + skeleton.get_bone_name(other))
			written[other] = [path, -1, -1, -1]

	for t in times:
		var local := _sample(source, skeleton, tracks, t)
		var global := _globals(skeleton, local)
		var mirrored_global: Array[Transform3D] = []
		mirrored_global.resize(count)
		for bone in count:
			var g := global[twin[bone]]
			mirrored_global[bone] = Transform3D(reflect * g.basis * correction[bone], reflect * g.origin)
		for bone: int in written:
			var parent := skeleton.get_bone_parent(bone)
			var pose := mirrored_global[bone] if parent < 0 else mirrored_global[parent].affine_inverse() * mirrored_global[bone]
			_insert(out, written[bone], t, pose, tracks.has(twin[bone]) and tracks[twin[bone]][1] >= 0,
					tracks.has(twin[bone]) and tracks[twin[bone]][3] >= 0)
	return out


## "upperarm_l" <-> "upperarm_r"; names without a side stay as they are.
static func twin_name(bone_name: String) -> String:
	if bone_name.ends_with("_l"):
		return bone_name.left(-2) + "_r"
	if bone_name.ends_with("_r"):
		return bone_name.left(-2) + "_l"
	return bone_name


static func _rest_globals(skeleton: Skeleton3D) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for bone in skeleton.get_bone_count():
		var parent := skeleton.get_bone_parent(bone)
		var rest := skeleton.get_bone_rest(bone)
		out.append(rest if parent < 0 else out[parent] * rest)
	return out


## Reflection across the body's mid-plane, whose normal runs between the
## left and right upper arms (or thighs) at rest.
static func _reflection(skeleton: Skeleton3D, rest_global: Array[Transform3D]) -> Basis:
	var axis := Vector3.RIGHT
	for pair in [["upperarm_l", "upperarm_r"], ["thigh_l", "thigh_r"], ["hand_l", "hand_r"]]:
		var left := skeleton.find_bone(pair[0])
		var right := skeleton.find_bone(pair[1])
		if left >= 0 and right >= 0:
			var across := rest_global[left].origin - rest_global[right].origin
			if across.length() > 0.001:
				axis = across.normalized()
				break
	# I - 2 n n^T, column by column
	return Basis(Vector3.RIGHT - 2.0 * axis.x * axis, Vector3.UP - 2.0 * axis.y * axis,
			Vector3.BACK - 2.0 * axis.z * axis)


## bone -> [track path, position track, rotation track, scale track] (-1 = none)
static func _bone_tracks(source: Animation, skeleton: Skeleton3D) -> Dictionary:
	var out := {}
	for track in source.get_track_count():
		var type := source.track_get_type(track)
		var slot := {Animation.TYPE_POSITION_3D: 1, Animation.TYPE_ROTATION_3D: 2, Animation.TYPE_SCALE_3D: 3}.get(type, 0) as int
		if slot == 0:
			continue
		var path := source.track_get_path(track)
		var bone := skeleton.find_bone(path.get_concatenated_subnames())
		if bone < 0:
			continue
		if not out.has(bone):
			out[bone] = [String(path), -1, -1, -1]
		out[bone][slot] = track
	return out


static func _key_times(source: Animation, tracks: Dictionary) -> PackedFloat32Array:
	var seen := {}
	for bone: int in tracks:
		for slot in range(1, 4):
			var track: int = tracks[bone][slot]
			if track < 0:
				continue
			for key in source.track_get_key_count(track):
				seen[snappedf(source.track_get_key_time(track, key), 0.0001)] = true
	seen[0.0] = true
	seen[snappedf(source.length, 0.0001)] = true
	var times := PackedFloat32Array(seen.keys())
	times.sort()
	return times


static func _sample(source: Animation, skeleton: Skeleton3D, tracks: Dictionary, t: float) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for bone in skeleton.get_bone_count():
		var rest := skeleton.get_bone_rest(bone)
		var position := rest.origin
		var rotation := rest.basis.get_rotation_quaternion()
		var scale := rest.basis.get_scale()
		if tracks.has(bone):
			var entry: Array = tracks[bone]
			if entry[1] >= 0:
				position = source.position_track_interpolate(entry[1], t)
			if entry[2] >= 0:
				rotation = source.rotation_track_interpolate(entry[2], t)
			if entry[3] >= 0:
				scale = source.scale_track_interpolate(entry[3], t)
		out.append(Transform3D(Basis(rotation).scaled(scale), position))
	return out


static func _globals(skeleton: Skeleton3D, local: Array[Transform3D]) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for bone in skeleton.get_bone_count():
		var parent := skeleton.get_bone_parent(bone)
		out.append(local[bone] if parent < 0 else out[parent] * local[bone])
	return out


static func _insert(out: Animation, entry: Array, t: float, pose: Transform3D, with_position: bool, with_scale: bool) -> void:
	if entry[2] < 0:
		entry[2] = _add_track(out, Animation.TYPE_ROTATION_3D, entry[0])
	out.rotation_track_insert_key(entry[2], t, pose.basis.get_rotation_quaternion())
	if with_position:
		if entry[1] < 0:
			entry[1] = _add_track(out, Animation.TYPE_POSITION_3D, entry[0])
		out.position_track_insert_key(entry[1], t, pose.origin)
	if with_scale:
		if entry[3] < 0:
			entry[3] = _add_track(out, Animation.TYPE_SCALE_3D, entry[0])
		out.scale_track_insert_key(entry[3], t, pose.basis.get_scale())


static func _add_track(out: Animation, type: Animation.TrackType, path: String) -> int:
	var track := out.add_track(type)
	out.track_set_path(track, NodePath(path))
	return track
