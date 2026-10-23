class_name CameraRig
extends Node3D
## Over-the-shoulder camera: a yaw/pitch pivot that follows the player, a
## spring arm so walls never swallow the view, and layered shake.
## Presentation only: the simulation sees it solely through InputCommands,
## and no shake ever moves the aim (forward() and aim_point() read the
## steady view; the shake lives on the camera node's tilt, lens offsets and
## FOV).
##
## Shake layers, each with its own character:
##   trauma  a general noise shake; strength is trauma squared, so small hits stay subtle
##   buzz    a short, high-frequency jitter (lightning)
##   rumble  a slow rolling shake that swells and fades (fire)
##   jolt    one crisp snap that settles without wobble (frost, big landings)
##   push    the view shoved away from a point, drifting back (wind)
##   kick    a directional shove of the view (a blow from somewhere)
##   punch   a quick FOV zoom that springs back (big moments)

@export var pivot_height := 1.8
## Right-shoulder offset of the spring arm's origin. Generous, so an enemy
## in sword range isn't hidden behind your own character.
@export var shoulder := Vector3(1.25, 0.35, 0.0)
@export var distance := 4.0
@export var follow_sharpness := 20.0
@export var min_pitch := -60.0
@export var max_pitch := 55.0
@export var fov := 72.0
## Full-strength trauma: lens offset (m), tilt and roll (degrees).
@export var max_shake_offset := 0.12
@export var max_shake_angle := 0.8
@export var max_shake_roll := 1.5
## Scales every shake, kick and punch (0 turns them all off).
@export var shake_scale := 1.0

## Hard limits on the summed layers, so stacked big moments never throw the
## view around: lens offset (m), tilt (degrees), FOV change (degrees).
const MAX_OFFSET := 0.32
const MAX_TILT := 3.2
const MAX_FOV := 11.0
## Spring integration step (stiff springs stay stable at low frame rates).
const SPRING_STEP := 1.0 / 240.0

var target: Node3D
## Swing around behind the target on its own (when a bot drives the player).
var auto_yaw := false
var yaw := 0.0
var pitch := deg_to_rad(-12.0)
## 0..1; shake strength is trauma squared, so small hits stay subtle.
var trauma := 0.0
var camera: Camera3D

var _pitch_pivot: Node3D
var _arm: SpringArm3D
var _shake_time := 0.0
## Directional kick (camera-space x/y offset) and FOV punch, each a damped spring.
var _kick := Vector2.ZERO
var _kick_velocity := Vector2.ZERO
var _fov_offset := 0.0
var _fov_velocity := 0.0
## Buzz: amplitude 0..1 and how fast it dies (per second).
var _buzz := 0.0
var _buzz_fade := 4.0
## Rumble: peak amplitude, age and length (it swells in, then rolls out).
var _rumble := 0.0
var _rumble_age := 0.0
var _rumble_length := 0.0
## Jolt: x/y lens offset (m) and roll (radians), a stiff, critically damped spring.
var _jolt := Vector3.ZERO
var _jolt_velocity := Vector3.ZERO
## Push: x/y lens offset (m) and z dolly (m, + = shoved back), a soft spring.
var _push := Vector3.ZERO
var _push_velocity := Vector3.ZERO
var _smoother: TickSmoother


func _ready() -> void:
	top_level = true
	process_physics_priority = 100  # sample the target after it has moved this tick
	_pitch_pivot = Node3D.new()
	add_child(_pitch_pivot)
	_arm = SpringArm3D.new()
	_arm.position = shoulder
	_arm.spring_length = distance
	_arm.collision_mask = 1
	_arm.margin = 0.15
	var probe := SphereShape3D.new()
	probe.radius = 0.2
	_arm.shape = probe
	_pitch_pivot.add_child(_arm)
	camera = Camera3D.new()
	camera.fov = fov
	camera.current = true
	_arm.add_child(camera)


func follow(new_target: Node3D) -> void:
	target = new_target
	if target is CollisionObject3D:
		_arm.add_excluded_object((target as CollisionObject3D).get_rid())
	yaw = target.global_rotation.y
	_smoother = TickSmoother.new(target)
	global_position = _pivot_point()


func rotate_view(d_yaw: float, d_pitch: float) -> void:
	yaw = wrapf(yaw + d_yaw, -PI, PI)
	pitch = clampf(pitch + d_pitch, deg_to_rad(min_pitch), deg_to_rad(max_pitch))


func add_trauma(amount: float) -> void:
	trauma = minf(trauma + amount * shake_scale, 1.0)


