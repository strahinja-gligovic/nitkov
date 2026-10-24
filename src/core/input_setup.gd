extends Node
## Registers every gameplay action in code, so all bindings live in one readable
## place. Rebind by editing _ready(); the editor's Input Map tab isn't used.


func _ready() -> void:
	_bind(&"move_forward", [_key(KEY_W), _axis(JOY_AXIS_LEFT_Y, -1.0)])
	_bind(&"move_back", [_key(KEY_S), _axis(JOY_AXIS_LEFT_Y, 1.0)])
	_bind(&"move_left", [_key(KEY_A), _axis(JOY_AXIS_LEFT_X, -1.0)])
	_bind(&"move_right", [_key(KEY_D), _axis(JOY_AXIS_LEFT_X, 1.0)])
	_bind(&"look_up", [_axis(JOY_AXIS_RIGHT_Y, -1.0)], 0.15)
	_bind(&"look_down", [_axis(JOY_AXIS_RIGHT_Y, 1.0)], 0.15)
	_bind(&"look_left", [_axis(JOY_AXIS_RIGHT_X, -1.0)], 0.15)
	_bind(&"look_right", [_axis(JOY_AXIS_RIGHT_X, 1.0)], 0.15)

	_bind(&"light_attack", [_mouse(MOUSE_BUTTON_LEFT), _pad(JOY_BUTTON_RIGHT_SHOULDER)])
	_bind(&"heavy_attack", [_key(KEY_F), _mouse(MOUSE_BUTTON_XBUTTON1), _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)], 0.4)
	_bind(&"block", [_mouse(MOUSE_BUTTON_RIGHT), _pad(JOY_BUTTON_LEFT_SHOULDER)])
	_bind(&"dash", [_key(KEY_SPACE), _pad(JOY_BUTTON_A)])
	_bind(&"sprint", [_key(KEY_SHIFT), _pad(JOY_BUTTON_LEFT_STICK)])
	_bind(&"cast_primary", [_key(KEY_E), _axis(JOY_AXIS_TRIGGER_LEFT, 1.0)], 0.4)
	_bind(&"cast_signature", [_key(KEY_Q), _pad(JOY_BUTTON_Y)])
	_bind(&"rune", [_key(KEY_R), _pad(JOY_BUTTON_B)])

	_bind(&"loadout_menu", [_key(KEY_TAB), _pad(JOY_BUTTON_START)])
	_bind(&"swap_primary", [_key(KEY_T), _pad(JOY_BUTTON_DPAD_RIGHT)])
	_bind(&"show_controls", [_key(KEY_H)])
	_bind(&"release_mouse", [_key(KEY_ESCAPE)])
	_bind(&"debug_tuning", [_key(KEY_F1), _pad(JOY_BUTTON_BACK)])
	_bind(&"debug_hitboxes", [_key(KEY_F2), _pad(JOY_BUTTON_DPAD_UP)])
	_bind(&"debug_slowmo", [_key(KEY_F3), _pad(JOY_BUTTON_DPAD_DOWN)])
	_bind(&"debug_log", [_key(KEY_F4), _pad(JOY_BUTTON_DPAD_LEFT)])

	# Godot's ui_cancel is Esc only; B backs out of menus and notices too.
	InputMap.action_add_event(&"ui_cancel", _pad(JOY_BUTTON_B))


func _bind(action: StringName, events: Array, deadzone := 0.2) -> void:
	if InputMap.has_action(action):
		InputMap.erase_action(action)
	InputMap.add_action(action, deadzone)
	for event: InputEvent in events:
		InputMap.action_add_event(action, event)


static func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code  # physical, so WASD stays put on AZERTY etc.
	return event


static func _mouse(button: MouseButton) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	return event


static func _pad(button: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	return event


static func _axis(axis: JoyAxis, direction: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = direction
	return event
