class_name ShowcaseActor
extends RefCounted
## Controller for the start menu's display fighters: stands facing a fixed
## direction and fires whatever button press the menu asks for, aimed at a
## chosen point. (Same InputCommand interface as PlayerInput and BotBrain.)

var yaw := 0.0
var aim_point := Vector3.ZERO

var _press := 0


func press(button: int, at: Vector3) -> void:
	_press |= button
	aim_point = at


func get_command(fighter: Fighter) -> InputCommand:
	var cmd := InputCommand.new()
	cmd.aim_yaw = yaw
	cmd.aim_target = aim_point if aim_point != Vector3.ZERO else fighter.chest_position() + CombatRules.yaw_to_dir(yaw) * 10.0
	cmd.pressed = _press
	cmd.held = _press
	_press = 0
	return cmd
