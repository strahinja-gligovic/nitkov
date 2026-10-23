class_name TickSmoother
extends RefCounted
## Draws a simulated node between its last two physics ticks. The simulation
## steps at a fixed 60 Hz; on a faster screen anything that only moves on
## ticks judders, so presentation reads position() instead, which slides from
## the previous tick to the current one. Big jumps (blink, respawn) snap.
##
## Off on 60 Hz screens and fixed-fps runs, where it would only add a tick of lag.

const SNAP_DISTANCE := 2.0

static var _enabled := -1  # -1 = not decided yet

## Where the target was before its last jump (see tick()).
var jumped_from := Vector3.ZERO

var _target: Node3D
var _previous := Vector3.ZERO
var _current := Vector3.ZERO


func _init(target: Node3D) -> void:
	_target = target
	reset()


static func is_enabled() -> bool:
	if _enabled < 0:
		var faster_screen := DisplayServer.screen_get_refresh_rate() > Engine.physics_ticks_per_second * 1.1
		_enabled = 1 if faster_screen and not OS.get_cmdline_args().has("--fixed-fps") else 0
	return _enabled == 1


## Call once per physics tick, after the target has moved. Returns true if
## the target jumped (and the drawing snapped); `jumped_from` says from where.
func tick() -> bool:
	var now := _target.global_position
	var jumped := now.distance_to(_current) >= SNAP_DISTANCE
	if jumped:
		jumped_from = _current
	_previous = now if jumped else _current
	_current = now
	return jumped


## Forget the trail, e.g. after a teleport the snap rule would not catch.
func reset() -> void:
	_current = _target.global_position
	_previous = _current


func position() -> Vector3:
	if not is_enabled():
		return _target.global_position
	return _previous.lerp(_current, Engine.get_physics_interpolation_fraction())
