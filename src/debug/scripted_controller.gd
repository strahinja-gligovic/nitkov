class_name ScriptedController
extends RefCounted
## Plays back a timeline of inputs in place of a human, for automated
## verification runs (see Autopilot and Scenarios). Each step is a Dictionary:
##   at: start second, for: duration (default 0.1)
##   move: Vector2(right, forward) relative to the camera
##   hold: InputCommand button bits held for the whole step
##   press: button bits pressed on the step's first tick (also held while it lasts)
##   turn: camera yaw speed in rad/s, pitch: camera pitch speed in rad/s

var steps: Array = []
var camera_rig: CameraRig
var time := 0.0
var _fired := {}


func _init(timeline: Array, rig: CameraRig) -> void:
	steps = timeline
	camera_rig = rig


func get_command(fighter: Fighter) -> InputCommand:
	var dt := fighter.get_physics_process_delta_time()
	time += dt
	var cmd := InputCommand.new()
	var local_move := Vector2.ZERO
	var turn := 0.0
	var pitch := 0.0
	for i in steps.size():
		var step: Dictionary = steps[i]
		var start: float = step.get("at", 0.0)
		var length: float = step.get("for", 0.1)
		if time < start or time >= start + length:
			continue
		local_move += step.get("move", Vector2.ZERO)
		turn += step.get("turn", 0.0)
		pitch += step.get("pitch", 0.0)
		cmd.held |= int(step.get("hold", 0)) | int(step.get("press", 0))
		if step.has("press") and not _fired.has(i):
			_fired[i] = true
			cmd.pressed |= int(step["press"])
	camera_rig.rotate_view(turn * dt, pitch * dt)
	cmd.aim_yaw = camera_rig.yaw
	var world := Basis(Vector3.UP, camera_rig.yaw) * Vector3(local_move.x, 0.0, -local_move.y)
	cmd.move = Vector2(world.x, world.z).limit_length(1.0)
	cmd.aim_target = camera_rig.aim_point(fighter.chest_position(), [fighter.get_rid()])
	return cmd
