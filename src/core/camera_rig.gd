class_name CameraRig
extends Node3D
## Over-the-shoulder camera: a yaw/pitch pivot that follows the player, a
## spring arm so walls never swallow the view, and trauma-based shake.
## Presentation only: the simulation sees it solely through InputCommands.

@export var pivot_height := 1.8
## Right-shoulder offset of the spring arm's origin. Generous, so an enemy
## in sword range isn't hidden behind your own character.
@export var shoulder := Vector3(1.25, 0.35, 0.0)
@export var distance := 4.0
@export var follow_sharpness := 20.0
@export var min_pitch := -60.0
@export var max_pitch := 55.0
@export var fov := 72.0
@export var max_shake_offset := 0.12
@export var max_shake_roll := 1.5

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
	trauma = minf(trauma + amount, 1.0)


## A directional shove of the view: "from there", where trauma only says
## "something happened". `world_dir` is the direction of the force; the part
## of it along the view becomes a brief dolly (an FOV nudge).
func kick(world_dir: Vector3, strength: float) -> void:
	var local := camera.global_basis.inverse() * world_dir.normalized()
	_kick_velocity += Vector2(local.x, local.y) * strength * 3.5
	_fov_velocity += local.z * strength * 40.0


## A quick zoom-in that springs back: big moments only (heavies, parries, breaks).
func fov_punch(degrees: float) -> void:
	_fov_velocity -= degrees * 22.0


func forward() -> Vector3:
	return -camera.global_basis.z


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


func _apply_shake(delta: float) -> void:
	trauma = maxf(trauma - delta * 1.8, 0.0)
	_shake_time += delta
	var s := trauma * trauma
	# springs: kick returns over ~0.15s, the FOV punch over ~0.25s
	_kick_velocity += (-900.0 * _kick - 48.0 * _kick_velocity) * delta
	_kick += _kick_velocity * delta
	_fov_velocity += (-324.0 * _fov_offset - 30.0 * _fov_velocity) * delta
	_fov_offset += _fov_velocity * delta
	camera.h_offset = sin(_shake_time * 61.0) * cos(_shake_time * 23.0) * max_shake_offset * s + _kick.x
	camera.v_offset = sin(_shake_time * 47.0 + 1.3) * max_shake_offset * s + _kick.y
	camera.rotation.z = deg_to_rad(sin(_shake_time * 37.0 + 0.7) * max_shake_roll * s)
	camera.fov = fov + _fov_offset
