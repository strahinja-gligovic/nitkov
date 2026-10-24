class_name UiIconPicker
extends HBoxContainer
## A compact row of icon buttons, one per choice (spells or runes), exactly
## one selected. The selected one is lit with a gold frame; the rest are dimmed.
## Each button names its choice in a tooltip. Used for the opponent's picks.

signal picked(id: StringName)

const SIDE := 50.0

var _buttons: Array[Button] = []
var _group := ButtonGroup.new()


## Fills the row with one button per item (SpellData or RuneData).
func setup(items: Array) -> void:
	add_theme_constant_override(&"separation", 8)
	for item: Resource in items:
		var button := Button.new()
		button.toggle_mode = true
		button.button_group = _group
		button.focus_mode = Control.FOCUS_ALL
		button.custom_minimum_size = Vector2(SIDE, SIDE)
		button.tooltip_text = item.display_name
		button.set_meta(&"id", item.id)
		var accent := UiIcons.accent_of(item.id)
		button.add_theme_stylebox_override(&"normal", _box(Color(0.1, 0.06, 0.14), UiTheme.INK, 2))
		button.add_theme_stylebox_override(&"hover", _box(Color(0.18, 0.11, 0.24), accent, 2))
		button.add_theme_stylebox_override(&"pressed", _box(accent.darkened(0.62), UiTheme.GOLD, 3, accent))
		button.add_theme_stylebox_override(&"hover_pressed", _box(accent.darkened(0.55), UiTheme.GOLD, 3, accent))
		button.add_theme_stylebox_override(&"focus", _focus_box())
		var icon := UiIconView.new(item.id, SIDE)
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.fill = 0.74
		button.add_child(icon)
		button.toggled.connect(func(on: bool) -> void: icon.dim = 0.0 if on else 0.45)
		button.pressed.connect(func() -> void: picked.emit(button.get_meta(&"id")))
		icon.dim = 0.45
		add_child(button)
		_buttons.append(button)


## Lights up the button for `id` without emitting `picked`.
func select(id: StringName) -> void:
	for button in _buttons:
		var on: bool = button.get_meta(&"id") == id
		button.set_pressed_no_signal(on)
		(button.get_child(0) as UiIconView).dim = 0.0 if on else 0.45


func first_button() -> Button:
	return _buttons[0] if not _buttons.is_empty() else null


static func _box(fill: Color, border: Color, width: int, glow := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(8)
	box.anti_aliasing = true
	if glow.a > 0.0:
		box.shadow_color = Color(glow, 0.55)
		box.shadow_size = 7
	return box


static func _focus_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.draw_center = false
	box.border_color = Color.WHITE
	box.set_border_width_all(2)
	box.set_corner_radius_all(10)
	box.set_expand_margin_all(4)
	return box
