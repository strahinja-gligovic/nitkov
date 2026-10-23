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

## The loadout changed (FighterVisual rebuilds the gauntlet glow).
signal loadout_changed

var state := FighterState.new()
## Anything with get_command(fighter: Fighter) -> InputCommand.
var controller: Object
var tuning: CombatTuning = GameData.tuning
var weapon: WeaponData = GameData.weapons[&"longsword"]
var gauntlet: GauntletData = GameData.gauntlets[&"fire"]
var rune: RuneData = GameData.runes[&"leap"]

## Enemy the current swing is homing on (recomputed every tick of the wind-up).
var _magnet: Fighter


func _ready() -> void:
	add_to_group(&"fighters")
	state.reset(tuning)
	state.team = team
	state.facing_yaw = rotation.y


func set_loadout(gauntlet_id: StringName, rune_id := &"") -> void:
	gauntlet = GameData.gauntlets.get(gauntlet_id, gauntlet)
	rune = GameData.runes.get(rune_id, rune)
	loadout_changed.emit()


## Debug quick-swap (T / D-pad right): the next gauntlet in GameData order.
## Lets one player test Frost -> Fire Shatter alone.
func cycle_gauntlet() -> void:
	var ids: Array = GameData.gauntlets.keys()
	set_loadout(ids[(ids.find(gauntlet.id) + 1) % ids.size()])


## Publishes a resolved hit and remembers who dealt damage (for burn kill credit).
static func report_hit(attacker: Fighter, target: Fighter, result: HitResult, at: Vector3) -> void:
	if result.outcome == HitResult.Outcome.IGNORED:
		return
	if attacker and result.damage > 0.0:
		target.state.last_attacker_id = attacker.get_instance_id()
	CombatEvents.hit_resolved.emit(attacker, target, result, at)
	if result.killed:
		CombatEvents.fighter_died.emit(target, attacker)


func _physics_process(delta: float) -> void:
	var cmd: InputCommand
	if controller:
		cmd = controller.get_command(self)
	else:
		cmd = InputCommand.new()  # an uncontrolled fighter stands still, facing where it faces
		cmd.aim_yaw = state.facing_yaw
	simulate(cmd, delta)


func simulate(cmd: InputCommand, delta: float) -> void:
	state.on_floor = is_on_floor()
	state.buffer_presses(cmd.pressed, tuning)
	if state.hitstop > 0.0:
		# frozen by a melee impact: time stands still for this fighter
		state.hitstop = maxf(state.hitstop - delta, 0.0)
		return
	state.tick(delta, tuning)
	_tick_statuses(delta)
	_advance_action(cmd, delta)
	if state.is_actionable():
		_act(cmd)
	_update_guard(cmd)
	_update_facing(cmd, delta)
	_move(cmd, delta)


func chest_position() -> Vector3:
	return global_position + Vector3.UP * CHEST_HEIGHT


## Where spells leave the gauntlet (left hand, chest height). Fixed relative
## to the body rather than read from the animation, so it's deterministic.
func cast_origin() -> Vector3:
	var f := forward()
	var left := Vector3(f.z, 0.0, -f.x)
	return global_position + Vector3.UP * 1.2 + f * 0.55 + left * 0.25


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

func _tick_statuses(delta: float) -> void:
	var burn := CombatRules.tick_statuses(state, delta, tuning)
	if burn <= 0.0:
		return
	var killed := state.take_damage(burn)
	CombatEvents.status_damage.emit(self, burn, SpellData.Element.FIRE)
	if killed:
		var killer: Object = instance_from_id(state.last_attacker_id) if is_instance_id_valid(state.last_attacker_id) else null
		CombatEvents.fighter_died.emit(self, killer)


func _advance_action(cmd: InputCommand, delta: float) -> void:
	match state.action:
		FighterState.Action.ATTACK:
			_advance_attack(cmd, delta)
		FighterState.Action.CAST:
			_advance_cast(cmd, delta)
		FighterState.Action.FLINCH, FighterState.Action.STAGGER, FighterState.Action.DASH:
			state.action_time += delta
			if state.action_time >= state.action_duration:
				state.end_action()
		FighterState.Action.DEAD:
			state.action_time += delta


