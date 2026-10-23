class_name MainMenu
extends Control
## The start menu. A title screen, then a loadout screen where you mix and
## match your character, primary spell, signature spell and rune, and set up
## the opponent. Picks are previewed live by the 3D showcase behind the UI.
## FIGHT! hands everything to the arena through the MatchConfig autoload.
##
## Automated runs (any "--" arguments) skip straight to the arena, unless
## --stay_in_menu is given (then --menu_screen=loadout opens that screen).

const ARENA_SCENE := "res://src/world/arena.tscn"

var _player := Loadout.new()
var _bot := Loadout.new()
var _showcase: MenuShowcase
var _title_screen: Control
var _loadout_screen: Control
var _play_button: Button
var _player_cards := {}  # slot name -> Array[PickCard]
var _player_character_label: Label
var _player_blurb: Label
var _bot_character_label: Label
var _bot_pickers := {}  # slot name -> OptionButton
var _difficulty_label: Label


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty() and not args.has("--stay_in_menu"):
		get_tree().change_scene_to_file.call_deferred(ARENA_SCENE)
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Engine.time_scale = 1.0
	_player = MatchConfig.player.duplicate()
	_bot = MatchConfig.bot.duplicate()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.make()
	_showcase = MenuShowcase.new()
	add_child(_showcase)
	add_child(_shade())
	_title_screen = _build_title_screen()
	add_child(_title_screen)
	_loadout_screen = _build_loadout_screen()
	add_child(_loadout_screen)
	_show_title()
	var pilot := Autopilot.from_args()
	if pilot:
		add_child(pilot)
		if pilot.args.get("menu_screen", "") == "loadout":
			_show_loadout.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and _loadout_screen.visible:
		_show_title()
		get_viewport().set_input_as_handled()


# --- screens ------------------------------------------------------------------------

func _show_title() -> void:
	_title_screen.visible = true
	_loadout_screen.visible = false
	_play_button.grab_focus()


func _show_loadout() -> void:
	_title_screen.visible = false
	_loadout_screen.visible = true
	_refresh_player()
	_refresh_bot()
	for card: PickCard in _player_cards["primary"]:
		if card.button_pressed:
			card.grab_focus()


func _fight() -> void:
	MatchConfig.player = _player
	MatchConfig.bot = _bot
	get_tree().change_scene_to_file(ARENA_SCENE)


func _build_title_screen() -> Control:
	var screen := Control.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.position = Vector2(110, 230)
	box.add_theme_constant_override(&"separation", 14)
	screen.add_child(box)
	var logo := UiTheme.title("NITKOV", 120)
	logo.add_theme_constant_override(&"outline_size", 22)
	box.add_child(logo)
	var tagline := Label.new()
	tagline.text = "Steel, sorcery and terrible manners."
	tagline.add_theme_font_size_override(&"font_size", 26)
	tagline.add_theme_color_override(&"font_color", UiTheme.TEXT)
	box.add_child(tagline)
	box.add_child(_spacer(40))
	_play_button = _big_button("PLAY", 34)
	_play_button.pressed.connect(_show_loadout)
	box.add_child(_play_button)
	var quit := _big_button("QUIT", 26)
	quit.custom_minimum_size = Vector2(340, 56)
	quit.pressed.connect(get_tree().quit)
	box.add_child(quit)
	return screen


