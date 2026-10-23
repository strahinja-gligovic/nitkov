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


func _ready() -> void:
	camera_rig = CameraRig.new()
	camera_rig.name = "CameraRig"
	add_child(camera_rig)
	camera_rig.camera.add_child(ToonMaterials.make_ink_pass())

	player_input = PlayerInput.new()
	player_input.name = "PlayerInput"
	player_input.camera_rig = camera_rig
	add_child(player_input)

	player = _spawn_fighter(0, "You", &"knight")
	player.controller = player_input
	player_input.fighter = player
	bot = _spawn_fighter(1, "Bot", &"barbarian")
	bot.set_loadout(&"frost")
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
	menu.opened.connect(func() -> void: player_input.enabled = false)
	menu.closed.connect(func() -> void: player_input.enabled = true)

	CombatEvents.fighter_respawned.connect(_on_respawned)
	_apply_autopilot()


func _input(event: InputEvent) -> void:
	# _input, not _unhandled_input: the menu's focus navigation would swallow Tab
	if event.is_action_pressed(&"loadout_menu"):
		menu.toggle()
		get_viewport().set_input_as_handled()


func _physics_process(_delta: float) -> void:
	for fighter in [player, bot]:
		if fighter.state.is_dead() and fighter.state.dead_time >= fighter.tuning.respawn_time:
			fighter.respawn(arena.spawn_transform(fighter.team))


func _on_respawned(fighter: Node) -> void:
	Vfx.ring(self, (fighter as Fighter).global_position, Color(1.0, 0.85, 0.4), 2.0, 0.45)
	if fighter == player:
		camera_rig.follow(player)


func _spawn_fighter(team: int, label: String, skin: StringName) -> Fighter:
	var fighter: Fighter = FIGHTER_SCENE.instantiate()
	fighter.team = team
	fighter.display_name = label
	fighter.skin = skin
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
	if args.has("player_gauntlet") or args.has("player_rune"):
		player.set_loadout(StringName(args.get("player_gauntlet", "")), StringName(args.get("player_rune", "")))
	if args.has("bot_gauntlet") or args.has("bot_rune"):
		bot.set_loadout(StringName(args.get("bot_gauntlet", "")), StringName(args.get("bot_rune", "")))
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
	if args.has("spectate"):
		pilot.spectate(player, bot)