## A directional shove of the view: "from there", where trauma only says
## "something happened". `world_dir` is the direction of the force; the part
## of it along the view becomes a brief dolly (an FOV nudge).
func kick(world_dir: Vector3, strength: float) -> void:
	if world_dir.length() < 0.001:
		return
	var local := _steady_basis().inverse() * world_dir.normalized()
	_kick_velocity += Vector2(local.x, local.y) * strength * 3.5 * shake_scale
	_fov_velocity += local.z * strength * 40.0 * shake_scale


## A quick zoom-in that springs back: big moments only (heavies, parries, breaks).
## Negative degrees zoom out instead.
func fov_punch(degrees: float) -> void:
	_fov_velocity -= degrees * 22.0 * shake_scale


## A short, high-frequency jitter (lightning): `amount` 0..1, gone after
## `seconds`. A stronger buzz replaces a weaker one.
func buzz(amount: float, seconds := 0.2) -> void:
	amount *= shake_scale
	if amount <= _buzz:
		return
	_buzz = minf(amount, 1.0)
	_buzz_fade = _buzz / maxf(seconds, 0.03)


## A slow rolling shake that swells in and rolls out over `seconds` (fire).
## A stronger rumble restarts it; a weaker one under a running rumble is
## lost in it.
func rumble(amount: float, seconds := 0.5) -> void:
	amount *= shake_scale
	if amount <= _rumble_level():
		return
	_rumble = minf(amount, 1.0)
	_rumble_age = 0.0
	_rumble_length = maxf(seconds, 0.1)


## One crisp snap along `world_dir` that settles at once, without wobble
## (frost, a bolt landing). `strength` ~0.3 light, ~1 heavy.
func jolt(world_dir: Vector3, strength: float) -> void:
	var local := Vector3.DOWN
	if world_dir.length() > 0.001:
		local = _steady_basis().inverse() * world_dir.normalized()
	var roll := signf(local.x) if absf(local.x) > 0.2 else (1.0 if randf() < 0.5 else -1.0)
	_jolt_velocity += Vector3(local.x * 6.5, local.y * 6.5, roll * 1.4) * strength * shake_scale


## The view shoved away from `world_point` and drifting back (wind): sideways
## and up or down on the lens, and back along the view as a widening FOV.
func push_from(world_point: Vector3, strength: float) -> void:
	push(camera.global_position - world_point, strength)


## The view shoved along `world_dir` and drifting back (see push_from).
func push(world_dir: Vector3, strength: float) -> void:
	if world_dir.length() < 0.001:
		world_dir = -forward()
	var local := _steady_basis().inverse() * world_dir.normalized()
	_push_velocity += local * strength * 2.6 * shake_scale


func forward() -> Vector3:
	return -_steady_basis().z


## World point under the crosshair. The ray starts level with `shooter`, so
## nothing between the camera and the shooter can catch it.
func aim_point(shooter: Vector3, exclude: Array[RID], max_distance := 150.0) -> Vector3:
	var origin := camera.global_position
	var dir := forward()
	var start := origin + dir * maxf(dir.dot(shooter - origin), 0.0)
	var query := PhysicsRayQueryParameters3D.create(start, start + dir * max_distance, 1 | 2, exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.position if hit else start + dir * max_distance


## The yaw a shooter at `from` should face to look at `aim_point`. The camera
## sits off-shoulder, so near targets need a different yaw than the camera's
## own: without this, an enemy under the crosshair at sword range can sit far
## outside your swing. Falls back to the camera yaw for points too close or
## off to the side.
func body_yaw(from: Vector3, aim_point: Vector3) -> float:
	var flat := Vector3(aim_point.x - from.x, 0.0, aim_point.z - from.z)
	if flat.length() < 1.0:
		return yaw
	var toward := CombatRules.dir_to_yaw(flat)
	return toward if absf(wrapf(toward - yaw, -PI, PI)) < deg_to_rad(70.0) else yaw


func _physics_process(_delta: float) -> void:
	if _smoother:
		_smoother.tick()


func _process(delta: float) -> void:
	if target == null:
		return
	var t := 1.0 - exp(-follow_sharpness * delta)
	global_position = global_position.lerp(_pivot_point(), t)
	if auto_yaw:
		yaw = lerp_angle(yaw, target.global_rotation.y, 1.0 - exp(-4.0 * delta))
	rotation = Vector3(0.0, yaw, 0.0)
	_pitch_pivot.rotation = Vector3(pitch, 0.0, 0.0)
	_apply_shake(delta)


func _pivot_point() -> Vector3:
	return _smoother.position() + Vector3.UP * pivot_height


## The view without any shake: the yaw and pitch the player aims with.
func _steady_basis() -> Basis:
	return _pitch_pivot.global_basis if _pitch_pivot.is_inside_tree() else Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)


