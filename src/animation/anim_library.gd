class_name AnimLibrary
extends RefCounted
## The clips fighters play, prepared once per skeleton shape. Several CC0
## sources share one 65-bone humanoid rig, but each was authored on its own
## rest pose, and our characters' rests differ again (spine and neck by up to
## 14 degrees). Bone tracks store absolute local rotations, so raw playback
## would bend every bone by its rest difference. For each clip the move set
## uses, this:
##   - renames bones (Mesh2Motion's "head" is our "Head") and drops tracks
##     for bones our characters don't have;
##   - re-expresses every rotation key relative to the target's rest:
##       q' = A(parent)^-1 * q * A(bone),   A(b) = source_rest(b)^-1 * target_rest(b)
##     (global rest rotations), which reproduces the source's motion;
##   - keeps position only on root and pelvis, scaled by the pelvis heights,
##     so bone lengths stay the character's own and feet stay on the floor;
##   - drops scale tracks that never change;
##   - splices chained moves into one clip ("<first>+<second>");
##   - bakes "<clip>@mirror" copies for moves played mirrored, and flags loops.
## Results are cached per rest pose, so every fighter of a body type shares them.

const MIRROR_SUFFIX := "@mirror"
## Library prefix -> imported source scene.
const SOURCES := {
	&"ual1": "res://assets/animations/UAL1_Standard.glb",
	&"ual2": "res://assets/animations/UAL2_Standard.glb",
	&"m2m_addon": "res://assets/animations/m2m_addon.glb",
}
## Source bone name -> our bone name, per source.
const RENAMES := {&"m2m_addon": {"head": "Head"}}
const SKELETON_PATH := "Armature/Skeleton3D"
## Bones whose position is animated; every other bone keeps its own length.
const MOVING_BONES: Array[String] = ["root", "pelvis"]
const LOOPING_MOVES: Array[StringName] = [&"idle", &"leap_air"]

## prefix -> {"library": AnimationLibrary, "rest": {bone: Quaternion}, "pelvis": float}
static var _sources := {}
## rest signature -> {prefix: AnimationLibrary}
static var _prepared := {}


## Gives `player` the move set's clips, converted for `skeleton`'s rest pose.
static func attach(player: AnimationPlayer, skeleton: Skeleton3D, moves: MoveSet) -> void:
	if _sources.is_empty():
		_load_sources()
	var key := "%d:%s" % [moves.get_instance_id(), _signature(skeleton)]
	if not _prepared.has(key):
		_prepared[key] = _prepare(skeleton, moves)
	var libraries: Dictionary = _prepared[key]
	for prefix: StringName in libraries:
		if player.has_animation_library(prefix):
			player.remove_animation_library(prefix)
		player.add_animation_library(prefix, libraries[prefix])


## Forgets converted clips (e.g. after editing the move set's mirror flags).
static func clear_cache() -> void:
	_prepared.clear()


static func _load_sources() -> void:
	for prefix: StringName in SOURCES:
		var scene: PackedScene = load(SOURCES[prefix])
		if scene == null:
			push_warning("AnimLibrary: missing %s" % SOURCES[prefix])
			continue
		var instance := scene.instantiate()
		var player := instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
		var skeleton := instance.find_child("Skeleton3D", true, false) as Skeleton3D
		if player and skeleton and player.has_animation_library(&""):
			var rest := {}
			for bone in skeleton.get_bone_count():
				rest[skeleton.get_bone_name(bone)] = skeleton.get_bone_global_rest(bone).basis.get_rotation_quaternion()
			_sources[prefix] = {
				"library": player.get_animation_library(&""),
				"rest": rest,
				"pelvis": skeleton.get_bone_global_rest(skeleton.find_bone("pelvis")).origin.y,
			}
		instance.free()


static func _prepare(skeleton: Skeleton3D, moves: MoveSet) -> Dictionary:
	var libraries := {}
	var converted := {}  # "prefix/clip" -> Animation, converted for this skeleton
	for id: StringName in moves.moves:
		var move: AnimMove = moves.moves[id]
		var prefix := StringName(String(move.clip).get_base_dir())
		if not libraries.has(prefix):
			libraries[prefix] = AnimationLibrary.new()
		var library: AnimationLibrary = libraries[prefix]
		var name := move.baked_name()
		if not library.has_animation(name):
			var clip := _part(move.clip, move.mirror, skeleton, converted)
			if clip == null:
				push_warning("AnimLibrary: move %s wants missing clip %s" % [id, move.clip])
				continue
			if move.clip_from > 0.0:
				clip = trim_start(clip, move.clip_from)
			if move.has_chain():
				var second := _part(move.chain_clip, move.chain_mirror, skeleton, converted)
				if second == null:
					push_warning("AnimLibrary: move %s wants missing clip %s" % [id, move.chain_clip])
					continue
				clip = splice(clip, move.chain_at, second, move.chain_from, move.chain_to, move.chain_blend)
			library.add_animation(name, clip)
		if move.ground_speed > 0.0 or id in LOOPING_MOVES:
			library.get_animation(name).loop_mode = Animation.LOOP_LINEAR
	return libraries


