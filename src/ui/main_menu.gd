class_name MainMenu
extends Control
## The start menu. A title screen, then a loadout screen where you mix and
## match your character, primary spell, signature spell and rune, and set up
## the opponent. Your picks are cards on the left, the opponent's are compact
## icon rows on the right, and the 3D showcase in between previews every
## pick: your fighter casts the spell you just chose. FIGHT! hands everything
## to the arena through the MatchConfig autoload.
##
## Automated runs (any "--" arguments) skip straight to the arena, unless
## --stay_in_menu is given. Then --menu_screen=loadout opens that screen, and
## --menu_pick=<spell or rune id> picks it as if its card were clicked.

const ARENA_SCENE := "res://src/world/arena.tscn"
const MARGIN := 28.0
const TOP := 76.0
## Width of your panel (two columns of cards) and of the opponent's.
const YOU_WIDTH := PickCard.SIZE.x * 2.0 + 10.0 + 32.0
const THEM_WIDTH := 372.0

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
var _bot_pickers := {}  # slot name -> UiIconPicker
var _bot_names := {}  # slot name -> Label
var _difficulty_label: Label
var _info_icon: UiIconView
var _info_title: Label
var _info_body: Label


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
		if pilot.args.has("slowmo"):
			Engine.time_scale = String(pilot.args["slowmo"]).to_float()
		if pilot.args.has("menu_pick"):
			_pick_by_id.call_deferred(StringName(pilot.args["menu_pick"]))


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
	_show_info(GameData.spells[_player.primary])
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
	screen.add_child(_shade(false))
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
	screen.add_child(_shade(true))

	var heading := UiTheme.title("LOADOUT", 44)
	heading.position = Vector2(MARGIN + 10.0, 12.0)
	screen.add_child(heading)

	# --- you: cards ----------------------------------------------------------------
	var left := PanelContainer.new()
	left.position = Vector2(MARGIN, TOP)
	left.custom_minimum_size = Vector2(YOU_WIDTH, 0)
	screen.add_child(left)
	var you := VBoxContainer.new()
	you.add_theme_constant_override(&"separation", 6)
	left.add_child(you)
	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 16)
	header.add_child(UiTheme.title("YOU", 26))
	var picker := _character_picker(true)
	header.add_child(picker[0])
	_player_character_label = picker[1]
	you.add_child(header)
	_player_blurb = Label.new()
	_player_blurb.add_theme_font_size_override(&"font_size", 16)
	_player_blurb.add_theme_color_override(&"font_color", UiTheme.MUTED)
	you.add_child(_player_blurb)
	for slot in [["primary", "Primary spell"], ["signature", "Signature spell"], ["rune", "Mobility rune"]]:
		var section := UiTheme.heading(slot[1])
		section.custom_minimum_size = Vector2(0, 28)
		section.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		you.add_child(section)
		you.add_child(_card_grid(slot[0]))

	# --- opponent: icon rows ----------------------------------------------------------
	var right := PanelContainer.new()
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.offset_left = -MARGIN - THEM_WIDTH
	right.offset_right = -MARGIN
	right.offset_top = TOP
	screen.add_child(right)
	var them := VBoxContainer.new()
	them.add_theme_constant_override(&"separation", 8)
	right.add_child(them)
	var them_header := HBoxContainer.new()
	them_header.add_theme_constant_override(&"separation", 8)
	them_header.add_child(UiTheme.title("OPPONENT", 26))
	them.add_child(them_header)
	var bot_picker := _character_picker(false)
	them.add_child(bot_picker[0])
	_bot_character_label = bot_picker[1]
	var modes := OptionButton.new()
	for mode_name in BotBrain.MODE_NAMES:
		modes.add_item(mode_name)
	modes.select(MatchConfig.bot_mode)
	modes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modes.item_selected.connect(func(index: int) -> void: MatchConfig.bot_mode = index as BotBrain.Mode)
	them.add_child(_row("Behaviour", modes))
	var difficulty := HSlider.new()
	difficulty.min_value = 0.0
	difficulty.max_value = 1.0
	difficulty.step = 0.05
	difficulty.value = MatchConfig.bot_difficulty
	difficulty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	difficulty.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_difficulty_label = Label.new()
	_difficulty_label.custom_minimum_size = Vector2(52, 0)
	_difficulty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_difficulty_label.text = "%d%%" % roundi(MatchConfig.bot_difficulty * 100)
	difficulty.value_changed.connect(func(value: float) -> void:
		MatchConfig.bot_difficulty = value
		_difficulty_label.text = "%d%%" % roundi(value * 100))
	var difficulty_box := HBoxContainer.new()
	difficulty_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	difficulty_box.add_child(difficulty)
	difficulty_box.add_child(_difficulty_label)
	them.add_child(_row("Difficulty", difficulty_box))
	for slot in [["primary", "Primary"], ["signature", "Signature"], ["rune", "Rune"]]:
		them.add_child(_bot_slot(slot[0], slot[1]))
	var shuffle := Button.new()
	shuffle.text = "Randomize opponent"
	shuffle.pressed.connect(_randomize_bot)
	them.add_child(_spacer(2))
	them.add_child(shuffle)

	# --- what the highlighted pick does ------------------------------------------------
	screen.add_child(_build_info_strip())

	# --- go ------------------------------------------------------------------------------
	var fight := _big_button("FIGHT!", 46)
	fight.add_theme_font_override(&"font", UiTheme.bold_font())
	_anchor_bottom_right(fight, -126.0, -36.0)
	fight.add_theme_color_override(&"font_color", UiTheme.GOLD)
	fight.add_theme_color_override(&"font_hover_color", Color(1.0, 0.92, 0.6))
	fight.add_theme_color_override(&"font_focus_color", Color(1.0, 0.92, 0.6))
	fight.pressed.connect(_fight)
	screen.add_child(fight)
	var back := Button.new()
	back.text = "Back   [Esc / B]"
	_anchor_bottom_right(back, -178.0, -138.0)
	back.pressed.connect(_show_title)
	screen.add_child(back)
	return screen


