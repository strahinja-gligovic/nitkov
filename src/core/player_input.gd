class_name PlayerInput
extends Node
## Turns keyboard/mouse or controller input into InputCommands for the local
## fighter. Look input turns the camera rig; everything the simulation needs
## goes into the command.

const BUTTONS := {
	&"light_attack": InputCommand.LIGHT,
	&"heavy_attack": InputCommand.HEAVY,
	&"block": InputCommand.BLOCK,
	&"dash": InputCommand.DASH,
	&"sprint": InputCommand.SPRINT,
	&"cast_primary": InputCommand.PRIMARY,
	&"cast_signature": InputCommand.SIGNATURE,
	&"rune": InputCommand.RUNE,
}

@export var mouse_sensitivity := 0.0024
## Radians per second at full right-stick deflection.
@export var stick_speed := 3.4

var camera_rig: CameraRig
## The fighter this input drives (for the debug quick-swap).
var fighter: Fighter
## False while a menu is open: the fighter idles and the mouse is free.
var enabled := true
var using_gamepad := false

var _pressed := 0
var _prev_held := 0
var _sprint_latched := false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.4):
		using_gamepad = true
	elif event is InputEventKey or event is InputEventMouseButton:
		using_gamepad = false
	if not enabled:
		return
	if event.is_action_pressed(&"release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if event.is_action_pressed(&"swap_gauntlet") and fighter:
		# debug shortcut that edits the loadout directly; online it would be a request to the server
		fighter.cycle_gauntlet()
		return
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return  # the click that grabs the mouse shouldn't also swing
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		using_gamepad = false
		var motion: Vector2 = event.screen_relative
		camera_rig.rotate_view(-motion.x * mouse_sensitivity, -motion.y * mouse_sensitivity)
		return
	# Catch taps that start and end between two physics ticks. Trigger axes are
	# skipped: their motion events repeat while held, so their presses come from
	# held-state edges in get_command() instead.
	if event is InputEventJoypadMotion:
		return
	for action: StringName in BUTTONS:
		if event.is_action_pressed(action):
			_pressed |= BUTTONS[action]


func _process(delta: float) -> void:
	if not enabled or camera_rig == null:
		return
	var look := Input.get_vector(&"look_left", &"look_right", &"look_up", &"look_down")
	if look != Vector2.ZERO:
		# squared response curve: fine aim near the centre, fast turns at full tilt
		look = look * look.length()
		var speed := stick_speed * delta * _look_scale()
		camera_rig.rotate_view(-look.x * speed, -look.y * speed * 0.75)


## Look speed multiplier; aim assist hooks in here.
func _look_scale() -> float:
	return 1.0


func get_command(fighter: Fighter) -> InputCommand:
	var cmd := InputCommand.new()
	cmd.aim_yaw = camera_rig.yaw
	cmd.aim_target = camera_rig.aim_point(fighter.chest_position(), [fighter.get_rid()])
	if not enabled:
		_pressed = 0
		return cmd
	var raw := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var world := Basis(Vector3.UP, camera_rig.yaw) * Vector3(raw.x, 0.0, raw.y)
	cmd.move = Vector2(world.x, world.z).limit_length(1.0)
	for action: StringName in BUTTONS:
		if Input.is_action_pressed(action):
			cmd.held |= BUTTONS[action]
	_update_sprint_latch(cmd)
	cmd.pressed = _pressed | (cmd.held & ~_prev_held)
	_prev_held = cmd.held
	_pressed = 0
	return cmd


## On a controller, clicking L3 keeps you sprinting until you stop moving.
func _update_sprint_latch(cmd: InputCommand) -> void:
	if cmd.move.length() < 0.2:
		_sprint_latched = false
	elif using_gamepad and _pressed & InputCommand.SPRINT:
		_sprint_latched = true
	if _sprint_latched:
		cmd.held |= InputCommand.SPRINT