## A clip converted for `skeleton`, mirrored if asked; each kept once per prepare.
static func _part(path: StringName, mirrored: bool, skeleton: Skeleton3D, cache: Dictionary) -> Animation:
	var key := String(path) + (MIRROR_SUFFIX if mirrored else "")
	if cache.has(key):
		return cache[key]
	var clip := _converted(path, skeleton, cache)
	if clip != null and mirrored:
		clip = AnimMirror.mirror(clip, skeleton)
		cache[key] = clip
	return clip


## A source clip ("prefix/name") converted for `skeleton`, once per prepare.
static func _converted(path: StringName, skeleton: Skeleton3D, cache: Dictionary) -> Animation:
	if cache.has(path):
		return cache[path]
	var prefix := StringName(String(path).get_base_dir())
	var name := String(path).get_file()
	if not _sources.has(prefix):
		return null
	var source: Dictionary = _sources[prefix]
	var library: AnimationLibrary = source["library"]
	if not library.has_animation(name):
		return null
	var clip := retarget(library.get_animation(name), source["rest"], source["pelvis"], skeleton, RENAMES.get(prefix, {}))
	cache[path] = clip
	return clip


## `first` up to `first_until` seconds, flowing into `second` from
## `second_from` to `second_to`, crossfaded over `blend` seconds that end at
## the splice. Resampled at 30 fps.
static func splice(first: Animation, first_until: float, second: Animation, second_from: float,
		second_to: float, blend: float) -> Animation:
	blend = clampf(blend, 0.0, first_until)
	var offset := first_until - blend  # where `second` (at second_from) joins
	var out := Animation.new()
	out.length = offset + maxf(second_to - second_from, 0.0)
	var frames := ceili(out.length * 30.0)
	var tracks := {}  # "type|path" -> [type, path]
	for clip: Animation in [first, second]:
		for track in clip.get_track_count():
			var type := clip.track_get_type(track)
			if type in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]:
				tracks["%d|%s" % [type, clip.track_get_path(track)]] = [type, clip.track_get_path(track)]
	for entry: Array in tracks.values():
		var type: int = entry[0]
		var path: NodePath = entry[1]
		var a := first.find_track(path, type)
		var b := second.find_track(path, type)
		var track := out.add_track(type)
		out.track_set_path(track, path)
		for frame in frames + 1:
			var t := minf(frame / 30.0, out.length)
			var from_first: Variant = _sample(first, a, minf(t, first_until), type)
			var from_second: Variant = _sample(second, b, clampf(second_from + t - offset, second_from, second_to), type)
			if from_first == null:
				from_first = from_second
			if from_second == null:
				from_second = from_first
			var w := smoothstep(0.0, 1.0, (t - offset) / blend) if blend > 0.0 else (1.0 if t >= offset else 0.0)
			match type:
				Animation.TYPE_ROTATION_3D:
					out.rotation_track_insert_key(track, t, (from_first as Quaternion).slerp(from_second, w))
				Animation.TYPE_POSITION_3D:
					out.position_track_insert_key(track, t, (from_first as Vector3).lerp(from_second, w))
				Animation.TYPE_SCALE_3D:
					out.scale_track_insert_key(track, t, (from_first as Vector3).lerp(from_second, w))
	return out


## `clip` without its first `seconds`, every key moved earlier by as much.
static func trim_start(clip: Animation, seconds: float) -> Animation:
	var out := Animation.new()
	out.length = maxf(clip.length - seconds, 0.001)
	for track in clip.get_track_count():
		var type := clip.track_get_type(track)
		if type not in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]:
			continue
		var copy := out.add_track(type)
		out.track_set_path(copy, clip.track_get_path(track))
		# the pose at the cut, then every later key
		var first: Variant = _sample(clip, track, seconds, type)
		_insert_key(out, copy, type, 0.0, first)
		for key in clip.track_get_key_count(track):
			var t := clip.track_get_key_time(track, key)
			if t > seconds + 0.0001:
				_insert_key(out, copy, type, t - seconds, clip.track_get_key_value(track, key))
	return out


