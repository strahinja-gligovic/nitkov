class_name TrainingMode
extends Node
## Runs the training arena: spawns the player (and later the bot), owns the
## camera, and respawns the dead.

const FIGHTER_SCENE := preload("res://src/combat/fighter.tscn")

@export var arena: ArenaBuilder

var player: Fighter
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

	player = _spawn_fighter(0, "You")
	player.controller = player_input
	camera_rig.follow(player)

	var pilot := Autopilot.from_args()
	if pilot:
		add_child(pilot)
		if pilot.args.has("drive"):
			player.controller = ScriptedController.new(Scenarios.get_timeline(pilot.args["drive"]), camera_rig)


func _spawn_fighter(team: int, label: String) -> Fighter:
	var fighter: Fighter = FIGHTER_SCENE.instantiate()
	fighter.team = team
	fighter.display_name = label
	fighter.name = label.replace(" ", "")
	fighter.transform = arena.spawn_transform(team)
	add_child(fighter)
	return fighter
