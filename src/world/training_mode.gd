class_name TrainingMode
extends Node
## Runs the training arena: spawns the player and the bot, health orbs, the
## camera and menus, and respawns the dead.

const FIGHTER_SCENE := preload("res://src/combat/fighter.tscn")

@export var arena: ArenaBuilder

var player: Fighter
var bot: Fighter
var camera_rig: CameraRig
var player_input: PlayerInput
var menu: LoadoutMenu
var debug: DebugOverlay
var bot_brain := BotBrain.new(MatchConfig.bot_mode, MatchConfig.bot_difficulty, 7)


func _ready() -> void:
	camera_rig = CameraRig.new()
	camera_rig.name = "CameraRig"
	add_child(camera_rig)
	camera_rig.camera.add_child(ToonMaterials.make_ink_pass())

	player_input = PlayerInput.new()
	player_input.name = "PlayerInput"
	player_input.camera_rig = camera_rig
	add_child(player_input)

	player = _spawn_fighter(0, "You", MatchConfig.player)
	player.controller = player_input
	player_input.fighter = player
	bot = _spawn_fighter(1, "Bot", MatchConfig.bot)
	bot.controller = bot_brain
	camera_rig.follow(player)

	for spot in ArenaBuilder.ORB_SPOTS:
		var orb := HealthOrb.new()
		orb.name = "HealthOrb"
		add_child(orb)
		orb.global_position = spot

	var feedback := CombatFeedback.new()
	feedback.name = "CombatFeedback"
	feedback.camera_rig = camera_rig
	feedback.focus = player
	add_child(feedback)

	menu = LoadoutMenu.new()
	menu.name = "LoadoutMenu"
	menu.player = player
	menu.bot = bot
	add_child(menu)
	_add_bot_controls()

	var hud := Hud.new()
	hud.name = "Hud"
	hud.player = player
	hud.bot = bot
	hud.bot_brain = bot_brain
	hud.player_input = player_input
	hud.camera = camera_rig.camera
	add_child(hud)
	var numbers := DamageNumbers.new()
	numbers.name = "DamageNumbers"
	add_child(numbers)

	var viz := HitboxViz.new()
	viz.name = "HitboxViz"
	add_child(viz)
	debug = DebugOverlay.new()
	debug.name = "DebugOverlay"
	debug.hitbox_viz = viz
	add_child(debug)
	debug.tuning_toggled.connect(func(_open: bool) -> void: _refresh_input_lock())
	menu.opened.connect(_refresh_input_lock)
	menu.closed.connect(_refresh_input_lock)

	CombatEvents.fighter_respawned.connect(_on_respawned)
	_apply_autopilot()


func _input(event: InputEvent) -> void:
	# _input, not _unhandled_input: the menu's focus navigation would swallow Tab
	if event.is_action_pressed(&"loadout_menu"):
		menu.toggle()
		get_viewport().set_input_as_handled()


## While any menu or panel is open, the player's fighter idles and the mouse is free.
func _refresh_input_lock() -> void:
	var locked := menu.visible or debug.tuning_panel.visible
	player_input.enabled = not locked
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if locked else Input.MOUSE_MODE_CAPTURED


func _physics_process(_delta: float) -> void:
	for fighter in [player, bot]:
		if fighter.state.is_dead() and fighter.state.dead_time >= fighter.tuning.respawn_time:
			fighter.respawn(arena.spawn_transform(fighter.team))


func _on_respawned(fighter: Node) -> void:
	Vfx.ring(self, (fighter as Fighter).global_position, Color(1.0, 0.85, 0.4), 2.0, 0.45)
	if fighter == player:
		camera_rig.follow(player)