## Starts a new action from IDLE, highest priority first.
func _act(cmd: InputCommand) -> void:
	if _try_dash(cmd) or _try_rune(cmd):
		return
	_try_parry()
	if state.on_floor and _try_attack(cmd):
		return
	if _try_cast():
		return


# --- runes ------------------------------------------------------------------

## Mobility rune: its own cooldown, no stamina, blocked by exhaustion. Can
## also cancel late attack or cast recovery, like a dash.
func _try_rune(cmd: InputCommand) -> bool:
	if rune == null or state.rune_cd > 0.0 or state.exhausted > 0.0:
		return false
	if not state.on_floor and not rune.air_use:
		return false
	if not state.consume_buffered(InputCommand.RUNE):
		return false
	if state.action != FighterState.Action.IDLE:
		state.end_action()
	rune.activate(self, cmd)
	state.rune_cd = rune.cooldown
	return true


# --- casting ------------------------------------------------------------------

## Primaries cost stamina; signatures wait for their cooldown. Casting works
## on the move and in the air, but not while exhausted.
func _try_cast() -> bool:
	if gauntlet == null or state.exhausted > 0.0:
		return false
	if state.can_spend() and state.consume_buffered(InputCommand.PRIMARY):
		_start_cast(gauntlet.primary)
		return true
	if state.signature_cd <= 0.0 and state.consume_buffered(InputCommand.SIGNATURE):
		_start_cast(gauntlet.signature)
		return true
	return false


func _start_cast(spell: SpellData) -> void:
	state.start_action(FighterState.Action.CAST)
	state.spell = spell
	if spell.stamina_cost > 0.0:
		state.spend_stamina(spell.stamina_cost, tuning)


func _advance_cast(cmd: InputCommand, delta: float) -> void:
	var spell := state.spell
	state.action_time += delta
	if not state.spell_released and state.action_time >= spell.windup:
		state.spell_released = true
		if spell.cooldown > 0.0:
			state.signature_cd = spell.cooldown
		spell.release(self, cmd.aim_target)
		CombatEvents.spell_cast.emit(self, spell)
	if state.spell_released and (_try_dash(cmd) or _try_rune(cmd)):
		return
	if state.action_time >= spell.windup + spell.recovery:
		state.end_action()


# --- dash ---------------------------------------------------------------------

## A quick step in the move direction (backwards with no input) with
## invulnerability at the start.
func _try_dash(cmd: InputCommand) -> bool:
	if not state.on_floor or not state.can_spend() or not state.consume_buffered(InputCommand.DASH):
		return false
	var direction := cmd.move_3d()
	direction = direction.normalized() if direction.length() > 0.2 else -forward()
	state.start_action(FighterState.Action.DASH, tuning.dash_duration)
	state.dash_dir = direction
	state.invulnerable = maxf(state.invulnerable, tuning.dash_iframes)
	state.spend_stamina(tuning.dash_stamina, tuning)
	return true


func _dash_speed() -> float:
	return tuning.dash_distance / maxf(tuning.dash_duration, 0.01)


# --- block and parry ----------------------------------------------------------

## A block press opens a short parry window, at most once per parry_cooldown.
## Presses during cooldown just block.
func _try_parry() -> void:
	if not state.has_buffered(InputCommand.BLOCK) or not _can_guard():
		return
	state.consume_buffered(InputCommand.BLOCK)
	if state.parry_cooldown <= 0.0:
		state.parry_window = tuning.parry_window
		state.parry_cooldown = tuning.parry_cooldown


func _update_guard(cmd: InputCommand) -> void:
	state.blocking = state.action == FighterState.Action.IDLE and cmd.is_held(InputCommand.BLOCK) and _can_guard()
	if state.action != FighterState.Action.IDLE:
		state.parry_window = 0.0


func _can_guard() -> bool:
	return state.on_floor and state.exhausted <= 0.0


# --- melee ------------------------------------------------------------------

