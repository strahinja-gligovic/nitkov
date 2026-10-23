class_name ScriptedController
extends RefCounted
## Plays back a timeline of inputs in place of a human, for automated
## verification runs (see Autopilot and Scenarios). Each step is a Dictionary:
##   at: start second, for: duration (default 0.1)
##   move: Vector2(right, forward) relative to the camera
##   hold: InputCommand button bits held for the whole step
##   press: button bits pressed on the step's first tick (also held while it lasts)
##   turn: camera yaw speed in rad/s, pitch: camera pitch speed in rad/s
##   track: true steers the crosshair onto the nearest enemy, like a player aiming
##   swap: true quick-swaps the gauntlet on the step's first tick (debug key T)

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
	var track := false
	for i in steps.size():
		var step: Dictionary = steps[i]
		var start: float = step.get("at", 0.0)
		var length: float = step.get("for", 0.1)
		if time < start or time >= start + length:
			continue
		local_move += step.get("move", Vector2.ZERO)
		turn += step.get("turn", 0.0)
		pitch += step.get("pitch", 0.0)
		track = track or step.get("track", false)
		cmd.held |= int(step.get("hold", 0)) | int(step.get("press", 0))
		if (step.has("press") or step.has("swap")) and not _fired.has(i):
			_fired[i] = true
			cmd.pressed |= int(step.get("press", 0))
			if step.get("swap", false):
				fighter.cycle_gauntlet()
	if camera_rig:
		camera_rig.rotate_view(turn * dt, pitch * dt)
		if track:
			_aim_camera_at(_nearest_enemy(fighter))
		cmd.aim_yaw = camera_rig.yaw
		cmd.aim_target = camera_rig.aim_point(fighter.chest_position(), [fighter.get_rid()])
	else:
		# no camera (a scripted bot): face and aim at the nearest enemy
		var foe := _nearest_enemy(fighter)
		cmd.aim_yaw = fighter.state.facing_yaw
		if foe:
			cmd.aim_yaw = CombatRules.dir_to_yaw(foe.global_position - fighter.global_position)
			cmd.aim_target = foe.chest_position()
	var world := Basis(Vector3.UP, cmd.aim_yaw) * Vector3(local_move.x, 0.0, -local_move.y)
	cmd.move = Vector2(world.x, world.z).limit_length(1.0)
	return cmd


## Turns the camera so its centre ray passes through the foe's chest. The
## camera sits off-shoulder, so this converges over a few ticks.
func _aim_camera_at(foe: Fighter) -> void:
	if foe == null:
		return
	var to := foe.chest_position() - camera_rig.camera.global_position
	var want_yaw := CombatRules.dir_to_yaw(Vector3(to.x, 0.0, to.z))
	var want_pitch := atan2(to.y, Vector2(to.x, to.z).length())
	camera_rig.rotate_view(wrapf(want_yaw - camera_rig.yaw, -PI, PI) * 0.5, (want_pitch - camera_rig.pitch) * 0.5)


static func _nearest_enemy(fighter: Fighter) -> Fighter:
	var best: Fighter = null
	for other in fighter.enemies():
		if best == null or fighter.global_position.distance_to(other.global_position) < fighter.global_position.distance_to(best.global_position):
			best = other
	return best
