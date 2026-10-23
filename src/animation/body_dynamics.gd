class_name BodyDynamics
extends RefCounted
## Whole-body secondary motion on two pivot nodes, presentation only:
##   yaw: the visual body follows the simulation's facing through a fast spring
##        instead of snapping like a turret;
##   lean: pitch and roll into acceleration and turns (applied to the spine by
##         LeanModifier, so the feet stay planted); a shove takes over the
##         lean, so the chest goes with the push while the feet drag behind;
##   squash: stretch on take-off and dash starts, squash on landings and hits;
##   tumble: a shove that lifts you off your feet tips the whole body about
##           the hips and spins it a little, and it rights itself on landing
##           (wind);
##   recoil: a hard knock jerks the whole body back and it springs into place
##           (fire).

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
## The shove carrying the body (world, horizontal), whether it's off the
## ground, and how much the shove is wind (0..1, which lifts and tumbles).
var _shove := Vector3.ZERO
var _airborne := false
var _wind := 0.0
## Whole-body tilt about the hips, a world rotation vector, and the extra yaw of a tumble.
var _tilt := Vector3.ZERO
var _tilt_velocity := Vector3.ZERO
var _twist := 0.0
var _twist_velocity := 0.0
## Whole-body offset (world) of a hard knock.
var _recoil := Vector3.ZERO
var _recoil_velocity := Vector3.ZERO


func reset(yaw: float) -> void:
	_yaw = yaw
	_yaw_velocity = 0.0
	_lean = Vector2.ZERO
	_lean_velocity = Vector2.ZERO
	_squash = 0.0
	_squash_velocity = 0.0
	_stretch = 0.0
	_shove = Vector3.ZERO
	_airborne = false
	_wind = 0.0
	_tilt = Vector3.ZERO
	_tilt_velocity = Vector3.ZERO
	_twist = 0.0
	_twist_velocity = 0.0
	_recoil = Vector3.ZERO
	_recoil_velocity = Vector3.ZERO
	_initialized = true


func squash(amount: float) -> void:
	_squash_velocity += amount * 26.0


## Stretch along a local direction (e.g. the dash direction) for a moment.
func stretch_along(local_dir: Vector3, amount: float) -> void:
	_stretch_axis = local_dir.normalized()
	_stretch = amount


## What's carrying the body this frame: the shove's velocity (world,
## horizontal), whether the feet are off the ground, and how much of the
## shove is wind (0..1).
func carry(shove: Vector3, airborne: bool, wind: float) -> void:
	_shove = Vector3(shove.x, 0.0, shove.z)
	_airborne = airborne
	_wind = clampf(wind, 0.0, 1.0)


## A hard knock along `world_dir`: the whole body jerks that way (about
## `amount` x 7 cm at the peak) and springs back with one rebound.
func recoil(world_dir: Vector3, amount: float) -> void:
	var flat := Vector3(world_dir.x, 0.0, world_dir.z)
	if flat.length() > 0.001:
		_recoil_velocity += flat.normalized() * amount * 2.4


## Spins the body about its own up axis (radians per second), e.g. as a
## burst throws it; the spin dies out and unwinds on its own.
func spin(speed: float) -> void:
	_twist_velocity += speed


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
	# a real shove takes over: the chest goes with it, the feet drag behind
	var shove_weight := clampf((_shove.length() - 1.0) / 3.0, 0.0, 1.0) * lerpf(0.4, 1.0, _wind)
	if shove_weight > 0.0:
		var with_shove := Vector2(clampf(0.06 * _shove.dot(forward), -0.42, 0.42),
				clampf(0.06 * _shove.dot(right), -0.32, 0.32))
		target = target.lerp(with_shove, shove_weight)
	_lean_velocity += (196.0 * (target - _lean) - 19.6 * _lean_velocity) * delta
	_lean += _lean_velocity * delta
	# squash: omega 25, zeta 0.35 (bouncy)
	_squash_velocity += (-625.0 * _squash - 17.5 * _squash_velocity) * delta
	_squash += _squash_velocity * delta
	_stretch = move_toward(_stretch, 0.0, delta / 0.12 * maxf(absf(_stretch), 0.01))
	_update_tumble(delta)


## Off the ground in a gale, the body tips over with the shove (top first,
## legs trailing) and lags behind it; back on its feet it rights itself fast.
func _update_tumble(delta: float) -> void:
	var tilt_target := Vector3.ZERO
	var speed := _shove.length()
	if _airborne and _wind > 0.0 and speed > 0.5:
		var axis := Vector3.UP.cross(_shove / speed)
		tilt_target = axis * clampf(speed * 0.085, 0.0, 1.05) * _wind
	var omega := 9.0 if _airborne else 15.0
	var left := minf(delta, 0.1)
	while left > 0.0:
		var dt := minf(left, 1.0 / 240.0)
		left -= dt
		_tilt_velocity += (omega * omega * (tilt_target - _tilt) - 1.1 * omega * _tilt_velocity) * dt
		_tilt += _tilt_velocity * dt
		# the spin unwinds slowly in the air and quickly once standing
		var unwind := 5.0 if _airborne else 13.0
		_twist_velocity += (-unwind * unwind * _twist - 1.3 * unwind * _twist_velocity) * dt
		_twist += _twist_velocity * dt
		# recoil: omega 22, zeta 0.45 (one rebound)
		_recoil_velocity += (-484.0 * _recoil - 19.8 * _recoil_velocity) * dt
		_recoil += _recoil_velocity * dt


## The visual's yaw relative to the simulated body (the body snaps; we don't),
## a tumble's spin included.
func yaw_offset(sim_yaw: float) -> float:
	return wrapf(_yaw - sim_yaw + _twist, -PI, PI)


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


## The whole body's tilt (a world rotation) about `pivot`, the point it
## turns around (the hips), as a transform for the body's root at the feet.
func tumble_transform(pivot: Vector3) -> Transform3D:
	var angle := _tilt.length()
	var tilt := Basis(_tilt / angle, angle) if angle > 0.0005 else Basis()
	return Transform3D(tilt, pivot - tilt * pivot + _recoil)
