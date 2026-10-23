class_name CameraRig
extends Node3D
## Over-the-shoulder camera: a yaw/pitch pivot that follows the player, a
## spring arm so walls never swallow the view, and trauma-based shake.
## Presentation only: the simulation sees it solely through InputCommands.

@export var pivot_height := 1.55
## Right-shoulder offset of the spring arm's origin.
@export var shoulder := Vector3(1.1, 0.3, 0.0)
@export var distance := 3.6
@export var follow_sharpness := 20.0
@export var min_pitch := -60.0
@export var max_pitch := 55.0
@export var fov := 72.0
@export var max_shake_offset := 0.12
@export var max_shake_roll := 1.5

var target: Node3D
var yaw := 0.0
var pitch := deg_to_rad(-6.0)
## 0..1; shake strength is trauma squared, so small hits stay subtle.
var trauma := 0.0
var camera: Camera3D

var _pitch_pivot: Node3D
var _arm: SpringArm3D
var _shake_time := 0.0


func _ready() -> void:
	top_level = true
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
	global_position = _pivot_point()


func rotate_view(d_yaw: float, d_pitch: float) -> void:
	yaw = wrapf(yaw + d_yaw, -PI, PI)
	pitch = clampf(pitch + d_pitch, deg_to_rad(min_pitch), deg_to_rad(max_pitch))


func add_trauma(amount: float) -> void:
	trauma = minf(trauma + amount, 1.0)


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


func _process(delta: float) -> void:
	if target == null:
		return
	var t := 1.0 - exp(-follow_sharpness * delta)
	global_position = global_position.lerp(_pivot_point(), t)
	rotation = Vector3(0.0, yaw, 0.0)
	_pitch_pivot.rotation = Vector3(pitch, 0.0, 0.0)
	_apply_shake(delta)


func _pivot_point() -> Vector3:
	return target.global_position + Vector3.UP * pivot_height


func _apply_shake(delta: float) -> void:
	trauma = maxf(trauma - delta * 1.8, 0.0)
	_shake_time += delta
	var s := trauma * trauma
	camera.h_offset = sin(_shake_time * 61.0) * cos(_shake_time * 23.0) * max_shake_offset * s
	camera.v_offset = sin(_shake_time * 47.0 + 1.3) * max_shake_offset * s
	camera.rotation.z = deg_to_rad(sin(_shake_time * 37.0 + 0.7) * max_shake_roll * s)