func _build_loadout_screen() -> Control:
	var screen := Control.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var heading := UiTheme.title("LOADOUT", 46)
	heading.position = Vector2(44, 18)
	screen.add_child(heading)

	# --- you -------------------------------------------------------------------------
	var left := PanelContainer.new()
	left.position = Vector2(36, 86)
	screen.add_child(left)
	var you := VBoxContainer.new()
	you.add_theme_constant_override(&"separation", 8)
	left.add_child(you)
	you.add_child(_section("YOU"))
	var picker := _character_picker(true)
	you.add_child(picker[0])
	_player_character_label = picker[1]
	_player_blurb = Label.new()
	_player_blurb.add_theme_font_size_override(&"font_size", 15)
	_player_blurb.add_theme_color_override(&"font_color", UiTheme.MUTED)
	you.add_child(_player_blurb)
	for slot in [["primary", "PRIMARY SPELL"], ["signature", "SIGNATURE SPELL"], ["rune", "MOBILITY RUNE"]]:
		you.add_child(_section(slot[1], 17))
		you.add_child(_card_row(slot[0]))

	# --- opponent ----------------------------------------------------------------------
	var right := PanelContainer.new()
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.offset_left = -430
	right.offset_right = -36
	right.offset_top = 86
	screen.add_child(right)
	var them := VBoxContainer.new()
	them.add_theme_constant_override(&"separation", 10)
	right.add_child(them)
	them.add_child(_section("OPPONENT"))
	var bot_picker := _character_picker(false)
	them.add_child(bot_picker[0])
	_bot_character_label = bot_picker[1]
	var modes := OptionButton.new()
	for mode_name in BotBrain.MODE_NAMES:
		modes.add_item(mode_name)
	modes.select(MatchConfig.bot_mode)
	modes.item_selected.connect(func(index: int) -> void: MatchConfig.bot_mode = index as BotBrain.Mode)
	them.add_child(_row("Behaviour", modes))
	var difficulty := HSlider.new()
	difficulty.min_value = 0.0
	difficulty.max_value = 1.0
	difficulty.step = 0.05
	difficulty.value = MatchConfig.bot_difficulty
	difficulty.custom_minimum_size = Vector2(170, 0)
	difficulty.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_difficulty_label = Label.new()
	_difficulty_label.text = "%d%%" % roundi(MatchConfig.bot_difficulty * 100)
	difficulty.value_changed.connect(func(value: float) -> void:
		MatchConfig.bot_difficulty = value
		_difficulty_label.text = "%d%%" % roundi(value * 100))
	var difficulty_box := HBoxContainer.new()
	difficulty_box.add_child(difficulty)
	difficulty_box.add_child(_difficulty_label)
	them.add_child(_row("Difficulty", difficulty_box))
	for slot in [["primary", "Primary"], ["signature", "Signature"], ["rune", "Rune"]]:
		var option := OptionButton.new()
		option.custom_minimum_size = Vector2(190, 0)
		for item: Resource in _options(slot[0]):
			option.add_item(item.display_name)
			option.set_item_metadata(option.item_count - 1, item.id)
		option.item_selected.connect(_on_bot_pick.bind(slot[0], option))
		_bot_pickers[slot[0]] = option
		them.add_child(_row(slot[1], option))
	var shuffle := Button.new()
	shuffle.text = "Randomize opponent"
	shuffle.pressed.connect(_randomize_bot)
	them.add_child(shuffle)

	# --- go ------------------------------------------------------------------------------
	var fight := _big_button("FIGHT!", 44)
	fight.anchor_left = 1.0
	fight.anchor_right = 1.0
	fight.anchor_top = 1.0
	fight.anchor_bottom = 1.0
	fight.offset_left = -430
	fight.offset_right = -36
	fight.offset_top = -126
	fight.offset_bottom = -40
	fight.add_theme_color_override(&"font_color", UiTheme.GOLD)
	fight.pressed.connect(_fight)
	screen.add_child(fight)
	var back := Button.new()
	back.text = "Back   [Esc / B]"
	back.anchor_left = 1.0
	back.anchor_right = 1.0
	back.anchor_top = 1.0
	back.anchor_bottom = 1.0
	back.offset_left = -430
	back.offset_right = -36
	back.offset_top = -176
	back.offset_bottom = -136
	back.pressed.connect(_show_title)
	screen.add_child(back)
	return screen


# --- your picks ------------------------------------------------------------------------

