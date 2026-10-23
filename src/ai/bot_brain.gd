class_name BotBrain
extends RefCounted
## Drives a fighter by producing InputCommands, exactly like the player's
## controller does, so the bot obeys every rule the player does. The dummy
## modes are predictable practice partners; DUELIST actually fights. The
## duelist sees its opponent through a reaction delay, and `difficulty` (0..1)
## scales its reactions, parry/block/dodge odds, aim and aggression.

enum Mode { IDLE, BLOCK, ATTACK_LOOP, CAST_LOOP, DUELIST }

const MODE_NAMES: Array[String] = ["Dummy: idle", "Dummy: always block", "Dummy: attack loop", "Dummy: cast loop", "Duelist"]
const MELEE_RANGE := 2.3

var mode := Mode.DUELIST
var difficulty := 0.5
var rng := RandomNumberGenerator.new()

var _time := 0.0
var _hold := 0
var _press := 0
var _prev_held := 0

# reacting to the opponent's swings
var _seen_attack_serial := -1
var _threat: AttackData
var _threat_started := 0.0
var _threat_react_at := INF
var _block_until := 0.0
var _parry_at := INF
var _dodge_at := INF
var _dodge_dir := Vector3.ZERO
var _seen_projectiles := {}
var _foe_block_since := -1.0

# offence
var _next_attack := 0.0
var _chain_left := 0
var _chained_serial := -1
var _next_cast := 0.0
var _loop_step := 0

# footwork
var _strafe := 1.0
var _strafe_flip_at := 0.0
var _stuck_for := 0.0


func _init(start_mode := Mode.DUELIST, start_difficulty := 0.5, seed_value := 0) -> void:
	mode = start_mode
	difficulty = start_difficulty
	rng.seed = seed_value


func get_command(me: Fighter) -> InputCommand:
	var dt := me.get_physics_process_delta_time()
	_time += dt
	_press = 0
	_hold = 0
	var cmd := InputCommand.new()
	cmd.aim_yaw = me.state.facing_yaw
	var foe := _nearest_enemy(me)
	if foe == null or me.state.is_dead():
		return _finish(cmd)
	var to := foe.global_position - me.global_position
	to.y = 0.0
	var distance := to.length()
	var toward := to.normalized() if distance > 0.01 else me.forward()
	cmd.aim_yaw = CombatRules.dir_to_yaw(toward)
	cmd.aim_target = foe.chest_position()
	var move := Vector3.ZERO
	match mode:
		Mode.BLOCK:
			_hold |= InputCommand.BLOCK
		Mode.ATTACK_LOOP:
			move = _attack_loop(me, distance, toward)
		Mode.CAST_LOOP:
			move = _cast_loop(me, foe, distance, toward, cmd)
		Mode.DUELIST:
			move = _duel(me, foe, distance, toward, cmd, dt)
	cmd.move = Vector2(move.x, move.z).limit_length(1.0)
	return _finish(cmd)


func _finish(cmd: InputCommand) -> InputCommand:
	cmd.held = _hold | _press
	cmd.pressed = _press | (cmd.held & ~_prev_held)
	_prev_held = cmd.held
	return cmd


# --- skill knobs ----------------------------------------------------------------

func _reaction() -> float:
	return lerpf(0.42, 0.14, difficulty) * rng.randf_range(0.85, 1.25)


func _parry_odds() -> float:
	return lerpf(0.05, 0.65, difficulty)


func _block_odds() -> float:
	return lerpf(0.35, 0.9, difficulty)


func _dodge_odds() -> float:
	return lerpf(0.1, 0.6, difficulty)


func _aggression() -> float:
	return lerpf(0.35, 0.85, difficulty)


func _aim_error() -> float:
	return lerpf(1.4, 0.15, difficulty)


# --- dummy modes ----------------------------------------------------------------

## Walks up and alternates a full light chain with a lone heavy, with pauses
## in between: parry and block practice.
func _attack_loop(me: Fighter, distance: float, toward: Vector3) -> Vector3:
	_continue_chain(me)
	if distance > MELEE_RANGE - 0.3:
		return toward
	if _time >= _next_attack and me.state.is_actionable():
		if _loop_step % 2 == 0:
			_press |= InputCommand.LIGHT
			_chain_left = 2
			_next_attack = _time + 2.6
		else:
			_press |= InputCommand.HEAVY
			_next_attack = _time + 2.8
		_loop_step += 1
	return Vector3.ZERO


