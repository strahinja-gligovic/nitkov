class_name ShowcaseActor
extends RefCounted
## Controller for the start menu's display fighters: stands facing a fixed
## direction and fires whatever button press the menu asks for, aimed at a
## chosen point, turning to face that point while it performs. (Same
## InputCommand interface as PlayerInput and BotBrain.)

## Where the fighter faces at rest.
var yaw := 0.0
var aim_point := Vector3.ZERO

var _press := 0
## Seconds left facing the aim point before turning back to rest.
var _facing := 0.0


## Queues a button press (InputCommand.PRIMARY, ...) aimed at `at`, and faces
## `at` for `hold` seconds so the cast animation and the spell line up.
func press(button: int, at: Vector3, hold := 1.2) -> void:
	_press |= button
	aim_point = at
	_facing = hold


func get_command(fighter: Fighter) -> InputCommand:
	var cmd := InputCommand.new()
	cmd.aim_yaw = yaw
	if _facing > 0.0:
		_facing -= fighter.get_physics_process_delta_time()
		var flat := (aim_point - fighter.global_position) * Vector3(1, 0, 1)
		if flat.length() > 0.5:
			cmd.aim_yaw = CombatRules.dir_to_yaw(flat)
	cmd.aim_target = aim_point if aim_point != Vector3.ZERO else fighter.chest_position() + CombatRules.yaw_to_dir(yaw) * 10.0
	cmd.pressed = _press
	cmd.held = _press
	_press = 0
	return cmd
