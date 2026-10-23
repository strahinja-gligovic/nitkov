class_name TrainingMode
extends Node
## Runs the training arena: spawns the player and the bot, owns the camera,
## and respawns the dead.

const FIGHTER_SCENE := preload("res://src/combat/fighter.tscn")

@export var arena: ArenaBuilder

var player: Fighter
var bot: Fighter
var camera_rig: CameraRig
var player_input: PlayerInput


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
	bot = _spawn_fighter(1, "Bot", &"barbarian")
	camera_rig.follow(player)

	var feedback := CombatFeedback.new()
	feedback.name = "CombatFeedback"
	feedback.camera_rig = camera_rig
	feedback.focus = player
	add_child(feedback)

	var pilot := Autopilot.from_args()
	if pilot:
		add_child(pilot)
		if pilot.args.has("drive"):
			player.controller = ScriptedController.new(Scenarios.get_timeline(pilot.args["drive"]), camera_rig)
		if pilot.args.has("player_at"):
			var xz := String(pilot.args["player_at"]).split(",")
			player.global_position = Vector3(xz[0].to_float(), 0.0, xz[1].to_float())
		if pilot.args.has("bot_at"):
			# put the bot this many metres in front of the player, facing them
			var distance := String(pilot.args["bot_at"]).to_float()
			bot.global_position = player.global_position + player.forward() * distance
			bot.state.facing_yaw = wrapf(player.state.facing_yaw + PI, -PI, PI)
			bot.rotation.y = bot.state.facing_yaw
		if pilot.args.has("bot_drive"):
			bot.controller = ScriptedController.new(Scenarios.get_timeline(pilot.args["bot_drive"]), null)
		if pilot.args.has("spectate"):
			pilot.spectate(player, bot)


func _spawn_fighter(team: int, label: String, skin: StringName) -> Fighter:
	var fighter: Fighter = FIGHTER_SCENE.instantiate()
	fighter.team = team
	fighter.display_name = label
	fighter.skin = skin
	fighter.name = label.replace(" ", "")
	fighter.transform = arena.spawn_transform(team)
	add_child(fighter)
	return fighter