## Keeps 9-13m away and casts: dodge and block practice.
func _cast_loop(me: Fighter, foe: Fighter, distance: float, toward: Vector3, cmd: InputCommand) -> Vector3:
	cmd.aim_target = _lead(me, foe, 0.0)
	if me.state.is_actionable():
		if me.state.signature_cd <= 0.0 and _signature_fits(me, distance):
			_press |= InputCommand.SIGNATURE
		elif _time >= _next_cast:
			_press |= InputCommand.PRIMARY
			_next_cast = _time + 1.6
	if distance < 9.0:
		return -toward
	if distance > 13.0:
		return toward
	return Vector3.ZERO


# --- the duelist ------------------------------------------------------------------

func _duel(me: Fighter, foe: Fighter, distance: float, toward: Vector3, cmd: InputCommand, dt: float) -> Vector3:
	var s := me.state
	var tuning := me.tuning
	_watch_swings(foe, distance)
	_watch_projectiles(me)
	_track_foe_guard(foe)

	# timed defensive inputs scheduled by the watchers
	if _time >= _parry_at:
		_press |= InputCommand.BLOCK
		_block_until = maxf(_block_until, _time + 0.25)
		_parry_at = INF
	if _time >= _dodge_at:
		_press |= InputCommand.DASH
		_dodge_at = INF
		return _dodge_dir
	if _time < _block_until:
		_hold |= InputCommand.BLOCK
		return _strafe_dir(toward) * 0.4
	if _parry_at < INF or _dodge_at < INF:
		return _strafe_dir(toward) * 0.3  # hands free for the planned parry or dodge

	var zone_exit := _escape_zones(me)
	if zone_exit != Vector3.ZERO:
		return zone_exit

	# low on health: go heal if an orb is reachable
	if s.hp < s.max_hp * 0.38:
		var heal_move := _seek_orb(me, foe)
		if heal_move != Vector3.ZERO:
			return heal_move

	_continue_chain(me)

	# punish staggers immediately
	if foe.state.action == FighterState.Action.STAGGER and distance <= MELEE_RANGE + 0.8 and s.is_actionable():
		var long_stagger := foe.state.action_duration - foe.state.action_time > 0.9
		_press |= InputCommand.HEAVY if long_stagger and s.stamina > 30.0 else InputCommand.LIGHT
		_chain_left = 0 if long_stagger else 2
		return toward

	var low_stamina := s.stamina < 28.0
	if low_stamina and distance < 5.0:
		if s.hp < s.max_hp * 0.3 and s.rune_cd <= 0.0 and rng.randf() < 0.02:
			_press |= InputCommand.RUNE  # bail out
		return (-toward + _strafe_dir(toward) * 0.8).normalized()

	# melee range: swing, or break a turtle with a heavy
	if distance <= MELEE_RANGE:
		if s.is_actionable() and _time >= _next_attack and s.stamina > 15.0:
			if _foe_seems_blocking(foe) and rng.randf() < 0.55 + 0.3 * difficulty:
				_press |= InputCommand.HEAVY
			elif rng.randf() < 0.18:
				_press |= InputCommand.HEAVY
			else:
				_press |= InputCommand.LIGHT
				_chain_left = int(rng.randf() < _aggression()) + int(rng.randf() < _aggression() * 0.7)
			_next_attack = _time + lerpf(1.25, 0.45, _aggression()) + rng.randf() * 0.4
		if me.gauntlet.signature is NovaSpell and s.signature_cd <= 0.0 and s.is_actionable() and rng.randf() < 0.02:
			_press |= InputCommand.SIGNATURE
		return _strafe_dir(toward) * 0.5 + toward * (0.3 if distance > MELEE_RANGE - 0.6 else -0.3)

	# mid/long range: cast while closing in
	if s.is_actionable() and _has_line_of_sight(me, foe):
		cmd.aim_target = _lead(me, foe, _aim_error())
		if s.signature_cd <= 0.0 and _signature_fits(me, distance) and rng.randf() < 0.05:
			_press |= InputCommand.SIGNATURE
		elif _time >= _next_cast and s.stamina > 45.0 and distance > 4.5:
			_press |= InputCommand.PRIMARY
			_next_cast = _time + lerpf(2.4, 1.0, _aggression()) + rng.randf() * 0.6
	var move := toward + _strafe_dir(toward) * 0.35
	if distance > 9.0 and s.stamina > 55.0:
		_hold |= InputCommand.SPRINT
	return _unstick(me, move, dt)


