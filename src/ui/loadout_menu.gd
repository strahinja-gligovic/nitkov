class_name LoadoutMenu
extends CanvasLayer
## Tab / Start during a match: change spells, rune and character for you and
## the bot. Changes apply immediately; the fight keeps running underneath.
## Your picks are the same element cards as the start menu's; the bot's are
## compact icon rows.

signal opened
signal closed

const MAIN_MENU := "res://src/ui/main_menu.tscn"
const SLOTS := [["Primary spell", "primary"], ["Signature spell", "signature"], ["Mobility rune", "rune"]]

var player: Fighter
var bot: Fighter
## Extra rows for the bot (mode, difficulty) are added here by TrainingMode.
var bot_section: VBoxContainer

var _cards := {}  # slot -> Array[PickCard]
var _bot_pickers := {}  # slot -> UiIconPicker
var _bot_names := {}  # slot -> Label
var _characters := {}  # "player"/"bot" -> Label
var _first_focus: Control


func _ready() -> void:
	layer = 10
	visible = false
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiTheme.make()
	add_child(root)
	var wash := ColorRect.new()
	wash.color = Color(0.04, 0.02, 0.07, 0.45)
	wash.set_anchors_preset(Control.PRESET_FULL_RECT)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(wash)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override(&"separation", 8)
	panel.add_child(outer)
	outer.add_child(UiTheme.title("LOADOUT", 34))
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override(&"separation", 26)
	outer.add_child(columns)

	# --- you -----------------------------------------------------------------------
	var you := VBoxContainer.new()
	you.add_theme_constant_override(&"separation", 6)
	columns.add_child(you)
	you.add_child(_header("YOU", "player"))
	for slot: Array in SLOTS:
		var heading := UiTheme.heading(slot[0], 15)
		heading.custom_minimum_size = Vector2(0, 24)
		heading.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		you.add_child(heading)
		you.add_child(_card_grid(slot[1]))
	var hint := Label.new()
	hint.text = "T / D-pad right: quick-swap your primary spell mid-fight"
	hint.add_theme_color_override(&"font_color", UiTheme.MUTED)
	hint.add_theme_font_size_override(&"font_size", 15)
	you.add_child(hint)

	columns.add_child(VSeparator.new())

	# --- bot -----------------------------------------------------------------------
	var them := VBoxContainer.new()
	them.custom_minimum_size = Vector2(330, 0)
	them.add_theme_constant_override(&"separation", 8)
	columns.add_child(them)
	them.add_child(_header("BOT", "bot"))
	for slot: Array in SLOTS:
		them.add_child(_bot_slot(slot[1], slot[0].get_slice(" ", 0)))
	bot_section = VBoxContainer.new()
	bot_section.add_theme_constant_override(&"separation", 10)
	them.add_child(bot_section)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	them.add_child(spacer)
	var back := Button.new()
	back.text = "Back to the fight   [Tab / Start]"
	back.pressed.connect(close_menu)
	them.add_child(back)
	var quit := Button.new()
	quit.text = "Quit to main menu"
	quit.pressed.connect(func() -> void:
		Engine.time_scale = 1.0
		get_tree().change_scene_to_file(MAIN_MENU))
	them.add_child(quit)


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
	for card: PickCard in _cards["primary"]:
		if card.button_pressed:
			_first_focus = card
	_first_focus.grab_focus()
	opened.emit()


func close_menu() -> void:
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()


## "YOU  < Warden >": a title and arrows cycling through the characters.
func _header(title: String, who: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	var label := UiTheme.title(title, 24)
	label.custom_minimum_size = Vector2(64, 0)
	row.add_child(label)
	var name := Label.new()
	name.custom_minimum_size = Vector2(150, 0)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.add_theme_font_override(&"font", UiTheme.bold_font())
	name.add_theme_font_size_override(&"font_size", 22)
	name.add_theme_color_override(&"font_color", UiTheme.GOLD)
	_characters[who] = name
	var previous := Button.new()
	previous.text = "  <  "
	previous.pressed.connect(_cycle_character.bind(who, -1))
	var next := Button.new()
	next.text = "  >  "
	next.pressed.connect(_cycle_character.bind(who, 1))
	row.add_child(previous)
	row.add_child(name)
	row.add_child(next)
	return row


func _card_grid(slot: String) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 10)
	grid.add_theme_constant_override(&"v_separation", 8)
	var group := ButtonGroup.new()
	var cards: Array[PickCard] = []
	for item: Resource in _options(slot):
		var card := PickCard.new()
		card.setup(item)
		card.button_group = group
		card.tooltip_text = PickCard.wrapped(item.description)
		card.pressed.connect(_on_picked.bind("player", slot, item.id))
		grid.add_child(card)
		cards.append(card)
		if _first_focus == null:
			_first_focus = card
	_cards[slot] = cards
	return grid


func _bot_slot(slot: String, title: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 4)
	var line := HBoxContainer.new()
	line.add_theme_constant_override(&"separation", 10)
	var label := UiTheme.heading(title, 14)
	label.custom_minimum_size = Vector2(98, 0)
	line.add_child(label)
	var name := Label.new()
	name.add_theme_font_override(&"font", UiTheme.bold_font())
	name.add_theme_font_size_override(&"font_size", 17)
	line.add_child(name)
	_bot_names[slot] = name
	box.add_child(line)
	var picker := UiIconPicker.new()
	picker.setup(_options(slot))
	picker.picked.connect(func(id: StringName) -> void: _on_picked("bot", slot, id))
	_bot_pickers[slot] = picker
	box.add_child(picker)
	return box


static func _options(slot: String) -> Array:
	match slot:
		"character":
			return GameData.characters.values()
		"primary":
			return GameData.spells_for(SpellData.Slot.PRIMARY)
		"signature":
			return GameData.spells_for(SpellData.Slot.SIGNATURE)
	return GameData.runes.values()


func _on_picked(who: String, slot: String, id: StringName) -> void:
	var fighter := player if who == "player" else bot
	var loadout := fighter.current_loadout()
	loadout.set(slot, id)
	fighter.apply_loadout(loadout)
	_refresh()


func _cycle_character(who: String, step: int) -> void:
	var fighter := player if who == "player" else bot
	var loadout := fighter.current_loadout()
	var ids: Array = GameData.characters.keys()
	loadout.character = ids[(ids.find(loadout.character) + step + ids.size()) % ids.size()]
	fighter.apply_loadout(loadout)
	_refresh()


## Show what each fighter currently has (the quick-swap key may have changed it).
func _refresh() -> void:
	var mine := player.current_loadout()
	for slot: String in _cards:
		for card: PickCard in _cards[slot]:
			card.set_selected(card.payload == mine.get(slot))
	var theirs := bot.current_loadout()
	for slot: String in _bot_pickers:
		var id: StringName = theirs.get(slot)
		(_bot_pickers[slot] as UiIconPicker).select(id)
		var item: Resource = GameData.runes.get(id) if slot == "rune" else GameData.spells.get(id)
		var name: Label = _bot_names[slot]
		name.text = item.display_name if item else ""
		name.add_theme_color_override(&"font_color", UiIcons.accent_of(id).lightened(0.4))
	_characters["player"].text = player.character.display_name
	_characters["bot"].text = bot.character.display_name