func _anchor_bottom_right(control: Control, top: float, bottom: float) -> void:
	control.anchor_left = 1.0
	control.anchor_right = 1.0
	control.anchor_top = 1.0
	control.anchor_bottom = 1.0
	control.offset_left = -MARGIN - THEM_WIDTH
	control.offset_right = -MARGIN
	control.offset_top = top
	control.offset_bottom = bottom


## The full description of the card you're pointing at, under the showcase.
func _build_info_strip() -> Control:
	var strip := PanelContainer.new()
	strip.anchor_top = 1.0
	strip.anchor_bottom = 1.0
	strip.anchor_right = 1.0
	strip.offset_left = MARGIN + YOU_WIDTH + 22.0
	strip.offset_right = -MARGIN - THEM_WIDTH - 22.0
	strip.offset_top = -150.0
	strip.offset_bottom = -36.0
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.07, 0.04, 0.1, 0.82)
	box.border_color = Color(UiTheme.GOLD, 0.55)
	box.set_border_width_all(2)
	box.set_corner_radius_all(10)
	box.set_content_margin_all(10)
	box.anti_aliasing = true
	strip.add_theme_stylebox_override(&"panel", box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	strip.add_child(row)
	_info_icon = UiIconView.new(&"", 58.0, true)
	_info_icon.fill = 0.72
	_info_icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(_info_icon)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override(&"separation", 0)
	row.add_child(text)
	_info_title = Label.new()
	_info_title.add_theme_font_override(&"font", UiTheme.bold_font())
	_info_title.add_theme_font_size_override(&"font_size", 19)
	text.add_child(_info_title)
	_info_body = Label.new()
	_info_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_body.add_theme_font_size_override(&"font_size", 15)
	_info_body.add_theme_color_override(&"font_color", UiTheme.TEXT)
	_info_body.add_theme_constant_override(&"line_spacing", -2)
	_info_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.add_child(_info_body)
	return strip


func _show_info(item: Resource) -> void:
	_info_icon.icon_id = item.id
	_info_title.text = "%s   ·   %s" % [item.display_name, PickCard.stat_line(item)]
	_info_title.add_theme_color_override(&"font_color", UiIcons.accent_of(item.id).lightened(0.45))
	_info_body.text = item.description


# --- your picks ------------------------------------------------------------------------

func _card_grid(slot: String) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 10)
	grid.add_theme_constant_override(&"v_separation", 10)
	var group := ButtonGroup.new()
	var cards: Array[PickCard] = []
	for item: Resource in _options(slot):
		var card := PickCard.new()
		card.setup(item)
		card.button_group = group
		card.pressed.connect(_on_player_pick.bind(slot, card))
		card.focus_entered.connect(_show_info.bind(item))
		card.mouse_entered.connect(_show_info.bind(item))
		grid.add_child(card)
		cards.append(card)
	_player_cards[slot] = cards
	return grid