static func _insert_key(clip: Animation, track: int, type: int, t: float, value: Variant) -> void:
	match type:
		Animation.TYPE_ROTATION_3D:
			clip.rotation_track_insert_key(track, t, value)
		Animation.TYPE_POSITION_3D:
			clip.position_track_insert_key(track, t, value)
		Animation.TYPE_SCALE_3D:
			clip.scale_track_insert_key(track, t, value)


static func _sample(clip: Animation, track: int, t: float, type: int) -> Variant:
	if track < 0:
		return null
	match type:
		Animation.TYPE_ROTATION_3D:
			return clip.rotation_track_interpolate(track, t)
		Animation.TYPE_POSITION_3D:
			return clip.position_track_interpolate(track, t)
	return clip.scale_track_interpolate(track, t)


## A copy of `source` re-expressed for `target`'s rest pose (see the class notes).
## `source_rest` maps source bone names to global rest rotations.
static func retarget(source: Animation, source_rest: Dictionary, source_pelvis: float,
		target: Skeleton3D, renames: Dictionary) -> Animation:
	var to_source := {}
	for from: String in renames:
		to_source[renames[from]] = from
	var adjust := {}
	for bone in target.get_bone_count():
		var bone_name := target.get_bone_name(bone)
		var source_name: String = to_source.get(bone_name, bone_name)
		if source_rest.has(source_name):
			var target_rest := target.get_bone_global_rest(bone).basis.get_rotation_quaternion()
			adjust[bone_name] = (source_rest[source_name] as Quaternion).inverse() * target_rest
	var pelvis := target.find_bone("pelvis")
	var height := target.get_bone_global_rest(pelvis).origin.y / source_pelvis if pelvis >= 0 and source_pelvis > 0.0 else 1.0

	var clip := source.duplicate(true) as Animation
	for track in range(clip.get_track_count() - 1, -1, -1):
		var type := clip.track_get_type(track)
		var bone_name := String(clip.track_get_path(track).get_concatenated_subnames())
		bone_name = renames.get(bone_name, bone_name)
		var bone := target.find_bone(bone_name)
		if bone < 0 or not adjust.has(bone_name) \
				or type not in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]:
			clip.remove_track(track)
			continue
		clip.track_set_path(track, NodePath("%s:%s" % [SKELETON_PATH, bone_name]))
		var parent := target.get_bone_parent(bone)
		var parent_adjust: Quaternion = adjust.get(target.get_bone_name(parent), Quaternion.IDENTITY) if parent >= 0 else Quaternion.IDENTITY
		var own: Quaternion = adjust[bone_name]
		match type:
			Animation.TYPE_ROTATION_3D:
				for key in clip.track_get_key_count(track):
					var q: Quaternion = clip.track_get_key_value(track, key)
					clip.track_set_key_value(track, key, (parent_adjust.inverse() * q * own).normalized())
			Animation.TYPE_POSITION_3D:
				if bone_name not in MOVING_BONES:
					clip.remove_track(track)
					continue
				for key in clip.track_get_key_count(track):
					var p: Vector3 = clip.track_get_key_value(track, key)
					clip.track_set_key_value(track, key, parent_adjust.inverse() * p * height)
			Animation.TYPE_SCALE_3D:
				if _is_constant(clip, track):
					clip.remove_track(track)
	return clip


static func _is_constant(clip: Animation, track: int) -> bool:
	var count := clip.track_get_key_count(track)
	if count < 2:
		return true
	var first: Vector3 = clip.track_get_key_value(track, 0)
	for key in range(1, count):
		if (clip.track_get_key_value(track, key) as Vector3).distance_to(first) > 0.0005:
			return false
	return true


## Identifies a rest pose: skeletons with equal rests share converted clips.
static func _signature(skeleton: Skeleton3D) -> String:
	var parts := PackedStringArray()
	for bone in skeleton.get_bone_count():
		var rest := skeleton.get_bone_rest(bone)
		var q := rest.basis.get_rotation_quaternion()
		parts.append("%s %.4f %.4f %.4f %.4f %.4f %.4f %.4f" % [skeleton.get_bone_name(bone),
				q.x, q.y, q.z, q.w, rest.origin.x, rest.origin.y, rest.origin.z])
	return str(";".join(parts).hash())
