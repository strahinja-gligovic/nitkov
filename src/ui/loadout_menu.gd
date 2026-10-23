class_name LoadoutMenu
extends CanvasLayer
## Tab / Start: choose gauntlets and runes for you and the bot. Changes apply
## immediately. The fight keeps running underneath.

signal opened
signal closed

var player: Fighter
var bot: Fighter
## Extra rows for the bot (mode, difficulty) are added here by TrainingMode.
var bot_section: VBoxContainer

var _pickers := {}  # "<who>/<slot>" -> OptionButton
var _first_focus: Control


func _ready() -> void:
	layer = 10
	visible = false
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiTheme.make()
	add_child(root)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 14)
	panel.add_child(box)
	box.add_child(UiTheme.title("Loadout"))

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override(&"h_separation", 18)
	grid.add_theme_constant_override(&"v_separation", 10)
	box.add_child(grid)
	for heading in ["", "You", "Bot"]:
		var label := Label.new()
		label.text = heading
		label.add_theme_color_override(&"font_color", UiTheme.GOLD)
		grid.add_child(label)
	_add_row(grid, "Gauntlet", "gauntlet", GameData.gauntlets)
	_add_row(grid, "Rune", "rune", GameData.runes)

	bot_section = VBoxContainer.new()
	bot_section.add_theme_constant_override(&"separation", 10)
	box.add_child(bot_section)

	var hint := Label.new()
	hint.text = "T / D-pad right: quick-swap gauntlet mid-fight"
	hint.add_theme_color_override(&"font_color", UiTheme.MUTED)
	hint.add_theme_font_size_override(&"font_size", 16)
	box.add_child(hint)
	var back := Button.new()
	back.text = "Back to the fight   [Tab / Start]"
	back.pressed.connect(close_menu)
	box.add_child(back)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		close_menu()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if visible:
		close_menu()
	else:
		open_menu()


func open_menu() -> void:
	_refresh()
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_first_focus.grab_focus()
	opened.emit()


func close_menu() -> void:
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()


func _add_row(grid: GridContainer, label_text: String, slot: String, options: Dictionary) -> void:
	var label := Label.new()
	label.text = label_text
	grid.add_child(label)
	for who in ["player", "bot"]:
		var picker := OptionButton.new()
		picker.custom_minimum_size = Vector2(170, 0)
		for id: StringName in options:
			picker.add_item(options[id].display_name)
			picker.set_item_metadata(picker.item_count - 1, id)
		picker.item_selected.connect(_on_picked.bind(who, slot, picker))
		grid.add_child(picker)
		_pickers["%s/%s" % [who, slot]] = picker
		if _first_focus == null:
			_first_focus = picker


func _on_picked(index: int, who: String, slot: String, picker: OptionButton) -> void:
	var fighter := player if who == "player" else bot
	var id: StringName = picker.get_item_metadata(index)
	if slot == "gauntlet":
		fighter.set_loadout(id)
	else:
		fighter.set_loadout(fighter.gauntlet.id, id)


## Show what each fighter currently has (the quick-swap key may have changed it).
func _refresh() -> void:
	for who in ["player", "bot"]:
		var fighter := player if who == "player" else bot
		_select(_pickers["%s/gauntlet" % who], fighter.gauntlet.id)
		_select(_pickers["%s/rune" % who], fighter.rune.id)


static func _select(picker: OptionButton, id: StringName) -> void:
	for i in picker.item_count:
		if picker.get_item_metadata(i) == id:
			picker.select(i)
