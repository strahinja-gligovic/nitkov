class_name BotAim
extends RefCounted
## The bot's aiming and prediction math, as pure functions (no nodes and no
## physics), so it's unit tested headless. BotBrain feeds it what it sees.

## How fast a shove dies away (m/s per second), as Fighter._move decays knockback.
const KNOCKBACK_DECAY := 14.0


## Seconds until a shot fired now from `origin` at `speed` can meet a target
## at `target` moving with a constant `velocity`, or -1 if it never can.
static func intercept_time(origin: Vector3, target: Vector3, velocity: Vector3, speed: float) -> float:
	var to := target - origin
	# |to + velocity * t| = speed * t, as a quadratic in t
	var a := velocity.length_squared() - speed * speed
	var b := 2.0 * to.dot(velocity)
	var c := to.length_squared()
	if absf(a) < 0.0001:
		return -c / b if b < 0.0 else -1.0
	var discriminant := b * b - 4.0 * a * c
	if discriminant < 0.0:
		return -1.0
	var root := sqrt(discriminant)
	var best := INF
	for t: float in [(-b - root) / (2.0 * a), (-b + root) / (2.0 * a)]:
		if t > 0.0 and t < best:
			best = t
	return best if best < INF else -1.0


## Where to aim a shot of `speed` from `origin` at a target moving with
## `velocity`. `lead` scales how much of the lead is taken: 0 aims where the
## target is now, 1 where shot and target meet.
static func lead_point(origin: Vector3, target: Vector3, velocity: Vector3, speed: float, lead := 1.0) -> Vector3:
	var t := intercept_time(origin, target, velocity, speed)
	if t < 0.0:
		t = origin.distance_to(target) / maxf(speed, 0.01)
	return target + velocity * t * lead


## Ground covered by a shove still running at `knockback` before it dies away.
static func knockback_travel(knockback: Vector3) -> Vector3:
	var flat := Vector3(knockback.x, 0.0, knockback.z)
	var speed := flat.length()
	if speed < 0.01:
		return Vector3.ZERO
	return flat / speed * (speed * speed / (2.0 * KNOCKBACK_DECAY))


## Where a fighter will probably stand `horizon` seconds from now. A shove
## carries them first; they stay put while `pinned` (stunned, mid-swing),
## then drift along `velocity`, scaled by `lead` (how far the bot trusts
## their heading to hold).
static func predict_position(position: Vector3, velocity: Vector3, knockback: Vector3, pinned: float,
		horizon: float, lead: float) -> Vector3:
	var drift := Vector3(velocity.x, 0.0, velocity.z) * maxf(horizon - pinned, 0.0) * lead
	return position + knockback_travel(knockback) + drift


## How far `point` must travel along `direction` to leave the circle of
## `radius` around `centre`, measured flat (XZ). 0 if it's already outside.
static func circle_exit_distance(point: Vector3, direction: Vector3, centre: Vector3, radius: float) -> float:
	var offset := Vector2(point.x - centre.x, point.z - centre.z)
	var c := offset.length_squared() - radius * radius
	if c >= 0.0:
		return 0.0
	var heading := Vector2(direction.x, direction.z).normalized()
	var b := offset.dot(heading)
	return -b + sqrt(b * b - c)


## Flat distance from `point` to the line through `from` along `direction`,
## and which side it's on: the offset from the line to the point.
static func offset_from_line(point: Vector3, from: Vector3, direction: Vector3) -> Vector3:
	var along := Vector3(direction.x, 0.0, direction.z).normalized()
	var rel := Vector3(point.x - from.x, 0.0, point.z - from.z)
	return rel - along * rel.dot(along)


## Where a shot flying from `from` with `velocity` comes down to the ground
## height `floor_y`, or Vector3.INF if it isn't descending.
static func floor_point(from: Vector3, velocity: Vector3, floor_y: float) -> Vector3:
	if velocity.y > -0.05:
		return Vector3.INF
	var t := (from.y - floor_y) / -velocity.y
	return from + velocity * t if t >= 0.0 else Vector3.INF


## How steady a heading is: 1 for someone running in a straight line, near 0
## for someone jinking back and forth. `mean_velocity` and `mean_speed` are
## averages over the same recent window.
static func heading_steadiness(mean_velocity: Vector3, mean_speed: float) -> float:
	if mean_speed < 0.5:
		return 0.0
	return clampf(Vector2(mean_velocity.x, mean_velocity.z).length() / mean_speed, 0.0, 1.0)