## Notices a new swing, then answers it after a reaction delay: parry, block,
## dodge, or (at low skill) eat it.
func _watch_swings(foe: Fighter, distance: float) -> void:
	var fs := foe.state
	if fs.action == FighterState.Action.ATTACK and fs.action_serial != _seen_attack_serial:
		_seen_attack_serial = fs.action_serial
		_threat = fs.attack
		_threat_started = _time - fs.action_time
		_threat_react_at = _time + _reaction()
	if _time < _threat_react_at:
		return
	_threat_react_at = INF
	if fs.action != FighterState.Action.ATTACK or fs.action_serial != _seen_attack_serial:
		return
	if distance > _threat.reach + 1.5:
		return
	var hits_at := _threat_started + _threat.windup
	var time_left := hits_at - _time
	var parry_lead := GameData.tuning.parry_window * 0.5
	if _threat.breaks_block:
		if time_left > parry_lead and rng.randf() < _parry_odds():
			_parry_at = hits_at - parry_lead
		elif time_left > 0.05 and rng.randf() < _dodge_odds():
			_schedule_dodge(foe, _time)
		elif rng.randf() < 0.4:
			_block_until = hits_at + 0.3  # a mistake: blocking a heavy
	else:
		if time_left > parry_lead and rng.randf() < _parry_odds() * 0.6:
			_parry_at = hits_at - parry_lead
		elif rng.randf() < _block_odds():
			_block_until = maxf(_block_until, maxf(hits_at, _time) + 0.45)
		elif time_left > 0.05 and rng.randf() < _dodge_odds() * 0.5:
			_schedule_dodge(foe, _time)


## Sidesteps or blocks incoming spells it has had time to notice.
func _watch_projectiles(me: Fighter) -> void:
	for node in me.get_tree().get_nodes_in_group(&"projectiles"):
		var bolt := node as Projectile
		if bolt.team == me.team or _seen_projectiles.has(bolt.get_instance_id()):
			continue
		var rel := me.chest_position() - bolt.global_position
		var speed := bolt.velocity.length()
		if speed < 1.0 or rel.length() > 14.0 or bolt.velocity.dot(rel) <= 0.0:
			continue
		var along := bolt.velocity.normalized()
		var miss := (rel - along * rel.dot(along)).length()
		if miss > 1.3:
			continue
		_seen_projectiles[bolt.get_instance_id()] = true
		var impact_in := rel.length() / speed
		var react := _reaction()
		if impact_in <= react + 0.05:
			continue
		if rng.randf() < _dodge_odds():
			_dodge_at = _time + react
			var side := along.cross(Vector3.UP).normalized()
			_dodge_dir = side if rng.randf() < 0.5 else -side
		elif rng.randf() < _block_odds() * 0.5:
			_block_until = maxf(_block_until, _time + impact_in + 0.2)
	if _seen_projectiles.size() > 64:
		_seen_projectiles.clear()


func _schedule_dodge(foe: Fighter, at: float) -> void:
	_dodge_at = at
	var away := foe.forward()
	_dodge_dir = (away.cross(Vector3.UP) * (1.0 if rng.randf() < 0.5 else -1.0) + away * 0.5).normalized()


## Remembers when the opponent raised their guard; it only "sees" it after a delay.
func _track_foe_guard(foe: Fighter) -> void:
	if foe.state.blocking:
		if _foe_block_since < 0.0:
			_foe_block_since = _time
	else:
		_foe_block_since = -1.0


func _foe_seems_blocking(foe: Fighter) -> bool:
	return foe.state.blocking and _foe_block_since >= 0.0 and _time - _foe_block_since >= lerpf(0.4, 0.15, difficulty)


