class_name SfxPool
extends Node
## A fixed set of 3D voices for cosmetic sounds, one pool per viewport (the
## arena's, or a SubViewport's own world). The voices are made once: 24 for
## one-shots and 12 for loops. A new sound takes a free voice or steals the
## least important, oldest one, so the node count never grows.
##
## A voice can follow a node (a projectile's look, the casting hand, a body),
## fade in and out, stop when its node goes away, bend its pitch as it flies
## past (doppler), or sit on the point of a line nearest the listener (the
## Flame Wall). Loudness over distance is computed here: full level inside
## the sound's `near` radius, then -5 dB per doubling of distance, fading to
## silence at its max distance. That's gentler than the inverse-distance
## model, so a duel at 15-20 m stays readable.
##
## Reads node positions only; never touches gameplay state. Headless (a
## server, an autotest) the voices run their whole life - following, fading,
## stealing - but never start a playback: there's no one to hear it, and a
## playback still alive at quit would outlive the dummy audio driver. With no
## camera, sounds play at their own level and nothing is culled.

const ONE_SHOT_VOICES := 24
const LOOP_VOICES := 12
## A stylised speed of sound for the fly-by pitch bend (m/s; real air is 343).
const SOUND_SPEED := 240.0
const DB_PER_DOUBLING := -5.0
const SILENT_DB := -60.0

## How one sound plays.
class Params:
	var volume_db := 0.0
	## Full level up to this distance (m).
	var near := 5.0
	## Silent from here (m); faded over the last fifth.
	var max_distance := 50.0
	## Random pitch spread (0.06 = +-6%).
	var pitch_jitter := 0.06
	## Who wins when every voice is busy (higher stays).
	var priority := 1

	func _init(db := 0.0, near_m := 5.0, far_m := 50.0, jitter := 0.06, rank := 1) -> void:
		volume_db = db
		near = near_m
		max_distance = far_m
		pitch_jitter = jitter
		priority = rank


class Voice:
	var player: AudioStreamPlayer3D
	var active := false
	var params: Params
	var age := 0.0
	## One-shots: when the stream is over (s of age).
	var length := INF
	var target_id := 0
	var offset := Vector3.ZERO
	## > 0: sit on the nearest point of the target's local X line, +-this.
	var line_half := 0.0
	var stop_with_target := false
	var level := 1.0
	## Level change per second (+ fading in, - fading out).
	var fade_speed := 0.0
	## Age at which a scheduled fade-out starts, and how long it takes.
	var stop_at := INF
	var stop_fade := 0.1
	var doppler := false
	var base_pitch := 1.0
	var bend := 1.0
	var last_position := Vector3.ZERO
	var has_last := false
	var serial := 0


static var _pools := {}
static var _silent := DisplayServer.get_name() == "headless"
## Run with `-- --sfx_log` to print every sound started.
static var _log := OS.get_cmdline_user_args().has("--sfx_log")

var _shots: Array[Voice] = []
var _loops: Array[Voice] = []
var _serial := 0
var _last_listener := Vector3.ZERO
var _listener_velocity := Vector3.ZERO
var _has_listener := false


## The pool for `node`'s viewport, made on first use (null when `node` isn't
## in a scene tree yet).
static func of(node: Node) -> SfxPool:
	if node == null or not node.is_inside_tree():
		return null
	var viewport := node.get_viewport()
	var key := viewport.get_instance_id()
	var existing: Object = instance_from_id(_pools.get(key, 0))
	if existing is SfxPool and existing.is_inside_tree():
		return existing
	var pool := SfxPool.new()
	pool.name = "SfxPool"
	viewport.add_child(pool)
	_pools[key] = pool.get_instance_id()
	return pool


func _init() -> void:
	for i in ONE_SHOT_VOICES:
		_shots.append(_make_voice("Shot%d" % i))
	for i in LOOP_VOICES:
		_loops.append(_make_voice("Loop%d" % i))


func _make_voice(voice_name: String) -> Voice:
	var player := AudioStreamPlayer3D.new()
	player.name = voice_name
	# distance is ours (_distance_db); Godot only pans and muffles
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	player.max_db = 6.0
	player.attenuation_filter_cutoff_hz = 6000.0
	player.attenuation_filter_db = -12.0
	player.panning_strength = 0.85
	add_child(player)
	var voice := Voice.new()
	voice.player = player
	return voice


func _ready() -> void:
	var bus := &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"
	for voice in _shots + _loops:
		voice.player.bus = bus


func _exit_tree() -> void:
	for voice in _shots + _loops:
		_release(voice)
	# static caches would outlive the scene tree at exit
	SfxBank.clear()
	SpellSfx.clear()