## Bot mode and difficulty rows in the loadout menu.
func _add_bot_controls() -> void:
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override(&"separation", 12)
	var mode_label := Label.new()
	mode_label.text = "Bot behaviour"
	mode_row.add_child(mode_label)
	var modes := OptionButton.new()
	for mode_name in BotBrain.MODE_NAMES:
		modes.add_item(mode_name)
	modes.select(bot_brain.mode)
	modes.item_selected.connect(func(index: int) -> void: bot_brain.mode = index as BotBrain.Mode)
	mode_row.add_child(modes)
	menu.bot_section.add_child(mode_row)

	var skill_row := HBoxContainer.new()
	skill_row.add_theme_constant_override(&"separation", 12)
	var skill_label := Label.new()
	skill_label.text = "Bot difficulty"
	skill_row.add_child(skill_label)
	var skill := HSlider.new()
	skill.min_value = 0.0
	skill.max_value = 1.0
	skill.step = 0.05
	skill.value = bot_brain.difficulty
	skill.custom_minimum_size = Vector2(220, 0)
	skill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var readout := Label.new()
	readout.text = "%d%%" % roundi(bot_brain.difficulty * 100)
	skill.value_changed.connect(func(value: float) -> void:
		bot_brain.difficulty = value
		readout.text = "%d%%" % roundi(value * 100))
	skill_row.add_child(skill)
	skill_row.add_child(readout)
	menu.bot_section.add_child(skill_row)


func _spawn_fighter(team: int, label: String, loadout: Loadout) -> Fighter:
	var fighter: Fighter = FIGHTER_SCENE.instantiate()
	fighter.team = team
	fighter.display_name = label
	fighter.apply_loadout(loadout)
	fighter.name = label.replace(" ", "")
	fighter.transform = arena.spawn_transform(team)
	add_child(fighter)
	return fighter


## Command-line hooks for automated verification runs (see Autopilot).
func _apply_autopilot() -> void:
	var pilot := Autopilot.from_args()
	if pilot == null:
		return
	add_child(pilot)
	var args := pilot.args
	if args.has("drive"):
		player.controller = ScriptedController.new(Scenarios.get_timeline(args["drive"]), camera_rig)
	if args.has("bot_drive"):
		bot.controller = ScriptedController.new(Scenarios.get_timeline(args["bot_drive"]), null)
	if args.has("bot_mode"):
		bot_brain.mode = String(args["bot_mode"]).to_int() as BotBrain.Mode
	if args.has("bot_skill"):
		bot_brain.difficulty = String(args["bot_skill"]).to_float()
	if args.has("autotest"):
		# bot vs bot: the player's fighter gets a duelist brain too
		var skill := String(args.get("player_skill", "0.5")).to_float()
		player.controller = BotBrain.new(BotBrain.Mode.DUELIST, skill, 3)
		player.apply_loadout(Loadout.make(player.character.id, &"firebolt", &"flame_wall", &"leap"))
		bot.apply_loadout(Loadout.make(bot.character.id, &"shard_volley", &"frost_nova", &"blink"))
		camera_rig.auto_yaw = true
		pilot.start_autotest(String(args["autotest"]).to_float())
	for who in ["player", "bot"]:
		var fighter := player if who == "player" else bot
		var loadout := fighter.current_loadout()
		for slot in ["character", "primary", "signature", "rune"]:
			if args.has("%s_%s" % [who, slot]):
				loadout.set(slot, StringName(args["%s_%s" % [who, slot]]))
		fighter.apply_loadout(loadout)
	if args.has("player_hp"):
		player.state.hp = String(args["player_hp"]).to_float()
	if args.has("player_yaw"):
		player.state.facing_yaw = deg_to_rad(String(args["player_yaw"]).to_float())
		player.rotation.y = player.state.facing_yaw
		camera_rig.yaw = player.state.facing_yaw
	if args.has("player_at"):
		var xz := String(args["player_at"]).split(",")
		player.global_position = Vector3(xz[0].to_float(), 0.0, xz[1].to_float())
	if args.has("bot_at"):
		# put the bot this many metres in front of the player, facing them
		var distance := String(args["bot_at"]).to_float()
		bot.global_position = player.global_position + player.forward() * distance
		bot.state.facing_yaw = wrapf(player.state.facing_yaw + PI, -PI, PI)
		bot.rotation.y = bot.state.facing_yaw
	if args.has("menu"):
		menu.open_menu.call_deferred()
	if args.has("hitboxes"):
		debug.hitbox_viz.visible = true
	if args.has("combat_log"):
		debug.combat_log.visible = true
	if args.has("tuning"):
		debug.tuning_panel.visible = true
	if args.has("spectate"):
		pilot.spectate(player, bot)
