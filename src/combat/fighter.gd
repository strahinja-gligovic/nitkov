class_name Fighter
extends CharacterBody3D
## One combatant. Each physics tick it pulls an InputCommand from its
## controller (PlayerInput or BotBrain) and advances the simulation. Player
## and bot run exactly the same code; only the controller differs.

const CHEST_HEIGHT := 1.2
const RADIUS := 0.4

@export var team := 0
@export var display_name := "Fighter"
## Which character model FighterVisual shows (see FighterVisual.SKINS).
@export var skin := &"knight"

var state := FighterState.new()
## Anything with get_command(fighter: Fighter) -> InputCommand.
var controller: Object
var tuning: CombatTuning
var weapon: WeaponData


func _ready() -> void:
	add_to_group(&"fighters")
	tuning = GameData.tuning
	weapon = GameData.weapons[&"longsword"]
	state.reset(tuning)
	state.team = team
	state.facing_yaw = rotation.y


func _physics_process(delta: float) -> void:
	var cmd: InputCommand = controller.get_command(self) if controller else InputCommand.new()
	simulate(cmd, delta)


func simulate(cmd: InputCommand, delta: float) -> void:
	state.on_floor = is_on_floor()
	state.buffer_presses(cmd.pressed, tuning)
	if state.hitstop > 0.0:
		# frozen by a melee impact: time stands still for this fighter
		state.hitstop = maxf(state.hitstop - delta, 0.0)
		return
	state.tick(delta, tuning)
	_advance_action(cmd, delta)
	if state.is_actionable():
		_act(cmd)
	_update_facing(cmd, delta)
	_move(cmd, delta)


func chest_position() -> Vector3:
	return global_position + Vector3.UP * CHEST_HEIGHT


func forward() -> Vector3:
	return CombatRules.yaw_to_dir(state.facing_yaw)


func is_enemy(other: Fighter) -> bool:
	return other != self and other.team != team


func enemies() -> Array[Fighter]:
	var out: Array[Fighter] = []
	for node in get_tree().get_nodes_in_group(&"fighters"):
		var other := node as Fighter
		if is_enemy(other) and not other.state.is_dead():
			out.append(other)
	return out


# --- action state machine -------------------------------------------------

func _advance_action(_cmd: InputCommand, delta: float) -> void:
	match state.action:
		FighterState.Action.FLINCH, FighterState.Action.STAGGER:
			state.action_time += delta
			if state.action_time >= state.action_duration:
				state.end_action()
		FighterState.Action.DEAD:
			state.action_time += delta


## Starts a new action from IDLE, highest priority first.
func _act(_cmd: InputCommand) -> void:
	pass


# --- facing and movement ----------------------------------------------------

func _update_facing(cmd: InputCommand, delta: float) -> void:
	match state.action:
		FighterState.Action.IDLE:
			_turn_toward(cmd.aim_yaw, tuning.turn_rate, delta)


func _turn_toward(yaw: float, rate_deg: float, delta: float) -> void:
	var diff := wrapf(yaw - state.facing_yaw, -PI, PI)
	var max_step := deg_to_rad(rate_deg) * delta
	state.facing_yaw = wrapf(state.facing_yaw + clampf(diff, -max_step, max_step), -PI, PI)
	rotation.y = state.facing_yaw


func _move(cmd: InputCommand, delta: float) -> void:
	var target := Vector3.ZERO
	var accel := tuning.ground_accel if state.on_floor else tuning.air_accel
	match state.action:
		FighterState.Action.IDLE:
			target = _locomotion_velocity(cmd, delta)
		FighterState.Action.FLINCH, FighterState.Action.STAGGER, FighterState.Action.DEAD:
			target = state.knockback
			state.knockback = state.knockback.move_toward(Vector3.ZERO, 12.0 * delta)
	var planar := Vector3(velocity.x, 0.0, velocity.z).move_toward(target, accel * delta)
	velocity.x = planar.x
	velocity.z = planar.z
	if state.on_floor and velocity.y < 0.0:
		velocity.y = 0.0
	velocity.y -= tuning.gravity * delta
	move_and_slide()


func _locomotion_velocity(cmd: InputCommand, delta: float) -> Vector3:
	var wish := cmd.move_3d()
	var sprinting := cmd.is_held(InputCommand.SPRINT) and wish.length() > 0.3 \
			and state.can_spend() and not state.blocking
	if sprinting:
		state.spend_stamina(tuning.sprint_stamina_per_sec * delta, tuning)
	var speed := tuning.sprint_speed if sprinting else tuning.walk_speed
	if state.blocking:
		speed *= tuning.block_move_mult
	return wish * speed