## Plays `stream` once at `at` (or following `follow`, `offset` above it).
## `from` starts part-way in (a riser lined up with its moment), `fade_in`
## eases it in from silence. Returns a handle for stop_after(), or 0 when the
## sound was dropped (out of earshot, or every voice is busier).
func play(stream: AudioStream, at: Vector3, params: Params, follow: Node3D = null, offset := Vector3.ZERO,
		from := 0.0, fade_in := 0.0, stop_with_target := false) -> int:
	if stream == null:
		return 0
	var where := at if follow == null else follow.global_position + offset
	if _beyond_earshot(where, params):
		return 0
	var voice := _free_voice(_shots, params.priority)
	if voice == null:
		return 0
	var pitch := 1.0 + randf_range(-params.pitch_jitter, params.pitch_jitter)
	_start(voice, stream, where, params, pitch, from, fade_in)
	voice.length = maxf(stream.get_length() - from, 0.05) / pitch + 0.1
	if follow:
		voice.target_id = follow.get_instance_id()
		voice.offset = offset
		voice.stop_with_target = stop_with_target
	return voice.serial


## Loops `stream` on `target` until stop_target() or the target goes away.
## It starts at a random point of the loop, so repeats never line up.
func loop(stream: AudioStream, target: Node3D, params: Params, offset := Vector3.ZERO, fade_in := 0.05,
		doppler := false, line_half := 0.0) -> int:
	if stream == null or target == null or not target.is_inside_tree():
		return 0
	var voice := _free_voice(_loops, params.priority)
	if voice == null:
		return 0
	var pitch := 1.0 + randf_range(-params.pitch_jitter, params.pitch_jitter)
	_start(voice, stream, target.global_position + offset, params, pitch, randf() * stream.get_length(), fade_in)
	voice.target_id = target.get_instance_id()
	voice.offset = offset
	voice.doppler = doppler
	voice.line_half = line_half
	voice.stop_with_target = true
	return voice.serial


## Fades out every voice following `target` (by instance id) over `fade` s.
func stop_target(target_id: int, fade := 0.1) -> void:
	for voice in _shots + _loops:
		if voice.active and voice.target_id == target_id:
			_fade_out(voice, fade)


## Schedules the voice behind `handle` to fade out `seconds` from now.
func stop_after(handle: int, seconds: float, fade := 0.1) -> void:
	var voice := _find(handle)
	if voice:
		voice.stop_at = voice.age + maxf(seconds, 0.0)
		voice.stop_fade = fade


## Pushes a scheduled stop later (a re-applied stun), or returns false when
## no voice with `handle` is playing any more.
func extend(handle: int, seconds: float) -> bool:
	var voice := _find(handle)
	if voice == null or voice.fade_speed < 0.0:
		return false
	voice.stop_at = maxf(voice.stop_at, voice.age + seconds)
	return true


## Silences every voice at once (a reset).
func stop_all() -> void:
	for voice in _shots + _loops:
		if voice.active:
			_release(voice)


func is_playing(handle: int) -> bool:
	return _find(handle) != null


## How many voices are sounding (for tests and debugging).
func busy_voices() -> int:
	var count := 0
	for voice in _shots + _loops:
		count += int(voice.active)
	return count


func _find(handle: int) -> Voice:
	if handle == 0:
		return null
	for voice in _shots + _loops:
		if voice.active and voice.serial == handle:
			return voice
	return null


func _start(voice: Voice, stream: AudioStream, where: Vector3, params: Params, pitch: float, from: float,
		fade_in: float) -> void:
	_serial += 1
	voice.serial = _serial
	voice.active = true
	voice.params = params
	voice.age = 0.0
	voice.length = INF
	voice.target_id = 0
	voice.offset = Vector3.ZERO
	voice.line_half = 0.0
	voice.stop_with_target = false
	voice.stop_at = INF
	voice.doppler = false
	voice.base_pitch = pitch
	voice.bend = 1.0
	voice.has_last = false
	voice.level = 0.0 if fade_in > 0.0 else 1.0
	voice.fade_speed = 1.0 / fade_in if fade_in > 0.0 else 0.0
	var player := voice.player
	player.stream = stream
	player.pitch_scale = pitch
	player.global_position = where
	_apply_volume(voice, where)
	if not _silent:
		player.play(from)
	if _log:
		print("[sfx %7.2f] %-28s %5.1f m  from %.2f  busy %d" % [Time.get_ticks_msec() / 1000.0,
				stream.resource_path.get_file(), where.distance_to(_last_listener) if _has_listener else -1.0, from,
				busy_voices()])


func _free_voice(voices: Array[Voice], priority: int) -> Voice:
	var victim: Voice = null
	for voice in voices:
		if not voice.active:
			return voice
		if voice.params.priority > priority:
			continue
		if victim == null or voice.params.priority < victim.params.priority \
				or (voice.params.priority == victim.params.priority and voice.age > victim.age):
			victim = voice
	if victim:
		victim.player.stop()
		victim.active = false
	return victim


