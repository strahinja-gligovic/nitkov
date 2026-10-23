class_name BodyDynamics
extends RefCounted
## Whole-body secondary motion on two pivot nodes, presentation only:
##   yaw: the visual body follows the simulation's facing through a fast spring
##        instead of snapping like a turret;
##   lean: pitch and roll into acceleration and turns (applied to the spine by
##         LeanModifier, so the feet stay planted);
##   squash: stretch on take-off and dash starts, squash on landings and hits.

## Springs as [value, velocity].
var _yaw := 0.0
var _yaw_velocity := 0.0
var _lean := Vector2.ZERO  # x = pitch (forward +), y = roll (right +)
var _lean_velocity := Vector2.ZERO
var _squash := 0.0  # + squash (wider, shorter), - stretch
var _squash_velocity := 0.0
var _stretch_axis := Vector3.ZERO  # local axis of a directional stretch (dashes)
var _stretch := 0.0
var _last_velocity := Vector3.ZERO
var _accel := Vector3.ZERO
var _initialized := false


func reset(yaw: float) -> void:
	_yaw = yaw
	_yaw_velocity = 0.0
	_lean = Vector2.ZERO
	_lean_velocity = Vector2.ZERO
	_squash = 0.0
	_squash_velocity = 0.0
	_stretch = 0.0
	_initialized = true


func squash(amount: float) -> void:
	_squash_velocity += amount * 26.0


## Stretch along a local direction (e.g. the dash direction) for a moment.
func stretch_along(local_dir: Vector3, amount: float) -> void:
	_stretch_axis = local_dir.normalized()
	_stretch = amount


## Advances the springs. `sim_yaw` is the fighter's facing, `velocity` its
## world velocity; returns nothing, then call apply() with the pivots.
func update(delta: float, sim_yaw: float, velocity: Vector3) -> void:
	if not _initialized:
		reset(sim_yaw)
	if delta <= 0.0:
		return
	# yaw: omega 26, critically damped -> big turns resolve in ~0.15 s
	var error := wrapf(sim_yaw - _yaw, -PI, PI)
	_yaw_velocity += (676.0 * error - 52.0 * _yaw_velocity) * delta
	_yaw = wrapf(_yaw + _yaw_velocity * delta, -PI, PI)
	# lean from low-passed acceleration in the body's frame
	var planar := Vector3(velocity.x, 0.0, velocity.z)
	var raw_accel := (planar - _last_velocity) / delta
	_last_velocity = planar
	_accel = _accel.lerp(raw_accel, 1.0 - exp(-15.0 * delta))
	var forward := CombatRules.yaw_to_dir(_yaw)
	var right := Vector3(-forward.z, 0.0, forward.x)
	var target := Vector2(
			clampf(0.012 * _accel.dot(forward), -0.2, 0.2),
			clampf(0.012 * _accel.dot(right) + 0.004 * _yaw_velocity * planar.length(), -0.15, 0.15))
	_lean_velocity += (196.0 * (target - _lean) - 19.6 * _lean_velocity) * delta
	_lean += _lean_velocity * delta
	# squash: omega 25, zeta 0.35 (bouncy)
	_squash_velocity += (-625.0 * _squash - 17.5 * _squash_velocity) * delta
	_squash += _squash_velocity * delta
	_stretch = move_toward(_stretch, 0.0, delta / 0.12 * maxf(absf(_stretch), 0.01))


## The visual's yaw relative to the simulated body (the body snaps; we don't).
func yaw_offset(sim_yaw: float) -> float:
	return wrapf(_yaw - sim_yaw, -PI, PI)


## Radians: x = pitch (forward +), y = roll (toward the right +).
func lean() -> Vector2:
	return _lean


## Squash and stretch for the body's pivot (which sits at the feet).
func squash_basis() -> Basis:
	var basis := Basis()
	var s := clampf(_squash, -0.3, 0.3)
	var scale := Vector3(1.0 + s * 0.5, 1.0 - s, 1.0 + s * 0.5)
	if absf(_stretch) > 0.001:
		var axis := _stretch_axis
		var along := Vector3(absf(axis.x), absf(axis.y), absf(axis.z))
		scale *= Vector3.ONE + along * _stretch - (Vector3.ONE - along) * _stretch * 0.5
	return basis * Basis.from_scale(scale)
