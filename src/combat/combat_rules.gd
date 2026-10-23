class_name CombatRules
extends RefCounted
## The combat rules as pure functions over FighterState. No nodes and no
## physics, so everything here is unit tested headless (see tests/).


## Facing direction for a yaw angle. Godot's forward is -Z.
static func yaw_to_dir(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


static func dir_to_yaw(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)


## True when `source` lies within the `arc_deg` cone centred on the facing direction.
static func is_in_front(facing_yaw: float, at: Vector3, source: Vector3, arc_deg: float) -> bool:
	var to_source := Vector3(source.x - at.x, 0.0, source.z - at.z)
	if to_source.length_squared() < 0.0001:
		return true
	return yaw_to_dir(facing_yaw).dot(to_source.normalized()) >= cos(deg_to_rad(arc_deg * 0.5)) - 0.0001
