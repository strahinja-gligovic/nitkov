class_name Fighter
extends CharacterBody3D
## One combatant. Each physics tick it pulls an InputCommand from its
## controller (PlayerInput or BotBrain) and advances the simulation. Player
## and bot run exactly the same code; only the controller differs.

const CHEST_HEIGHT := 1.2

@export var team := 0
@export var display_name := "Fighter"

var state := FighterState.new()
## Anything with get_command(fighter: Fighter) -> InputCommand.
var controller: Object
var tuning: CombatTuning


func _ready() -> void:
	add_to_group(&"fighters")
	tuning = GameData.tuning
	state.reset(tuning)
	state.team = team
	state.facing_yaw = rotation.y


func _physics_process(delta: float) -> void:
	var cmd: InputCommand = controller.get_command(self) if controller else InputCommand.new()
	simulate(cmd, delta)


func simulate(cmd: InputCommand, delta: float) -> void:
	state.on_floor = is_on_floor()
	state.tick(delta, tuning)
	_turn_toward(cmd.aim_yaw, tuning.turn_rate, delta)
	_move(cmd, delta)


func chest_position() -> Vector3:
	return global_position + Vector3.UP * CHEST_HEIGHT


func forward() -> Vector3:
	return CombatRules.yaw_to_dir(state.facing_yaw)


func _turn_toward(yaw: float, rate_deg: float, delta: float) -> void:
	var diff := wrapf(yaw - state.facing_yaw, -PI, PI)
	var max_step := deg_to_rad(rate_deg) * delta
	state.facing_yaw = wrapf(state.facing_yaw + clampf(diff, -max_step, max_step), -PI, PI)
	rotation.y = state.facing_yaw


func _move(cmd: InputCommand, delta: float) -> void:
	var wish := cmd.move_3d()
	var sprinting := cmd.is_held(InputCommand.SPRINT) and wish.length() > 0.3 and state.can_spend()
	if sprinting:
		state.spend_stamina(tuning.sprint_stamina_per_sec * delta, tuning)
	var speed := tuning.sprint_speed if sprinting else tuning.walk_speed
	var accel := tuning.ground_accel if state.on_floor else tuning.air_accel
	var planar := Vector3(velocity.x, 0.0, velocity.z).move_toward(wish * speed, accel * delta)
	velocity.x = planar.x
	velocity.z = planar.z
	if not state.on_floor:
		velocity.y -= tuning.gravity * delta
	move_and_slide()