func _rumble_level() -> float:
	if _rumble_age >= _rumble_length:
		return 0.0
	var swell := clampf(_rumble_age / 0.05, 0.0, 1.0)
	return _rumble * swell * pow(1.0 - _rumble_age / _rumble_length, 1.5)


func _apply_shake(delta: float) -> void:
	trauma = maxf(trauma - delta * 1.8, 0.0)
	_shake_time += delta
	_buzz = maxf(_buzz - _buzz_fade * delta, 0.0)
	_rumble_age += delta
	_step_springs(delta)
	var t := _shake_time

	# trauma: smooth noise from a few detuned sines
	var s := trauma * trauma
	var offset := Vector2(sin(t * 61.0) * cos(t * 23.0), sin(t * 47.0 + 1.3)) * max_shake_offset * s
	var tilt := Vector3(sin(t * 53.0 + 2.1) * cos(t * 17.0) * max_shake_angle,
			sin(t * 43.0 + 0.4) * max_shake_angle, sin(t * 37.0 + 0.7) * max_shake_roll) * s
	# buzz: a new random offset ~50 times a second, as violent as it is brief
	if _buzz > 0.0:
		var step := floorf(t * 50.0)
		var b := _buzz * _buzz
		offset += Vector2(_hash(step), _hash(step + 31.7)) * 0.08 * b
		tilt += Vector3(_hash(step + 7.3), _hash(step + 13.1), _hash(step + 19.9) * 1.5) * 1.5 * b
	# rumble: a heavy, rolling bob that swells and fades
	var r := _rumble_level()
	if r > 0.0:
		offset += Vector2(sin(t * 33.0 + 0.5) * 0.4, sin(t * 46.0) * 0.7 + sin(t * 74.0 + 1.7) * 0.3) * 0.06 * r
		tilt += Vector3(sin(t * 58.0 + 2.1) * 0.6, sin(t * 29.0 + 0.9) * 0.4, sin(t * 39.0 + 0.4)) * 1.3 * r
	# the jolt snaps the view itself too (a lens offset alone barely moves the distance)
	offset += _kick + Vector2(_jolt.x, _jolt.y) + Vector2(_push.x, _push.y)
	tilt += Vector3(_jolt.y * 26.0, -_jolt.x * 16.0, rad_to_deg(_jolt.z) - _push.x * 9.0)
	offset = offset.limit_length(MAX_OFFSET)
	camera.h_offset = offset.x
	camera.v_offset = offset.y
	camera.rotation = Vector3(deg_to_rad(clampf(tilt.x, -MAX_TILT, MAX_TILT)),
			deg_to_rad(clampf(tilt.y, -MAX_TILT, MAX_TILT)), deg_to_rad(clampf(tilt.z, -MAX_TILT, MAX_TILT)))
	camera.fov = fov + clampf(_fov_offset + _push.z * 22.0, -MAX_FOV, MAX_FOV)


## Advances every spring in small steps, so the stiff ones stay stable.
func _step_springs(delta: float) -> void:
	var left := minf(delta, 0.1)
	while left > 0.0:
		var dt := minf(left, SPRING_STEP)
		left -= dt
		# kick returns over ~0.15 s, the FOV punch over ~0.25 s
		_kick_velocity += (-900.0 * _kick - 48.0 * _kick_velocity) * dt
		_kick += _kick_velocity * dt
		_fov_velocity += (-324.0 * _fov_offset - 30.0 * _fov_velocity) * dt
		_fov_offset += _fov_velocity * dt
		# jolt: omega 48, critically damped: out and back in ~70 ms, no wobble
		_jolt_velocity += (-2304.0 * _jolt - 96.0 * _jolt_velocity) * dt
		_jolt += _jolt_velocity * dt
		# push: omega 10, zeta 0.5: shoved, then drifting back with a small sway
		_push_velocity += (-100.0 * _push - 10.0 * _push_velocity) * dt
		_push += _push_velocity * dt


## A stable pseudo-random value in -1..1 for a step number.
static func _hash(n: float) -> float:
	return fposmod(sin(n * 12.9898 + 4.1414) * 43758.5453, 1.0) * 2.0 - 1.0
