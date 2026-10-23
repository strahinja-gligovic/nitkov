class_name TuningPanel
extends Control
## Live editor for the data resources, generated from their exported
## properties: change a number and the game uses it on the very next tick
## (everything reads the shared GameData instances). "Save" writes the
## resources back to their .tres files under data/.

var sections: Array = []  # [title: String, resource: Resource]

var _editors := {}  # "<instance id>:<property>" -> Control
var _status: Label
var _dirty := false


## `entries` is a list of [title, Resource] pairs, one collapsible section each.
func setup(entries: Array) -> void:
	sections = entries
	_build()


## The editor widget for one property (used by tests).
func editor_for(resource: Resource, property: String) -> Control:
	return _editors.get("%d:%s" % [resource.get_instance_id(), property])


func save_all() -> PackedStringArray:
	var written := PackedStringArray()
	for entry: Array in sections:
		var resource: Resource = entry[1]
		if resource.resource_path.begins_with("res://") and resource.resource_path.ends_with(".tres"):
			if ResourceSaver.save(resource) == OK:
				written.append(resource.resource_path)
	_dirty = false
	_status.text = "Saved %d files" % written.size()
	return written


func _build() -> void:
	set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	offset_left = -470.0
	theme = UiTheme.make()
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override(&"separation", 8)
	panel.add_child(outer)
	outer.add_child(UiTheme.title("Tuning  (F1)", 26))
	var bar := HBoxContainer.new()
	var save := Button.new()
	save.text = "Save to data/"
	save.pressed.connect(save_all)
	bar.add_child(save)
	_status = Label.new()
	_status.text = "Edits apply live"
	_status.add_theme_font_size_override(&"font_size", 15)
	_status.add_theme_color_override(&"font_color", UiTheme.MUTED)
	bar.add_child(_status)
	outer.add_child(bar)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for i in sections.size():
		_add_resource(list, sections[i][0], sections[i][1], 0, i == 0)


func _add_resource(parent: Control, title: String, resource: Resource, depth: int, open := false) -> void:
	var header := Button.new()
	header.toggle_mode = true
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.add_theme_font_size_override(&"font_size", 18 - depth * 2)
	var body := VBoxContainer.new()
	var indent := MarginContainer.new()
	indent.add_theme_constant_override(&"margin_left", 14)
	indent.add_child(body)
	header.toggled.connect(func(on: bool) -> void:
		indent.visible = on
		header.text = ("v  " if on else ">  ") + title)
	header.button_pressed = open
	header.text = ("v  " if open else ">  ") + title
	indent.visible = open
	parent.add_child(header)
	parent.add_child(indent)

	var pending_group := ""
	for prop: Dictionary in resource.get_property_list():
		var usage: int = prop["usage"]
		if usage & PROPERTY_USAGE_GROUP:
			pending_group = String(prop["name"])  # shown only if a row follows
			continue
		if not (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) or not (usage & PROPERTY_USAGE_EDITOR):
			continue
		if prop["hint"] == PROPERTY_HINT_ENUM or not prop["type"] in [TYPE_FLOAT, TYPE_INT, TYPE_BOOL, TYPE_OBJECT, TYPE_ARRAY]:
			continue  # ids, names and element types aren't tuning knobs
		if pending_group != "":
			var group := Label.new()
			group.text = pending_group
			group.add_theme_color_override(&"font_color", UiTheme.GOLD)
			group.add_theme_font_size_override(&"font_size", 15)
			body.add_child(group)
			pending_group = ""
		var name: String = prop["name"]
		var value: Variant = resource.get(name)
		match prop["type"]:
			TYPE_FLOAT, TYPE_INT:
				_number_row(body, resource, name, value, prop["type"] == TYPE_INT)
			TYPE_BOOL:
				_bool_row(body, resource, name, value)
			TYPE_OBJECT:
				if value is Resource:
					_add_resource(body, name.capitalize(), value, depth + 1)
			TYPE_ARRAY:
				for i in (value as Array).size():
					if value[i] is Resource:
						_add_resource(body, "%s %d" % [name.capitalize(), i + 1], value[i], depth + 1)


func _number_row(parent: Control, resource: Resource, property: String, value: float, integer: bool) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = property.capitalize()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override(&"font_size", 15)
	row.add_child(label)
	var spin := SpinBox.new()
	spin.step = 1.0 if integer else (0.005 if absf(value) < 1.0 else 0.05)
	spin.min_value = 0.0
	spin.max_value = maxf(10.0, absf(value) * 4.0)
	spin.allow_greater = true
	spin.allow_lesser = true
	spin.custom_minimum_size = Vector2(120, 0)
	spin.value = value
	spin.value_changed.connect(func(v: float) -> void:
		resource.set(property, int(v) if integer else v)
		_mark_dirty())
	row.add_child(spin)
	parent.add_child(row)
	_editors["%d:%s" % [resource.get_instance_id(), property]] = spin


func _bool_row(parent: Control, resource: Resource, property: String, value: bool) -> void:
	var check := CheckBox.new()
	check.text = property.capitalize()
	check.button_pressed = value
	check.add_theme_font_size_override(&"font_size", 15)
	check.toggled.connect(func(on: bool) -> void:
		resource.set(property, on)
		_mark_dirty())
	parent.add_child(check)
	_editors["%d:%s" % [resource.get_instance_id(), property]] = check


func _mark_dirty() -> void:
	if not _dirty:
		_dirty = true
		_status.text = "Unsaved changes (live)"
