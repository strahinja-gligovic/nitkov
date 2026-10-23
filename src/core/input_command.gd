class_name InputCommand
extends RefCounted
## One physics tick of intent for one fighter. PlayerInput and BotBrain both
## produce these and Fighter consumes them, so the simulation never touches
## devices. Once multiplayer exists, this is what crosses the network.

const LIGHT := 1
const HEAVY := 2
const BLOCK := 4
const DASH := 8
const SPRINT := 16
const PRIMARY := 32
const SIGNATURE := 64
const RUNE := 128

## Desired movement in world space (x, z), length <= 1.
var move := Vector2.ZERO
## Where the fighter wants to face, in radians (same convention as Node3D.rotation.y).
var aim_yaw := 0.0
## World point under the crosshair; spells fly toward it.
var aim_target := Vector3.ZERO
## Buttons currently held (bit flags above).
var held := 0
## Buttons pressed since the previous command; edges survive taps shorter than a tick.
var pressed := 0


func is_held(button: int) -> bool:
	return held & button != 0


func was_pressed(button: int) -> bool:
	return pressed & button != 0


func move_3d() -> Vector3:
	return Vector3(move.x, 0.0, move.y)