## Keeps a light chain going: one more press per swing while _chain_left lasts.
func _continue_chain(me: Fighter) -> void:
	var s := me.state
	if _chain_left <= 0 or s.action != FighterState.Action.ATTACK or s.attack == me.weapon.heavy:
		return
	if s.action_serial == _chained_serial:
		return
	if s.action_time >= s.attack.windup + s.attack.active + s.attack.chain_after - 0.1:
		_press |= InputCommand.LIGHT
		_chained_serial = s.action_serial
		_chain_left -= 1


func _signature_fits(me: Fighter, distance: float) -> bool:
	if me.gauntlet.signature is NovaSpell:
		return distance < (me.gauntlet.signature as NovaSpell).radius - 1.0
	return distance > 5.0 and distance < 14.0


## Aim point with a little lead on a moving target, plus skill-scaled error.
func _lead(me: Fighter, foe: Fighter, error: float) -> Vector3:
	var speed := 40.0
	if me.gauntlet.primary is ProjectileSpell:
		speed = (me.gauntlet.primary as ProjectileSpell).speed
	var flight := me.cast_origin().distance_to(foe.chest_position()) / speed
	var point := foe.chest_position() + Vector3(foe.velocity.x, 0.0, foe.velocity.z) * flight * lerpf(0.3, 1.0, difficulty)
	var wobble := Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)).limit_length(1.0) * error
	return point + Vector3(wobble.x, wobble.y * 0.5, 0.0)


func _strafe_dir(toward: Vector3) -> Vector3:
	if _time >= _strafe_flip_at:
		_strafe = -_strafe if rng.randf() < 0.6 else _strafe
		_strafe_flip_at = _time + rng.randf_range(0.8, 2.0)
	return toward.cross(Vector3.UP) * _strafe


## If we're pushing into something and not moving, slide sideways for a bit.
func _unstick(me: Fighter, move: Vector3, dt: float) -> Vector3:
	var speed := Vector2(me.velocity.x, me.velocity.z).length()
	_stuck_for = _stuck_for + dt if move.length() > 0.5 and speed < 0.6 and me.state.action == FighterState.Action.IDLE else 0.0
	if _stuck_for > 0.5:
		_strafe = -_strafe
		_stuck_for = 0.0
		_strafe_flip_at = _time + 1.5
	if _stuck_for > 0.25:
		return move.cross(Vector3.UP).normalized() * _strafe
	return move


## Steps out of enemy ground fire the short way.
func _escape_zones(me: Fighter) -> Vector3:
	for node in me.get_tree().get_nodes_in_group(&"zones"):
		var wall := node as FlameWall
		if wall.team != me.team and wall.contains(me.global_position, Fighter.RADIUS + 0.5):
			return wall.exit_direction(me.global_position)
	return Vector3.ZERO


## Heads for the nearest available orb that isn't closer to the opponent.
func _seek_orb(me: Fighter, foe: Fighter) -> Vector3:
	var best: HealthOrb = null
	var best_distance := 18.0
	for node in me.get_tree().get_nodes_in_group(&"orbs"):
		var orb := node as HealthOrb
		if not orb.available:
			continue
		var d := me.global_position.distance_to(orb.global_position)
		if d < best_distance and d < foe.global_position.distance_to(orb.global_position) + 2.0:
			best = orb
			best_distance = d
	if best == null:
		return Vector3.ZERO
	var to := best.global_position - me.global_position
	if to.y > 1.0 and Vector2(to.x, to.z).length() < 6.5 and me.rune is LeapRune and me.state.rune_cd <= 0.0:
		_press |= InputCommand.RUNE  # up onto the ledge
	if me.state.stamina > 40.0:
		_hold |= InputCommand.SPRINT
	return Vector3(to.x, 0.0, to.z).normalized()


func _has_line_of_sight(me: Fighter, foe: Fighter) -> bool:
	var query := PhysicsRayQueryParameters3D.create(me.cast_origin(), foe.chest_position(), 1)
	return me.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


static func _nearest_enemy(me: Fighter) -> Fighter:
	var best: Fighter = null
	for other in me.enemies():
		if best == null or me.global_position.distance_squared_to(other.global_position) \
				< me.global_position.distance_squared_to(best.global_position):
			best = other
	return best
