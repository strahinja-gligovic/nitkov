class_name PickCard
extends Button
## A selectable card in the start menu (a spell or a rune): an element
## stripe, a name, a stat line and a short description. It's a real Button,
## so mouse, keyboard and controller focus all work.

var payload := &""

var _accent := Color.WHITE


func setup(id: StringName, title: String, stats: String, body: String, accent: Color) -> void:
	payload = id
	_accent = accent
	toggle_mode = true
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(236, 152)
	clip_contents = true
	_apply_styles()

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: StringName in [&"margin_left", &"margin_right"]:
		margin.add_theme_constant_override(side, 14)
	margin.add_theme_constant_override(&"margin_top", 12)
	margin.add_theme_constant_override(&"margin_bottom", 10)
	add_child(margin)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override(&"separation", 4)
	margin.add_child(box)

	var stripe := ColorRect.new()
	stripe.color = accent
	stripe.custom_minimum_size = Vector2(0, 6)
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(stripe)
	box.add_child(_label(title, 22, accent.lightened(0.35)))
	box.add_child(_label(stats, 14, UiTheme.GOLD))
	var description := _label(body, 14, UiTheme.TEXT)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(description)


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", color)
	return label


func _apply_styles() -> void:
	add_theme_stylebox_override(&"normal", _box(Color(0.12, 0.08, 0.17, 0.95), _accent.darkened(0.35), 3))
	add_theme_stylebox_override(&"hover", _box(Color(0.18, 0.12, 0.24, 0.97), _accent, 3))
	add_theme_stylebox_override(&"pressed", _box(Color(0.24, 0.15, 0.3, 1.0), UiTheme.GOLD, 5))
	add_theme_stylebox_override(&"hover_pressed", _box(Color(0.27, 0.17, 0.33, 1.0), UiTheme.GOLD, 5))
	add_theme_stylebox_override(&"focus", _box(Color(0, 0, 0, 0), Color.WHITE, 2))


static func _box(fill: Color, border: Color, width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(10)
	box.shadow_color = Color(0, 0, 0, 0.35)
	box.shadow_size = 6
	return box
