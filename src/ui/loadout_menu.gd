class_name LoadoutMenu
extends CanvasLayer
## Tab / Start during a match: change spells, rune and character for you and
## the bot. Changes apply immediately; the fight keeps running underneath.

signal opened
signal closed

const MAIN_MENU := "res://src/ui/main_menu.tscn"
const SLOTS := [["Character", "character"], ["Primary", "primary"], ["Signature", "signature"], ["Rune", "rune"]]

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
	for slot: Array in SLOTS:
		_add_row(grid, slot[0], slot[1])

	bot_section = VBoxContainer.new()
	bot_section.add_theme_constant_override(&"separation", 10)
	box.add_child(bot_section)

	var hint := Label.new()
	hint.text = "T / D-pad right: quick-swap your primary spell mid-fight"
	hint.add_theme_color_override(&"font_color", UiTheme.MUTED)
	hint.add_theme_font_size_override(&"font_size", 16)
	box.add_child(hint)
	var back := Button.new()
	back.text = "Back to the fight   [Tab / Start]"
	back.pressed.connect(close_menu)
	box.add_child(back)
	var quit := Button.new()
	quit.text = "Quit to main menu"
	quit.pressed.connect(func() -> void:
		Engine.time_scale = 1.0
		get_tree().change_scene_to_file(MAIN_MENU))
	box.add_child(quit)


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


func _add_row(grid: GridContainer, label_text: String, slot: String) -> void:
	var label := Label.new()
	label.text = label_text
	grid.add_child(label)
	for who in ["player", "bot"]:
		var picker := OptionButton.new()
		picker.custom_minimum_size = Vector2(190, 0)
		for item: Resource in _options(slot):
			picker.add_item(item.display_name)
			picker.set_item_metadata(picker.item_count - 1, item.id)
		picker.item_selected.connect(_on_picked.bind(who, slot, picker))
		grid.add_child(picker)
		_pickers["%s/%s" % [who, slot]] = picker
		if _first_focus == null:
			_first_focus = picker


static func _options(slot: String) -> Array:
	match slot:
		"character":
			return GameData.characters.values()
		"primary":
			return GameData.spells_for(SpellData.Slot.PRIMARY)
		"signature":
			return GameData.spells_for(SpellData.Slot.SIGNATURE)
	return GameData.runes.values()


func _on_picked(index: int, who: String, slot: String, picker: OptionButton) -> void:
	var fighter := player if who == "player" else bot
	var loadout := fighter.current_loadout()
	loadout.set(slot, picker.get_item_metadata(index))
	fighter.apply_loadout(loadout)


## Show what each fighter currently has (the quick-swap key may have changed it).
func _refresh() -> void:
	for who in ["player", "bot"]:
		var loadout := (player if who == "player" else bot).current_loadout()
		for slot: Array in SLOTS:
			_select(_pickers["%s/%s" % [who, slot[1]]], loadout.get(slot[1]))


static func _select(picker: OptionButton, id: StringName) -> void:
	for i in picker.item_count:
		if picker.get_item_metadata(i) == id:
			picker.select(i)