func _fade_out(voice: Voice, fade: float) -> void:
	if fade <= 0.0:
		_release(voice)
		return
	voice.fade_speed = minf(voice.fade_speed, -1.0 / fade)
	voice.stop_at = INF


func _release(voice: Voice) -> void:
	voice.active = false
	voice.target_id = 0
	voice.player.stop()
	voice.player.stream = null


func _process(delta: float) -> void:
	if _log and Engine.get_process_frames() % 60 == 0:
		var names := []
		for voice in _shots + _loops:
			if voice.active:
				names.append("%s(%.1f)" % [voice.player.stream.resource_path.get_file() if voice.player.stream else "?", voice.age])
		print("[sfx] nodes %d  busy voices %d %s" % [get_tree().get_node_count(), busy_voices(), " ".join(names)])
	var listener := _listener()
	if _has_listener and delta > 0.0:
		var v := (listener - _last_listener) / delta
		_listener_velocity = _listener_velocity.lerp(v if v.length() < 60.0 else Vector3.ZERO, 0.3)
	_last_listener = listener
	for voice in _shots + _loops:
		if voice.active:
			_update(voice, delta, listener)


func _update(voice: Voice, delta: float, listener: Vector3) -> void:
	voice.age += delta
	var player := voice.player
	if voice.age >= voice.length or (voice.age > 0.1 and not player.playing and not _silent):
		_release(voice)
		return
	if voice.target_id != 0:
		var target := instance_from_id(voice.target_id) as Node3D
		if target and target.is_inside_tree():
			player.global_position = _follow_point(voice, target, listener)
		elif voice.stop_with_target:
			_fade_out(voice, 0.04 if voice.length < INF else 0.15)
			voice.target_id = 0
		else:
			voice.target_id = 0
	if voice.age >= voice.stop_at:
		_fade_out(voice, voice.stop_fade)
	if voice.fade_speed != 0.0:
		voice.level = clampf(voice.level + voice.fade_speed * delta, 0.0, 1.0)
		if voice.level >= 1.0 and voice.fade_speed > 0.0:
			voice.fade_speed = 0.0
		elif voice.level <= 0.0 and voice.fade_speed < 0.0:
			_release(voice)
			return
	if voice.doppler:
		_bend_pitch(voice, delta, listener)
	_apply_volume(voice, player.global_position)


func _follow_point(voice: Voice, target: Node3D, listener: Vector3) -> Vector3:
	var origin := target.global_position + voice.offset
	if voice.line_half <= 0.0 or not _has_listener:
		return origin
	var axis := target.global_basis.x.normalized()
	var along := clampf((listener - origin).dot(axis), -voice.line_half, voice.line_half)
	return origin + axis * along


## The fly-by bend: higher while it closes in, lower as it leaves.
func _bend_pitch(voice: Voice, delta: float, listener: Vector3) -> void:
	var where := voice.player.global_position
	if voice.has_last and delta > 0.0 and _has_listener:
		var velocity := (where - voice.last_position) / delta
		var to_source := where - listener
		if velocity.length() < 200.0 and to_source.length() > 0.5:
			var receding := (velocity - _listener_velocity).dot(to_source.normalized())
			var target_bend := clampf(SOUND_SPEED / (SOUND_SPEED + receding), 0.8, 1.25)
			voice.bend = lerpf(voice.bend, target_bend, 0.35)
			voice.player.pitch_scale = voice.base_pitch * voice.bend
	voice.last_position = where
	voice.has_last = true


func _apply_volume(voice: Voice, where: Vector3) -> void:
	var gain_db := voice.params.volume_db + _distance_db(where, voice.params)
	var level := voice.level
	if level < 0.999:
		gain_db += linear_to_db(maxf(level, 0.001))
	voice.player.volume_db = maxf(gain_db, SILENT_DB - 20.0)


func _distance_db(where: Vector3, params: Params) -> float:
	if not _has_listener:
		return 0.0
	var d := where.distance_to(_last_listener)
	var db := 0.0
	if d > params.near:
		db = DB_PER_DOUBLING * log(d / params.near) / log(2.0)
	var edge := params.max_distance * 0.8
	if d > edge:
		var t := clampf((d - edge) / (params.max_distance - edge), 0.0, 1.0)
		db += linear_to_db(maxf(1.0 - t * t * (3.0 - 2.0 * t), 0.001))
	return db


func _beyond_earshot(where: Vector3, params: Params) -> bool:
	_listener()
	return _has_listener and where.distance_to(_last_listener) >= params.max_distance


## The camera of this pool's viewport is the listener (as Godot hears it).
func _listener() -> Vector3:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	_has_listener = camera != null
	if camera == null:
		return Vector3.ZERO
	var at := camera.global_position
	if _last_listener == Vector3.ZERO:
		_last_listener = at
	return at
