extends GutTest
## The "coming soon" notice: the title screen's MULTIPLAYER button opens it,
## and OK, Esc / B or a click outside the panel close it and hand focus back.

var _host: Control
var _opener: Button


func before_each() -> void:
	_host = Control.new()
	_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_host.theme = UiTheme.make()
	add_child_autofree(_host)
	_opener = Button.new()
	_opener.text = "OPENER"
	_host.add_child(_opener)


func _cancel_event() -> InputEventAction:
	var event := InputEventAction.new()
	event.action = &"ui_cancel"
	event.pressed = true
	return event


func test_open_shows_the_text_and_focuses_ok() -> void:
	var notice := UiNotice.open(_host, "COMING SOON!", _opener)
	assert_eq(notice.heading().text, "COMING SOON!")
	assert_true(notice.ok_button().has_focus())


func test_ok_closes_and_returns_focus() -> void:
	var notice := UiNotice.open(_host, "COMING SOON!", _opener)
	watch_signals(notice)
	notice.ok_button().pressed.emit()
	assert_signal_emitted(notice, "closed")
	assert_true(notice.is_queued_for_deletion())
	assert_true(_opener.has_focus())


func test_cancel_closes() -> void:
	var notice := UiNotice.open(_host, "COMING SOON!", _opener)
	notice._unhandled_input(_cancel_event())
	assert_true(notice.is_queued_for_deletion())
	assert_true(_opener.has_focus())


func test_click_outside_the_panel_closes() -> void:
	var notice := UiNotice.open(_host, "COMING SOON!", _opener)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	notice._gui_input(click)
	assert_true(notice.is_queued_for_deletion())


func test_controller_focus_stays_on_ok() -> void:
	var notice := UiNotice.open(_host, "COMING SOON!", _opener)
	var ok := notice.ok_button()
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		assert_eq(ok.get_node(ok.get_focus_neighbor(side)), ok)
	assert_eq(ok.find_next_valid_focus(), ok)
	assert_eq(ok.find_prev_valid_focus(), ok)


func test_esc_and_controller_b_are_cancel() -> void:
	var keys := []
	var pads := []
	for event in InputMap.action_get_events(&"ui_cancel"):
		if event is InputEventKey:
			keys.append((event as InputEventKey).keycode)
		elif event is InputEventJoypadButton:
			pads.append((event as InputEventJoypadButton).button_index)
	assert_has(keys, KEY_ESCAPE)
	assert_has(pads, JOY_BUTTON_B)


func test_title_screen_multiplayer_button_opens_the_notice() -> void:
	var menu: MainMenu = load("res://src/ui/main_menu.tscn").instantiate()
	add_child_autofree(menu)
	var labels := []
	for button: Button in menu._title_screen.find_children("*", "Button", true, false):
		labels.append(button.text)
	assert_eq(labels, ["PLAY", "MULTIPLAYER", "QUIT"])
	menu._multiplayer_button.pressed.emit()
	var notice := menu.get_node_or_null("Notice") as UiNotice
	assert_not_null(notice)
	assert_eq(notice.heading().text, "COMING SOON!")
	assert_true(menu._title_screen.visible, "the title screen stays up behind the notice")
	notice.close()
	assert_true(menu._multiplayer_button.has_focus())
