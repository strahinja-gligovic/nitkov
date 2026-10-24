class_name UiNotice
extends Control
## A modal one-line notice ("COMING SOON!") in the menu's panel style: the
## screen behind is dimmed and a centred panel holds a gold heading and an OK
## button. OK, Esc / controller B, or a click outside the panel closes it,
## and focus goes back to the control that opened it.

signal closed

var _return_focus: Control
var _ok: Button


## Opens a notice over `parent` (it fills the parent's rect and inherits its theme).
static func open(parent: Control, text: String, return_focus: Control = null) -> UiNotice:
	var notice := UiNotice.new()
	notice.name = "Notice"
	notice._return_focus = return_focus
	parent.add_child(notice)
	notice.heading().text = text
	notice._ok.grab_focus()
	return notice


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP  # clicks outside the panel land here
	var dim := ColorRect.new()
	dim.color = Color(UiTheme.INK, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 44)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 26)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 26)
	margin.add_child(box)
	var label := UiTheme.title("", 54)
	label.name = "Heading"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(420, 0)
	box.add_child(label)
	_ok = Button.new()
	_ok.text = "OK"
	_ok.custom_minimum_size = Vector2(180, 56)
	_ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_ok.add_theme_font_size_override(&"font_size", 26)
	_ok.pressed.connect(close)
	# Keep controller focus inside the notice instead of wandering to the menu behind it.
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		_ok.set_focus_neighbor(side, ^".")
	_ok.focus_next = ^"."
	_ok.focus_previous = ^"."
	box.add_child(_ok)


func heading() -> Label:
	return find_child("Heading", true, false) as Label


func ok_button() -> Button:
	return _ok


func close() -> void:
	if is_queued_for_deletion():
		return
	if is_instance_valid(_return_focus) and _return_focus.is_visible_in_tree():
		_return_focus.grab_focus()
	closed.emit()
	queue_free()


func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		close()
		accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
