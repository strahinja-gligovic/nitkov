class_name BlinkRune
extends RuneData
## An instant short teleport in the move direction (forward with no input).
## The body's capsule is swept along the path, so walls stop it.

@export var distance := 8.0
@export var invulnerability := 0.1


func activate(fighter: Fighter, cmd: InputCommand) -> void:
	var direction := cmd.move_3d()
	direction = direction.normalized() if direction.length() > 0.2 else fighter.forward()
	var from := fighter.global_position
	var to := from + direction * distance * _free_fraction(fighter, direction * distance)
	Vfx.ring(fighter.get_parent(), from, Color(0.8, 0.6, 1.0), 1.4, 0.3)
	Vfx.impact(fighter.get_parent(), from + Vector3.UP, Color(0.8, 0.6, 1.0), 1.6, 0.25, 4.0)
	fighter.global_position = to
	fighter.state.invulnerable = maxf(fighter.state.invulnerable, invulnerability)
	Vfx.impact(fighter.get_parent(), to + Vector3.UP, Color(0.8, 0.6, 1.0), 1.6, 0.25, 4.0)


## How much of `motion` the body can travel before touching world geometry.
## The probe starts slightly lifted so standing on the floor isn't a contact.
static func _free_fraction(fighter: Fighter, motion: Vector3) -> float:
	var collider := fighter.get_node(^"Collision") as CollisionShape3D
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collider.shape
	query.transform = fighter.global_transform * collider.transform
	query.transform.origin += Vector3.UP * 0.15
	query.motion = motion
	query.collision_mask = 1
	query.exclude = [fighter.get_rid()]
	var fractions := fighter.get_world_3d().direct_space_state.cast_motion(query)
	return fractions[0]
