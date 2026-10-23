class_name LeapRune
extends RuneData
## A big vertical jump that keeps your momentum, then a slow fall.

@export var up_speed := 13.0
## Added in the move direction at take-off.
@export var forward_boost := 3.0
@export var max_launch_speed := 9.0
## Gravity multiplier once falling.
@export var fall_gravity_mult := 0.35
@export var max_fall_speed := 4.5
## Horizontal speed you can steer toward in the air.
@export var air_speed := 5.0


func activate(fighter: Fighter, cmd: InputCommand) -> void:
	var planar := Vector3(fighter.velocity.x, 0.0, fighter.velocity.z)
	var wish := cmd.move_3d()
	if wish.length() > 0.2:
		planar += wish.normalized() * forward_boost
	planar = planar.limit_length(max_launch_speed)
	fighter.velocity = Vector3(planar.x, up_speed, planar.z)
	fighter.state.leaping = true
	Vfx.ring(fighter.get_parent(), fighter.global_position, Color(0.75, 0.95, 1.0), 1.6, 0.3)