func _try_attack(cmd: InputCommand) -> bool:
	if not state.can_spend():
		return false
	if state.consume_buffered(InputCommand.HEAVY):
		_start_attack(weapon.heavy, -1, cmd)
		return true
	if state.consume_buffered(InputCommand.LIGHT):
		var chaining := state.action == FighterState.Action.ATTACK or state.since_attack <= tuning.combo_reset
		var index := (state.combo_index + 1) % weapon.light_chain.size() if chaining else 0
		_start_attack(weapon.light_chain[index], index, cmd)
		return true
	return false


func _start_attack(attack: AttackData, combo_index: int, cmd: InputCommand) -> void:
	state.start_action(FighterState.Action.ATTACK)
	state.attack = attack
	state.combo_index = combo_index
	state.spend_stamina(attack.stamina_cost, tuning)
	_magnet = _find_magnet_target(cmd.aim_yaw)


func _advance_attack(cmd: InputCommand, delta: float) -> void:
	var attack := state.attack
	var before := state.action_time
	state.action_time += delta
	var now := state.action_time
	if now < attack.windup:
		_magnet = _find_magnet_target(cmd.aim_yaw)
	# sweep on every tick that overlaps the active window
	if now >= attack.windup and before < attack.windup + attack.active:
		_sweep(attack)
		if state.action != FighterState.Action.ATTACK:
			return  # parried mid-swing
	var into_recovery := now - attack.windup - attack.active
	if into_recovery >= attack.dodge_cancel_after and (_try_dash(cmd) or _try_rune(cmd)):
		return
	if into_recovery >= attack.chain_after and _try_attack(cmd):
		return
	if now >= attack.duration():
		state.end_action()


## The enemy nearest the aim direction, within the magnet cone and range.
func _find_magnet_target(aim_yaw: float) -> Fighter:
	var aim := CombatRules.yaw_to_dir(aim_yaw)
	var best: Fighter = null
	var best_score := INF
	for other in enemies():
		var to := other.global_position - global_position
		to.y = 0.0
		var distance := to.length()
		if distance < 0.01 or distance > tuning.magnet_range:
			continue
		var angle := aim.angle_to(to)
		if angle > deg_to_rad(tuning.magnet_angle):
			continue
		var score := distance + angle * 3.0
		if score < best_score:
			best = other
			best_score = score
	return best


func _sweep(attack: AttackData) -> void:
	for target in enemies():
		var id := target.get_instance_id()
		if state.swing_hits.has(id) or not _in_swing(target, attack):
			continue
		state.swing_hits.append(id)
		var from_front := CombatRules.is_in_front(target.state.facing_yaw, target.global_position,
				global_position, tuning.block_arc)
		var result := CombatRules.resolve_melee(state, target.state, attack, from_front, tuning)
		_apply_melee_impact(target, attack, result)
		if state.action != FighterState.Action.ATTACK:
			return


func _in_swing(target: Fighter, attack: AttackData) -> bool:
	var to := target.global_position - global_position
	if absf(to.y) > 1.6:
		return false
	to.y = 0.0
	var distance := to.length()
	if distance > attack.reach + RADIUS:
		return false
	if distance > RADIUS and forward().angle_to(to) > deg_to_rad(attack.arc * 0.5):
		return false
	var query := PhysicsRayQueryParameters3D.create(chest_position(), target.chest_position(), 1)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## Knockback and hit-stop live in the simulation (they change positions and
## timing); everything cosmetic listens to CombatEvents.
func _apply_melee_impact(target: Fighter, attack: AttackData, result: HitResult) -> void:
	var push := target.global_position - global_position
	push.y = 0.0
	push = push.normalized() if push.length() > 0.01 else forward()
	match result.outcome:
		HitResult.Outcome.HIT:
			target.state.knockback = push * attack.knockback
			_freeze(target, attack.hitstop)
		HitResult.Outcome.BLOCKED:
			target.state.knockback = push * attack.knockback * 0.5
			_freeze(target, attack.hitstop * 0.7)
		HitResult.Outcome.GUARD_BREAK:
			target.state.knockback = push * attack.knockback * 1.2
			_freeze(target, attack.hitstop * 1.2)
		HitResult.Outcome.PARRIED:
			state.knockback = -push * 2.5
			_freeze(target, 0.12)
	report_hit(self, target, result, target.chest_position() - push * 0.35)


