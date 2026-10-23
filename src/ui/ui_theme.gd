class_name UiTheme
extends RefCounted
## The shared comic-book UI look: dark violet panels with a gold ink border,
## chunky buttons. Built in code so every screen stays consistent.

const INK := Color(0.06, 0.03, 0.09)
const PANEL := Color(0.11, 0.07, 0.16, 0.94)
const GOLD := Color(1.0, 0.78, 0.3)
const TEXT := Color(0.98, 0.94, 0.86)
const MUTED := Color(0.72, 0.66, 0.78)


static func make() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 20
	theme.set_stylebox(&"panel", &"PanelContainer", _box(PANEL, GOLD, 4, 12))
	theme.set_stylebox(&"panel", &"Panel", _box(PANEL, GOLD, 4, 12))
	theme.set_stylebox(&"normal", &"Button", _box(Color(0.2, 0.13, 0.27), INK, 3, 8))
	theme.set_stylebox(&"hover", &"Button", _box(Color(0.3, 0.2, 0.4), GOLD, 3, 8))
	theme.set_stylebox(&"pressed", &"Button", _box(Color(0.42, 0.28, 0.5), GOLD, 3, 8))
	theme.set_stylebox(&"focus", &"Button", _box(Color(0, 0, 0, 0), GOLD, 3, 8))
	for kind: StringName in [&"OptionButton", &"SpinBox", &"LineEdit"]:
		theme.set_stylebox(&"normal", kind, _box(Color(0.2, 0.13, 0.27), INK, 3, 8))
		theme.set_stylebox(&"focus", kind, _box(Color(0, 0, 0, 0), GOLD, 3, 8))
	theme.set_stylebox(&"hover", &"OptionButton", _box(Color(0.3, 0.2, 0.4), GOLD, 3, 8))
	theme.set_stylebox(&"pressed", &"OptionButton", _box(Color(0.42, 0.28, 0.5), GOLD, 3, 8))
	theme.set_color(&"font_color", &"Label", TEXT)
	theme.set_color(&"font_color", &"Button", TEXT)
	theme.set_color(&"font_color", &"OptionButton", TEXT)
	theme.set_color(&"font_outline_color", &"Label", INK)
	theme.set_constant(&"outline_size", &"Label", 4)
	return theme


static func _box(fill: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(radius)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	return box


static func title(text: String, size := 30) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", GOLD)
	label.add_theme_constant_override(&"outline_size", 8)
	return label