func _on_player_pick(slot: String, card: PickCard) -> void:
	_player.set(slot, card.payload)
	_refresh_player()
	_show_info(card.item)
	_showcase.show_loadout(true, _player)
	var button := {"primary": InputCommand.PRIMARY, "signature": InputCommand.SIGNATURE, "rune": InputCommand.RUNE}[slot] as int
	_showcase.perform(true, button)


## Picks a spell or rune by id as if its card were clicked (--menu_pick).
func _pick_by_id(id: StringName) -> void:
	for slot: String in _player_cards:
		for card: PickCard in _player_cards[slot]:
			if card.payload == id:
				card.set_selected(true)
				_on_player_pick(slot, card)
				return


func _refresh_player() -> void:
	for slot: String in _player_cards:
		for card: PickCard in _player_cards[slot]:
			card.set_selected(card.payload == _player.get(slot))
	var character: CharacterData = GameData.characters[_player.character]
	_player_character_label.text = character.display_name
	_player_blurb.text = character.blurb


# --- opponent picks ----------------------------------------------------------------------

## "Primary  Ice Spike" over a row of icons, one per choice.
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
	picker.picked.connect(_on_bot_pick.bind(slot))
	_bot_pickers[slot] = picker
	box.add_child(picker)
	return box


func _on_bot_pick(id: StringName, slot: String) -> void:
	_bot.set(slot, id)
	_refresh_bot()
	_showcase.show_loadout(false, _bot)
	var button := {"primary": InputCommand.PRIMARY, "signature": InputCommand.SIGNATURE, "rune": InputCommand.RUNE}[slot] as int
	_showcase.perform(false, button)


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
		var id: StringName = _bot.get(slot)
		(_bot_pickers[slot] as UiIconPicker).select(id)
		var item: Resource = GameData.runes.get(id) if slot == "rune" else GameData.spells.get(id)
		var name: Label = _bot_names[slot]
		name.text = item.display_name if item else ""
		name.add_theme_color_override(&"font_color", UiIcons.accent_of(id).lightened(0.4))


## "< Knight >" arrows that cycle through every character.
func _character_picker(for_player: bool) -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	var label := Label.new()
	label.custom_minimum_size = Vector2(170, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override(&"font", UiTheme.bold_font())
	label.add_theme_font_size_override(&"font_size", 25)
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


## A dark wash so text stays readable on the 3D backdrop: over the left of
## the screen, or (`both_sides`, the loadout screen) over both edges with the
## middle clear for the showcase.
static func _shade(both_sides: bool) -> TextureRect:
	var gradient := Gradient.new()
	var ink := Color(0.04, 0.02, 0.07, 0.82)
	gradient.set_color(0, ink)
	gradient.set_color(1, Color(ink, 0.0))
	if both_sides:
		gradient.set_offset(1, 0.42)
		gradient.add_point(0.62, Color(ink, 0.0))
		gradient.add_point(1.0, Color(ink, 0.7))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(1.0 if both_sides else 0.62, 0)
	var shade := TextureRect.new()
	shade.texture = texture
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return shade