func _freeze(target: Fighter, seconds: float) -> void:
	state.hitstop = maxf(state.hitstop, seconds)
	target.state.hitstop = maxf(target.state.hitstop, seconds)


# --- facing and movement ----------------------------------------------------

func _update_facing(cmd: InputCommand, delta: float) -> void:
	match state.action:
		FighterState.Action.IDLE, FighterState.Action.CAST:
			_turn_toward(cmd.aim_yaw, tuning.turn_rate, delta)
		FighterState.Action.ATTACK:
			if state.action_time < state.attack.windup:
				var yaw := cmd.aim_yaw
				if _magnet:
					yaw = CombatRules.dir_to_yaw(_magnet.global_position - global_position)
				_turn_toward(yaw, state.attack.windup_turn_rate, delta)


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
		FighterState.Action.CAST:
			target = cmd.move_3d() * tuning.walk_speed * tuning.cast_move_mult * CombatRules.move_speed_mult(state, tuning)
		FighterState.Action.ATTACK:
			target = _lunge_velocity()
			accel = 80.0
		FighterState.Action.DASH:
			target = state.dash_dir * _dash_speed()
			accel = 1000.0
	if state.leaping and state.action in [FighterState.Action.IDLE, FighterState.Action.CAST]:
		target = _air_velocity(cmd)
		accel = tuning.air_accel
	target += state.knockback
	state.knockback = state.knockback.move_toward(Vector3.ZERO, 14.0 * delta)
	var planar := Vector3(velocity.x, 0.0, velocity.z).move_toward(target, accel * delta)
	velocity.x = planar.x
	velocity.z = planar.z
	if state.on_floor and velocity.y < 0.0:
		velocity.y = 0.0
	var leap := rune as LeapRune if state.leaping else null
	var gravity := tuning.gravity
	if leap and velocity.y < 0.0:
		gravity *= leap.fall_gravity_mult
	velocity.y -= gravity * delta
	if leap:
		velocity.y = maxf(velocity.y, -leap.max_fall_speed)
	move_and_slide()
	if state.leaping and is_on_floor() and velocity.y <= 0.0:
		state.leaping = false
		CombatEvents.landed.emit(self)


## Airborne steering after a leap: no drag when you let go, and you can steer
## at the leap's air speed (or faster if you launched faster).
func _air_velocity(cmd: InputCommand) -> Vector3:
	var planar := Vector3(velocity.x, 0.0, velocity.z)
	var wish := cmd.move_3d()
	if wish.length() < 0.1:
		return planar
	var leap := rune as LeapRune
	return wish * maxf(leap.air_speed if leap else tuning.walk_speed, planar.length())


func _locomotion_velocity(cmd: InputCommand, delta: float) -> Vector3:
	var wish := cmd.move_3d()
	var sprinting := cmd.is_held(InputCommand.SPRINT) and wish.length() > 0.3 \
			and state.can_spend() and not state.blocking
	if sprinting:
		state.spend_stamina(tuning.sprint_stamina_per_sec * delta, tuning)
	var speed := tuning.sprint_speed if sprinting else tuning.walk_speed
	if state.blocking:
		speed *= tuning.block_move_mult
	return wish * speed * CombatRules.move_speed_mult(state, tuning)


## Swings carry you forward through wind-up and active frames, homing on the
## magnet target and stopping short of it. Recovery is committed: no movement.
func _lunge_velocity() -> Vector3:
	var attack := state.attack
	if state.action_time >= attack.windup + attack.active:
		return Vector3.ZERO
	var speed := attack.lunge_speed
	if _magnet:
		var gap := (_magnet.global_position - global_position) * Vector3(1, 0, 1)
		var distance := gap.length()
		if distance <= tuning.magnet_stop_distance:
			speed = 0.0
		elif distance > attack.reach:
			speed *= 1.5
	return forward() * speed