func _card_row(slot: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	var group := ButtonGroup.new()
	var cards: Array[PickCard] = []
	for item: Resource in _options(slot):
		var card := PickCard.new()
		card.setup(item.id, item.display_name, _stat_line(item), item.description, _accent(item))
		card.button_group = group
		card.pressed.connect(_on_player_pick.bind(slot, card))
		row.add_child(card)
		cards.append(card)
	_player_cards[slot] = cards
	return row


func _on_player_pick(slot: String, card: PickCard) -> void:
	_player.set(slot, card.payload)
	_showcase.show_loadout(true, _player)
	var button := {"primary": InputCommand.PRIMARY, "signature": InputCommand.SIGNATURE, "rune": InputCommand.RUNE}[slot] as int
	_showcase.perform(true, button)


func _refresh_player() -> void:
	for slot: String in _player_cards:
		for card: PickCard in _player_cards[slot]:
			card.set_pressed_no_signal(card.payload == _player.get(slot))
	var character: CharacterData = GameData.characters[_player.character]
	_player_character_label.text = character.display_name
	_player_blurb.text = character.blurb


# --- opponent picks ----------------------------------------------------------------------

func _on_bot_pick(index: int, slot: String, option: OptionButton) -> void:
	_bot.set(slot, option.get_item_metadata(index))
	_showcase.show_loadout(false, _bot)


func _randomize_bot() -> void:
	_bot.character = GameData.characters.keys().pick_random()
	for slot in ["primary", "signature", "rune"]:
		_bot.set(slot, (_options(slot).pick_random() as Resource).id)
	_refresh_bot()
	_showcase.show_loadout(false, _bot)
	_showcase.perform(false, InputCommand.PRIMARY)


func _refresh_bot() -> void:
	_bot_character_label.text = (GameData.characters[_bot.character] as CharacterData).display_name
	for slot: String in _bot_pickers:
		var option: OptionButton = _bot_pickers[slot]
		for i in option.item_count:
			if option.get_item_metadata(i) == _bot.get(slot):
				option.select(i)


## "< Knight >" arrows that cycle through every character.
func _character_picker(for_player: bool) -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	var label := Label.new()
	label.custom_minimum_size = Vector2(190, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override(&"font_size", 26)
	label.add_theme_color_override(&"font_color", UiTheme.GOLD)
	var previous := Button.new()
	previous.text = "  <  "
	previous.pressed.connect(_cycle_character.bind(for_player, -1))
	var next := Button.new()
	next.text = "  >  "
	next.pressed.connect(_cycle_character.bind(for_player, 1))
	row.add_child(previous)
	row.add_child(label)
	row.add_child(next)
	return [row, label]


func _cycle_character(for_player: bool, step: int) -> void:
	var loadout := _player if for_player else _bot
	var ids: Array = GameData.characters.keys()
	loadout.character = ids[(ids.find(loadout.character) + step + ids.size()) % ids.size()]
	_showcase.show_loadout(for_player, loadout)
	_showcase.perform(for_player, InputCommand.LIGHT)
	if for_player:
		_refresh_player()
	else:
		_refresh_bot()


# --- helpers -------------------------------------------------------------------------------

func _options(slot: String) -> Array:
	match slot:
		"primary":
			return GameData.spells_for(SpellData.Slot.PRIMARY)
		"signature":
			return GameData.spells_for(SpellData.Slot.SIGNATURE)
	return GameData.runes.values()


static func _stat_line(item: Resource) -> String:
	if item is SpellData:
		var spell := item as SpellData
		var element: String = SpellData.Element.keys()[spell.element]
		if spell.slot == SpellData.Slot.PRIMARY:
			return "%s  ·  %d stamina" % [element, roundi(spell.stamina_cost)]
		return "%s  ·  %ds cooldown" % [element, roundi(spell.cooldown)]
	return "MOBILITY  ·  %ds cooldown" % roundi((item as RuneData).cooldown)


static func _accent(item: Resource) -> Color:
	if item is SpellData:
		return SpellData.element_color((item as SpellData).element)
	return Color(0.8, 0.65, 1.0)


func _section(text: String, size := 24) -> Label:
	var label := UiTheme.title(text, size)
	return label


func _row(text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(110, 0)
	row.add_child(label)
	row.add_child(control)
	return row


func _big_button(text: String, size: int) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(340, 70)
	button.add_theme_font_size_override(&"font_size", size)
	return button


static func _spacer(height: float) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	return spacer


## A dark wash over the left of the screen so text stays readable on the 3D backdrop.
static func _shade() -> TextureRect:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.04, 0.02, 0.07, 0.82))
	gradient.set_color(1, Color(0.04, 0.02, 0.07, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(0.62, 0)
	var shade := TextureRect.new()
	shade.texture = texture
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return shade
