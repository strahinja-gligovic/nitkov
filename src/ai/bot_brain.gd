class_name BotBrain
extends RefCounted
## Drives a fighter by producing InputCommands, exactly like the player's
## controller does, so the bot obeys every rule the player does. The dummy
## modes are predictable practice partners; DUELIST actually fights. The
## duelist sees its opponent through a reaction delay, and `difficulty` (0..1)
## scales its reactions, parry/block/dodge odds, aim, spell sense and aggression.
##
## Spells, offence: each projectile is led by its own speed (the Wind Spear
## is thrown at the feet so a miss still bursts beside them), Lightning
## Strike is called where the target will stand when the bolt lands, and
## every signature waits for a moment that suits it (a stunned, swinging or
## guarding target for the strike, a Chilled one for the Flame Wall, a foe in
## reach who can't guard for the Frost Nova, a blast or an escape for the
## spear) before patience runs out. Defence: it reads enemy casts and guards
## the bolts it can't dodge on sight, sidesteps the Wind Spear, and gets out
## of a marked strike circle before the bolt lands, dashing if it must.

enum Mode { IDLE, BLOCK, ATTACK_LOOP, CAST_LOOP, DUELIST }

const MODE_NAMES: Array[String] = ["Dummy: idle", "Dummy: always block", "Dummy: attack loop", "Dummy: cast loop", "Duelist"]
const MELEE_RANGE := 2.3
## Seconds of the opponent's movement averaged to judge how steady their heading is.
const HEADING_WINDOW := 0.6
## Headings tried, in degrees off the wanted one, when walking around ground fire.
const STEER_ANGLES: Array[float] = [0.0, 30.0, -30.0, 60.0, -60.0, 90.0, -90.0, 135.0, -135.0]
## Aim heights above the target's feet, best first: a Wind Spear at the feet
## (a miss still bursts beside them), a Firebolt low (a near miss splashes
## off the floor), anything else at the body; higher if cover is in the way.
const FEET_FIRST: Array[float] = [0.05, 0.6, 1.0, 1.35]
const LOW_FIRST: Array[float] = [0.55, 1.0, 1.35]
const BODY_FIRST: Array[float] = [1.0, 1.35, 0.6]
## Headings tried, in degrees off straight out, when leaving a strike circle.
const EXIT_ANGLES: Array[float] = [0.0, 35.0, -35.0, 70.0, -70.0, 110.0, -110.0, 180.0]
## How a player is assumed to react to a strike marked under them (seconds).
const FOE_STRIKE_REACTION := 0.3
## Seconds of a moving target's motion a Lightning Strike leads: about a
## reaction time. Measured against logged duels and model players (keep
## going, or walk out 0.35-0.5 s after the mark appears), this lands far
## more often than aiming where they stand or leading the whole delay.
const STRIKE_LEAD := 0.4

## How the spell being cast is aimed, tick by tick, until it leaves the hand.
class CastPlan extends RefCounted:
	var spell: SpellData
	## shot, poke (spear at the feet), blast (spear point-blank), self_burst,
	## strike, wall, barrier (a wall between us) or nova.
	var kind := &"shot"
	## How good the moment is (signatures wait for a good enough one).
	var score := 0.0
	## Fraction of the full lead this cast takes, and its aim error
	## (metres sideways and up), both drawn once per cast.
	var lead := 1.0
	var error := Vector2.ZERO
	## self_burst: the way the bot wants to be blown.
	var away := Vector3.ZERO
	## The target's ground velocity on the first aimed tick, to notice them
	## cutting back during the windup (INF until then).
	var foe_velocity := Vector3.INF
	var juke_seen := false


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

# reading the opponent's casts
var _seen_cast_serial := -1
var _cast_threat: SpellData
var _cast_release_at := 0.0
var _cast_react_at := INF
var _juke_until := 0.0
var _juke_dir := Vector3.ZERO
var _juke_flip_at := INF

# enemy zones: instance id -> [first seen, noticed at]; the noticed ones this tick
var _zones := {}
var _hazards: Array[Node] = []

# watching the opponent move
var _foe_velocity_avg := Vector3.ZERO
var _foe_speed_avg := 0.0
var _foe_last_position := Vector3.INF

# offence
var _next_attack := 0.0
var _chain_left := 0
var _chained_serial := -1
var _next_cast := 0.0
var _loop_step := 0
var _plan: CastPlan
## When the signature came off cooldown (-1 while it's cooling down).
var _signature_ready_at := -1.0
var _opportunity_serial := -1
var _seize := false

# footwork
var _strafe := 1.0
var _strafe_flip_at := 0.0
var _stuck_for := 0.0
var _slide_until := 0.0


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
	if me.state.is_dead():
		return _finish(cmd)
	if foe == null:
		# no one left to fight, but their fire or lightning can still be waiting
		if mode == Mode.DUELIST:
			var exit := _leave_hazards(me)
			cmd.move = Vector2(exit.x, exit.z)
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
			move = _cast_loop(me, foe, distance, toward, cmd, dt)
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


## Odds of seeing and seizing a spell opening (a Shatter, a stunned target).
func _spell_sense() -> float:
	return lerpf(0.3, 1.0, difficulty)


## Odds of sidestepping a Wind Spear: big and slow, so a good player dodges it.
func _spear_dodge_odds() -> float:
	return lerpf(0.05, 0.95, smoothstep(0.2, 0.85, difficulty))


## Odds of reading a projectile cast aimed at it and guarding before it flies.
func _cast_read_odds() -> float:
	return lerpf(0.0, 0.7, smoothstep(0.15, 1.0, difficulty))


## Seconds before a new strike circle or wall of fire under the bot registers.
func _zone_reaction() -> float:
	return _reaction() + rng.randf() * lerpf(0.35, 0.0, difficulty)


## Odds of thinking to dash out of a strike circle when walking won't do.
func _strike_dash_odds() -> float:
	return lerpf(0.15, 1.0, difficulty)


## The score a signature moment needs: picky at first (a skilled bot waits
## for an opening), less so the longer the spell has been ready.
func _signature_bar(waited: float) -> float:
	var patience := lerpf(1.0, 7.0, difficulty)
	return lerpf(lerpf(0.3, 0.55, difficulty), 0.05, clampf(waited / patience, 0.0, 1.0))


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


## Keeps 9-13m away and casts: dodge and block practice. Spells are aimed
## like the duelist's, but cast without waiting for an opening. A Frost Nova
## needs them close, so with it ready the dummy walks in to set it off. It
## steps out of the player's strike circles and fire like the duelist does.
func _cast_loop(me: Fighter, foe: Fighter, distance: float, toward: Vector3, cmd: InputCommand, dt: float) -> Vector3:
	_track_foe(foe, dt)
	_scan_zones(me)
	_aim_cast(me, foe, cmd)
	var signature_ready := me.state.signature_cd <= 0.0 and me.state.exhausted <= 0.0
	if me.state.is_actionable():
		var plan := _plan_signature(me, foe, distance) if signature_ready else null
		if plan != null and plan.score > 0.0:
			_press |= InputCommand.SIGNATURE
			_plan = _commit(plan)
		elif _time >= _next_cast and _in_range(me.primary, distance):
			_press |= InputCommand.PRIMARY
			_plan = _commit(_new_plan(me.primary, &"shot"))
			_next_cast = _time + 1.6
	var exit := _escape_strikes(me, foe)
	if exit == Vector3.ZERO:
		exit = _escape_ground_fire(me)
	if exit != Vector3.ZERO:
		return exit
	var move := Vector3.ZERO
	if signature_ready and me.signature is NovaSpell:
		move = toward if distance > 3.0 else Vector3.ZERO
	elif distance < 9.0:
		move = -toward
	elif distance > 13.0:
		move = toward
	return _steer(me, _unstick(me, move, dt))


# --- the duelist ------------------------------------------------------------------

func _duel(me: Fighter, foe: Fighter, distance: float, toward: Vector3, cmd: InputCommand, dt: float) -> Vector3:
	var s := me.state
	_track_foe(foe, dt)
	_watch_swings(foe, distance)
	_watch_casts(me, foe, distance)
	_watch_projectiles(me)
	_track_foe_guard(foe)
	_scan_zones(me)
	if s.signature_cd > 0.0:
		_signature_ready_at = -1.0
	elif _signature_ready_at < 0.0:
		_signature_ready_at = _time
	# a spell on its way out of the hand keeps tracking its target
	_aim_cast(me, foe, cmd)

	# lightning is about to land here: get out, whatever else was planned
	var strike_exit := _escape_strikes(me, foe)
	if strike_exit != Vector3.ZERO:
		return strike_exit
	# standing in fire: only a sword about to land is worth guarding in it
	if BotRead.swing_lands_in(foe.state) == INF or distance > MELEE_RANGE + 1.0:
		var fire_exit := _escape_ground_fire(me)
		if fire_exit != Vector3.ZERO:
			_block_until = 0.0
			return fire_exit

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

	var fire_exit := _escape_ground_fire(me)
	if fire_exit != Vector3.ZERO:
		return fire_exit  # (a swing was coming in: it's been answered)

	# sidestepping a spell we saw coming
	if _time < _juke_until:
		if _time >= _juke_flip_at:
			_juke_dir = -_juke_dir  # change direction as it leaves their hand
			_juke_flip_at = INF
		if s.stamina > 30.0:
			_hold |= InputCommand.SPRINT
		return _steer(me, _juke_dir)

	# punish staggers immediately (the sword beats any spell up close)
	if foe.state.action == FighterState.Action.STAGGER and distance <= MELEE_RANGE + 0.8 and s.is_actionable():
		var long_stagger := foe.state.action_duration - foe.state.action_time > 0.9
		_press |= InputCommand.HEAVY if long_stagger and s.stamina > 30.0 else InputCommand.LIGHT
		_chain_left = 0 if long_stagger else 2
		return toward

	# the signature, when the moment suits it
	if s.is_actionable() and _try_signature(me, foe, distance):
		return _steer(me, _strafe_dir(toward) * 0.4)

	# low on health: go heal if an orb is reachable
	if s.hp < s.max_hp * 0.38:
		var heal_move := _seek_orb(me, foe)
		if heal_move != Vector3.ZERO:
			return _steer(me, heal_move)

	_continue_chain(me)

	# a shot worth taking right now: a Shatter, a stunned or healing target, a cast to break
	if s.is_actionable() and _try_opportune_shot(me, foe, distance):
		return _steer(me, _strafe_dir(toward) * 0.4)

	var low_stamina := s.stamina < 28.0
	if low_stamina and distance < 5.0:
		if s.hp < s.max_hp * 0.3 and s.rune_cd <= 0.0 and rng.randf() < 0.02:
			_press |= InputCommand.RUNE  # bail out
		return _steer(me, (-toward + _strafe_dir(toward) * 0.8).normalized())

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
		return _steer(me, _strafe_dir(toward) * 0.5 + toward * (0.3 if distance > MELEE_RANGE - 0.6 else -0.3))

	# mid/long range: cast while closing in
	if s.is_actionable() and _time >= _next_cast and s.stamina > 45.0 and distance > 4.5:
		var shot := me.primary as ProjectileSpell
		if shot and distance < shot.max_range - 2.0 and _has_line_of_sight(me, foe):
			if _guarded_against(foe, me.global_position):
				_next_cast = _time + 0.4  # don't feed a raised guard; look again shortly
			else:
				_press |= InputCommand.PRIMARY
				_plan = _commit(_new_plan(shot, &"shot"))
				_next_cast = _time + lerpf(2.4, 1.0, _aggression()) + rng.randf() * 0.6
	var move := toward + _strafe_dir(toward) * 0.35
	if distance > 9.0 and s.stamina > 55.0:
		_hold |= InputCommand.SPRINT
	return _steer(me, _unstick(me, move, dt))


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


## Notices the opponent starting a cast and, after a reaction delay, gets
## ready for it the way a player would: guards a fast bolt it couldn't dodge
## on sight, gets moving before a Wind Spear, Lightning Strike or Flame Wall
## comes out, and backs off or guards when a Frost Nova is about to go off
## next to it.
func _watch_casts(me: Fighter, foe: Fighter, distance: float) -> void:
	var fs := foe.state
	if fs.action == FighterState.Action.CAST and fs.action_serial != _seen_cast_serial and not fs.spell_released:
		_seen_cast_serial = fs.action_serial
		_cast_threat = fs.spell
		_cast_release_at = _time + BotRead.release_in(fs)
		_cast_react_at = _time + _reaction()
	if _time < _cast_react_at:
		return
	_cast_react_at = INF
	if fs.action != FighterState.Action.CAST or fs.action_serial != _seen_cast_serial:
		return  # interrupted
	var release_left := _cast_release_at - _time
	var toward := _flat(foe.global_position - me.global_position).normalized()
	var aimed_at_me := foe.forward().angle_to(-toward) < deg_to_rad(30.0)
	if _cast_threat is ProjectileSpell and aimed_at_me:
		var shot := _cast_threat as ProjectileSpell
		if distance > shot.max_range:
			return
		var arrives := _cast_release_at + maxf(distance - 1.0, 0.0) / shot.speed
		if shot.burst_radius > 0.0:
			if release_left > 0.0 and rng.randf() < _spear_dodge_odds():
				# a skilled bot cuts back the other way as it's thrown, so a
				# spear led along the first step flies past
				_start_juke(me, _open_side(me, toward.cross(Vector3.UP) * _strafe), arrives - _time + 0.15,
						release_left - 0.05 if difficulty > 0.55 else INF)
		elif arrives > _time + 0.03 and me.state.is_actionable() and rng.randf() < _cast_read_odds():
			# too fast to dodge on sight: the guard goes up as soon as we see the cast
			_block_until = maxf(_block_until, arrives + 0.15)
	if release_left <= 0.0:
		return  # out already: the zone and projectile watchers take it from here
	if _cast_threat is LightningStrikeSpell:
		if rng.randf() < _spell_sense() * 0.8:
			# keep moving, and switch direction as it comes out so a leading aim misses
			_start_juke(me, _open_side(me, toward.cross(Vector3.UP) * _strafe), release_left + 0.2,
					release_left - 0.05 if difficulty > 0.5 else INF)
	elif _cast_threat is FlameWallSpell and aimed_at_me:
		# the wall lies across the line of fire: back off along it so we're
		# already stepping off the narrow strip when it rises
		if distance < (_cast_threat as FlameWallSpell).max_range + 1.0 and rng.randf() < _spell_sense() * 0.8:
			var back := -toward if not _wall_ahead(me, -toward, 2.5) else toward.cross(Vector3.UP) * _strafe
			_start_juke(me, back, release_left + 0.3)
	elif _cast_threat is NovaSpell:
		var nova := _cast_threat as NovaSpell
		if distance > nova.radius + Fighter.RADIUS + 0.5:
			return
		var room := nova.radius + Fighter.RADIUS + 0.3 - distance
		if room / me.tuning.walk_speed < release_left - 0.03 and rng.randf() < _spell_sense():
			_start_juke(me, -toward, release_left + 0.1)
		elif me.state.is_actionable() and rng.randf() < _block_odds() * _spell_sense():
			_block_until = maxf(_block_until, _cast_release_at + 0.15)


## Sidesteps or blocks incoming spells it has had time to notice. The Wind
## Spear is watched from further out, and dodged clear of where it will burst.
func _watch_projectiles(me: Fighter) -> void:
	var body := me.global_position + Vector3.UP * 0.9
	for node in me.get_tree().get_nodes_in_group(&"projectiles"):
		var bolt := node as Projectile
		if bolt.team == me.team or _seen_projectiles.has(bolt.get_instance_id()):
			continue
		var spell := bolt.spell
		var spear := spell.burst_radius > 0.0
		var rel := body - bolt.global_position
		var speed := bolt.velocity.length()
		if speed < 1.0 or rel.length() > (22.0 if spear else 14.0) or bolt.velocity.dot(rel) <= 0.0:
			continue
		var along := bolt.velocity / speed
		var offset := rel - along * rel.dot(along)
		var reach := spell.radius + Fighter.RADIUS + 0.35
		var threat := offset.length() <= reach
		if spear and not threat:
			# a spear thrown at the floor beside us still bursts on us
			var ground := BotAim.floor_point(bolt.global_position, bolt.velocity, me.global_position.y)
			threat = ground != Vector3.INF and ground.distance_to(body) <= spell.burst_radius + Fighter.RADIUS
		if not threat:
			continue
		_seen_projectiles[bolt.get_instance_id()] = true
		var impact_in := rel.dot(along) / speed
		var react := _reaction()
		if impact_in <= react + 0.03:
			continue
		var side := Vector3(offset.x, 0.0, offset.z)
		side = side.normalized() if side.length() > 0.2 else along.cross(Vector3.UP).normalized() * (1.0 if rng.randf() < 0.5 else -1.0)
		var odds := _spear_dodge_odds() if spear else _dodge_odds()
		if rng.randf() < odds and me.state.stamina > 0.0:
			_dodge_at = _time + react
			_dodge_dir = _open_side(me, side)
		elif rng.randf() < _block_odds() * 0.5:
			_block_until = maxf(_block_until, _time + impact_in + (0.3 if spear else 0.2))
	if _seen_projectiles.size() > 64:
		_seen_projectiles.clear()


func _schedule_dodge(foe: Fighter, at: float) -> void:
	_dodge_at = at
	var away := foe.forward()
	_dodge_dir = (away.cross(Vector3.UP) * (1.0 if rng.randf() < 0.5 else -1.0) + away * 0.5).normalized()


## Moves along `heading` for a while, out of a telegraphed spell's way.
## With `flip_in`, reverses then (as the spell leaves the caster's hand), so
## an aim that leads the old heading misses.
func _start_juke(me: Fighter, heading: Vector3, seconds: float, flip_in := INF) -> void:
	_juke_dir = heading
	_juke_until = _time + seconds
	_juke_flip_at = _time + flip_in if flip_in < seconds and not _wall_ahead(me, -heading, 2.5) else INF


## Remembers when the opponent raised their guard; it only "sees" it after a delay.
func _track_foe_guard(foe: Fighter) -> void:
	if foe.state.blocking:
		if _foe_block_since < 0.0:
			_foe_block_since = _time
	else:
		_foe_block_since = -1.0


func _foe_seems_blocking(foe: Fighter) -> bool:
	return foe.state.blocking and _foe_block_since >= 0.0 and _time - _foe_block_since >= lerpf(0.4, 0.15, difficulty)


## True if the opponent's guard (as far as the bot has noticed) faces
## `from`: a spell from there would be blocked.
func _guarded_against(foe: Fighter, from: Vector3) -> bool:
	return _foe_seems_blocking(foe) and CombatRules.is_in_front(foe.state.facing_yaw, foe.global_position, from, foe.tuning.block_arc)


## Averages the opponent's recent movement, to tell a straight run from jinking.
func _track_foe(foe: Fighter, dt: float) -> void:
	var velocity := _foe_velocity(foe)
	if _foe_last_position == Vector3.INF or foe.global_position.distance_to(_foe_last_position) > 3.0:
		_foe_velocity_avg = velocity  # first look, a respawn or a blink
		_foe_speed_avg = velocity.length()
	else:
		var blend := clampf(dt / HEADING_WINDOW, 0.0, 1.0)
		_foe_velocity_avg = _foe_velocity_avg.lerp(velocity, blend)
		_foe_speed_avg = lerpf(_foe_speed_avg, velocity.length(), blend)
	_foe_last_position = foe.global_position


## The opponent's own ground velocity: what they're steering, minus any shove.
func _foe_velocity(foe: Fighter) -> Vector3:
	var velocity := foe.velocity - foe.state.knockback
	return Vector3(velocity.x, 0.0, velocity.z)


## Where the opponent will probably be `horizon` seconds from now, stopping
## at walls. `lead` scales how far the bot trusts their heading.
func _predict(me: Fighter, foe: Fighter, horizon: float, lead: float) -> Vector3:
	var s := foe.state
	var pinned := BotRead.pinned_for(s)
	var velocity := _foe_velocity(foe) if pinned <= 0.05 else Vector3.ZERO
	var at := BotAim.predict_position(foe.global_position, velocity, s.knockback, pinned, horizon, lead)
	return _clip_to_walls(me, foe.global_position, at)


## How steady the opponent's heading has been lately (0..1).
func _steadiness() -> float:
	return BotAim.heading_steadiness(_foe_velocity_avg, _foe_speed_avg)


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


# --- spells: when ------------------------------------------------------------------

## Casts the signature if the moment is good enough for how long it has waited.
func _try_signature(me: Fighter, foe: Fighter, distance: float) -> bool:
	if me.state.signature_cd > 0.0 or me.state.exhausted > 0.0:
		return false
	var plan := _plan_signature(me, foe, distance)
	if plan == null or plan.score <= 0.0 or plan.score < _signature_bar(_time - _signature_ready_at):
		return false
	_press |= InputCommand.SIGNATURE
	_plan = _commit(plan)
	return true


## How (and how well) the signature could be used right now, or null if it
## can't be: out of range, no line, or we'd be cut down mid-cast.
func _plan_signature(me: Fighter, foe: Fighter, distance: float) -> CastPlan:
	var spell := me.signature
	if spell is LightningStrikeSpell:
		return _plan_strike(me, foe, spell as LightningStrikeSpell)
	if spell is NovaSpell:
		return _plan_nova(me, foe, spell as NovaSpell, distance)
	if spell is FlameWallSpell:
		return _plan_wall(me, foe, spell as FlameWallSpell, distance)
	if spell is ProjectileSpell:
		var projectile := spell as ProjectileSpell
		if projectile.burst_radius > 0.0:
			return _plan_spear(me, foe, projectile, distance)
		if distance < projectile.max_range - 2.0 and _has_line_of_sight(me, foe):
			return _new_plan(spell, &"shot", 0.5)
	return null


## Lightning Strike: mark where they'll stand when the bolt lands, and wait
## for a moment they can't walk out of in time: stunned, mid-swing, casting,
## guarding (a guard is no use against it), slowed, out of stamina, healing.
func _plan_strike(me: Fighter, foe: Fighter, spell: LightningStrikeSpell) -> CastPlan:
	var s := foe.state
	var at := _strike_point(me, foe, spell, spell.windup)
	var line := _flat(at - me.global_position)
	if line.length() < 1.0 or line.length() > spell.max_range + 1.0:
		return null
	# the mark lands at least min_range out: is the target still well under it?
	var centre := me.global_position + line.normalized() * clampf(line.length(), spell.min_range, spell.max_range)
	var off_centre := _flat(at - centre).length()
	if off_centre > spell.radius * 0.6:
		return null
	var edge := (spell.radius + Fighter.RADIUS) * 0.9 - off_centre
	var react := FOE_STRIKE_REACTION
	var walk := _strike_odds(BotRead.escape_time(s, me.tuning, spell.windup, edge, react, false) - spell.delay)
	var dash := _strike_odds(BotRead.escape_time(s, me.tuning, spell.windup, edge, react) - spell.delay)
	var score := (walk + dash) * 0.5
	# where a free runner ends up is a guess; a stuck one is a sure thing
	var pinned := BotRead.pinned_for(s)
	if pinned < spell.windup + 0.3:
		score *= lerpf(0.55, 0.95, _steadiness())
	if s.blocking:
		score += 0.2
	if s.heal_time > 0.0:
		score += 0.25
	if s.stamina < me.tuning.dash_stamina:
		score += 0.1
	return _new_plan(spell, &"strike", score)


## Where to call the strike so the target is still inside when it lands
## (`release_in` seconds until the mark appears). Someone stuck in place
## (stunned, mid-swing) is where they'll be. Someone moving keeps going only
## until they notice the mark, then runs from it: lead them by about a
## reaction time, so they're near its centre, with the farthest to go, just
## as they start running (and still inside at the end if they never notice).
func _strike_point(me: Fighter, foe: Fighter, spell: LightningStrikeSpell, release_in: float) -> Vector3:
	var s := foe.state
	var pinned := BotRead.pinned_for(s)
	var at := foe.global_position + BotAim.knockback_travel(s.knockback)
	if pinned < release_in + spell.delay and pinned <= 0.05:
		var jitter := _plan.lead / lerpf(0.35, 1.0, difficulty) if _plan and _plan.spell == spell else 1.0
		var velocity := _foe_velocity(foe)
		at += velocity * maxf(release_in + STRIKE_LEAD * jitter, 0.0)
		var reach := _flat(at - me.global_position)
		if velocity.dot(reach) < 0.0 and reach.length() < MELEE_RANGE:
			# charging in: they stop at sword's reach
			at = me.global_position + reach.normalized() * MELEE_RANGE + Vector3.UP * (at.y - me.global_position.y)
	return _clip_to_walls(me, foe.global_position, at)


## `to`, pulled back short of any wall between it and `from`.
func _clip_to_walls(me: Fighter, from: Vector3, to: Vector3) -> Vector3:
	var ray := PhysicsRayQueryParameters3D.create(from + Vector3.UP * 0.6, to + Vector3.UP * 0.6, 1)
	var hit := me.get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():
		return to
	var back := _flat(to - from).normalized() * 0.5
	return Vector3(hit.position.x, to.y, hit.position.z) - back


## 0 when they'll be out well before the bolt lands, 1 when they can't be.
static func _strike_odds(late_by: float) -> float:
	return clampf((late_by + 0.3) / 0.6, 0.0, 1.0)


## Frost Nova: when they'll be inside the blast as it goes off and can't
## guard it (mid-swing, casting, stunned), as a way out when we're hurt, and
## as the opener for a Firebolt Shatter.
func _plan_nova(me: Fighter, foe: Fighter, spell: NovaSpell, distance: float) -> CastPlan:
	if distance > spell.radius + 2.0:
		return null
	var at := _predict(me, foe, spell.windup, 1.0)
	var reach := _flat(at - me.global_position).length()
	if reach > spell.radius + Fighter.RADIUS - 0.35 or absf(foe.global_position.y - me.global_position.y) > 2.0:
		return null
	if not _has_line_of_sight(me, foe):
		return null
	var s := foe.state
	if BotRead.swing_lands_in(s) < spell.windup + 0.05 and distance < MELEE_RANGE + 0.5:
		return null  # their blade lands first and cancels the cast
	var score := 0.35
	if _guarded_against(foe, me.global_position):
		score -= 0.6
	elif BotRead.guard_down(s):
		score += 0.35
	if me.state.hp < me.state.max_hp * 0.45:
		score += 0.25
	if me.primary.element == SpellData.Element.FIRE and s.chill_stacks == 0:
		score += 0.2
	if reach < 3.0:
		score += 0.1
	return _new_plan(spell, &"nova", score)


## Flame Wall: on top of them when they can't step off it in time, and above
## all on a Chilled target (its first tick Shatters them). When we're hurt
## and being chased, a wall between us instead.
func _plan_wall(me: Fighter, foe: Fighter, spell: FlameWallSpell, distance: float) -> CastPlan:
	var s := foe.state
	var horizon := spell.windup + spell.tick_interval
	var at := _predict(me, foe, horizon, lerpf(0.5, 1.0, _steadiness()))
	var reach := _flat(at - me.global_position).length()
	if reach > spell.max_range or reach < spell.min_range - 0.8:
		return null
	var score := 0.12
	if s.chill_stacks > 0 and s.chill_time > horizon + 0.1:
		score += 0.7
	if BotRead.pinned_for(s) > spell.windup + 0.4:
		score += 0.45
	if s.blocking:
		score += 0.15
	if CombatRules.move_speed_mult(s, me.tuning) < 0.95:
		score += 0.15
	# running across our line of fire keeps them inside the wall's length
	var toward := _flat(foe.global_position - me.global_position).normalized()
	var across := absf(_foe_velocity(foe).dot(toward.cross(Vector3.UP)))
	if across > 3.0 and _steadiness() > 0.6:
		score += 0.2
	var hurt := me.state.hp < me.state.max_hp * 0.4
	var chasing := _foe_velocity(foe).dot(-toward) > 2.5
	if hurt and chasing and distance > 4.0 and distance < 12.0:
		return _new_plan(spell, &"barrier", maxf(score, 0.5))
	return _new_plan(spell, &"wall", score)


## Wind Spear: point-blank, blast them away (the burst throws us back too);
## hurt and pressed against a raised guard, burst it at our own feet to get
## clear; at range, throw it at their feet so even a miss bursts beside them.
func _plan_spear(me: Fighter, foe: Fighter, spell: ProjectileSpell, distance: float) -> CastPlan:
	var s := foe.state
	var hurt := me.state.hp < me.state.max_hp * 0.4
	if distance <= 3.5:
		var lands_in := BotRead.swing_lands_in(s)
		if lands_in < spell.windup + 0.05:
			return null  # their blade lands first and cancels the cast
		if _guarded_against(foe, me.global_position):
			if not hurt:
				return null
			var plan := _new_plan(spell, &"self_burst", 0.6)
			plan.away = _escape_heading(me, foe)
			return plan
		var score := 0.3
		if hurt:
			score += 0.35
		if BotRead.pinned_for(s) > spell.windup:
			score += 0.25
		if lands_in < INF:
			score += 0.3  # a slow heavy: blow them out of its reach before it lands
		return _new_plan(spell, &"blast", score)
	if distance < 5.0 or distance > 16.0 or not _has_line_of_sight(me, foe):
		return null
	var score := 0.2
	var toward := _flat(foe.global_position - me.global_position).normalized()
	var velocity := _foe_velocity(foe)
	if velocity.dot(-toward) > 2.5:
		score += 0.3  # running at us: easy to lead
	# running across the line of fire: it's slow enough for them to step out of
	score -= 0.25 * clampf((absf(velocity.dot(toward.cross(Vector3.UP))) - 2.0) / 3.0, 0.0, 1.0)
	if distance < 10.0:
		score += 0.1
	if BotRead.pinned_for(s) > spell.windup + distance / spell.speed:
		score += 0.35
	if not s.on_floor:
		score += 0.2
	if _guarded_against(foe, me.global_position):
		score -= 0.3
	return _new_plan(spell, &"poke", score)


## Fires the primary right away when it's worth more than usual: a Shatter
## on a Chilled target, a stunned or healing target, a cast it can break, or
## someone in the air who can't guard.
func _try_opportune_shot(me: Fighter, foe: Fighter, distance: float) -> bool:
	var spell := me.primary as ProjectileSpell
	var s := me.state
	if spell == null or not s.can_spend() or s.stamina < spell.stamina_cost + 5.0:
		return false
	if distance > spell.max_range - 1.0 or not _has_line_of_sight(me, foe):
		return false
	var fs := foe.state
	if fs.action_serial != _opportunity_serial:
		_opportunity_serial = fs.action_serial
		_seize = rng.randf() < _spell_sense()
	if not _seize:
		return false
	var flight := spell.windup + distance / spell.speed
	var guarded := _guarded_against(foe, me.global_position)
	var worth := false
	if spell.element == SpellData.Element.FIRE and fs.chill_stacks > 0 and fs.chill_time > flight and not guarded:
		worth = true  # Shatter
	elif fs.heal_time > flight and not guarded:
		worth = true  # any damage stops the heal
	elif fs.action == FighterState.Action.STAGGER and fs.action_duration - fs.action_time > flight + 0.05 \
			and distance > MELEE_RANGE + 1.5:
		worth = true
	elif spell.flinch > 0.0 and BotRead.release_in(fs) > flight + 0.02 and not guarded:
		worth = true  # jolt them out of the cast
	elif not fs.on_floor and not fs.leaping and distance > MELEE_RANGE and difficulty > 0.35:
		worth = true  # popped up: no guard in the air
	if not worth:
		return false
	_press |= InputCommand.PRIMARY
	_plan = _commit(_new_plan(spell, &"shot"))
	_next_cast = maxf(_next_cast, _time + 0.6)
	return true


func _new_plan(spell: SpellData, kind: StringName, score := 1.0) -> CastPlan:
	var plan := CastPlan.new()
	plan.spell = spell
	plan.kind = kind
	plan.score = score
	return plan


## Draws this cast's lead and aim error: skill sets how close to perfect.
func _commit(plan: CastPlan) -> CastPlan:
	plan.lead = clampf(lerpf(0.35, 1.0, difficulty) + rng.randf_range(-1.0, 1.0) * lerpf(0.3, 0.05, difficulty), 0.0, 1.15)
	plan.error = Vector2(rng.randf_range(-0.7, 0.7), rng.randf_range(-1.0, 1.0)) * _aim_error()
	return plan


# --- spells: where ------------------------------------------------------------------

## Points the cast in progress at its target until the spell leaves the hand
## (the aim is read on the release tick).
func _aim_cast(me: Fighter, foe: Fighter, cmd: InputCommand) -> void:
	var s := me.state
	if s.action != FighterState.Action.CAST or s.spell == null or s.spell_released:
		return
	if _plan == null or _plan.spell != s.spell:
		_plan = _commit(_new_plan(s.spell, &"strike" if s.spell is LightningStrikeSpell else &"shot"))
	var release_in := BotRead.release_in(s)
	match _plan.kind:
		&"strike":
			cmd.aim_target = _strike_point(me, foe, s.spell as LightningStrikeSpell, release_in) + Vector3(_plan.error.x, 0.0, _plan.error.y) * 0.6
		&"wall":
			var wall := s.spell as FlameWallSpell
			cmd.aim_target = _predict(me, foe, release_in + wall.tick_interval, _plan.lead * lerpf(0.5, 1.0, _steadiness()))
		&"barrier":
			var toward := _flat(foe.global_position - me.global_position)
			var wall := s.spell as FlameWallSpell
			cmd.aim_target = me.global_position + toward.normalized() * clampf(toward.length() * 0.55, wall.min_range + 0.3, wall.max_range)
		&"self_burst":
			var burst := me.global_position - _plan.away * 1.2
			cmd.aim_target = burst
			cmd.aim_yaw = CombatRules.dir_to_yaw(_flat(burst - me.global_position))
		&"poke":
			var velocity := _foe_velocity(foe)
			if _plan.foe_velocity == Vector3.INF:
				_plan.foe_velocity = velocity
			# they changed course while we wound up: they're juking it, so a
			# skilled thrower stops leading and lets the burst at their feet
			# catch whichever way they cut
			if not _plan.juke_seen and (velocity - _plan.foe_velocity).length() > 3.0:
				_plan.juke_seen = true
				_plan.lead *= 0.25 if difficulty > 0.5 and rng.randf() < _spell_sense() else 1.0
			cmd.aim_target = _shot_point(me, foe, s.spell as ProjectileSpell, FEET_FIRST)
		&"nova":
			pass
		_:
			if s.spell is ProjectileSpell:
				var shot := s.spell as ProjectileSpell
				cmd.aim_target = _shot_point(me, foe, shot, LOW_FIRST if shot.splash_radius > 0.0 else BODY_FIRST)


## Where to aim a projectile so it meets the opponent, led by its own speed
## (this cast's lead and error applied). `heights` are aim points above
## their feet in order of preference; the first one the shot can reach
## without clipping cover (a low wall) wins.
func _shot_point(me: Fighter, foe: Fighter, spell: ProjectileSpell, heights: Array[float]) -> Vector3:
	var origin := me.cast_origin()
	var velocity := Vector3(foe.velocity.x, 0.0, foe.velocity.z)  # shoves included: they carry the body too
	if BotRead.pinned_for(foe.state) > origin.distance_to(foe.chest_position()) / spell.speed:
		velocity = Vector3.ZERO
	var lead := _plan.lead if _plan else 1.0
	var point := Vector3.ZERO
	for height in heights:
		point = BotAim.lead_point(origin, foe.global_position + Vector3.UP * height, velocity, spell.speed, lead)
		if _plan:
			var side := _flat(point - origin).normalized().cross(Vector3.UP)
			# no vertical error at the feet: a shot into the floor short of them is wasted
			point += side * _plan.error.x + Vector3.UP * (_plan.error.y * 0.5 if height > 0.5 else 0.0)
		if _clear_line(me, origin, point.lerp(origin, 0.03)):
			break
	return point


# --- footwork ---------------------------------------------------------------------

func _strafe_dir(toward: Vector3) -> Vector3:
	if _time >= _strafe_flip_at:
		_strafe = -_strafe if rng.randf() < 0.6 else _strafe
		_strafe_flip_at = _time + rng.randf_range(0.8, 2.0)
	return toward.cross(Vector3.UP) * _strafe


## If we're pushing into something and not moving, slide along it for a
## while (long enough to round a low wall), towards the side with room.
func _unstick(me: Fighter, move: Vector3, dt: float) -> Vector3:
	if move.length() < 0.1:
		_slide_until = 0.0
		return move
	var heading := _flat(move).normalized()
	if _time < _slide_until:
		var slide := heading.cross(Vector3.UP) * _strafe
		if _wall_ahead(me, slide, 0.8):
			_strafe = -_strafe  # cornered that way: try the other
			slide = -slide
		return (slide + heading * 0.25).normalized() * move.length()
	var speed := Vector2(me.velocity.x, me.velocity.z).length()
	var free := me.state.action == FighterState.Action.IDLE
	var trying := move.length() > 0.5 and (free or me.state.action == FighterState.Action.CAST)
	_stuck_for = _stuck_for + dt if trying and speed < (0.6 if free else 0.25) else 0.0
	if _stuck_for > 0.3 and _wall_ahead(me, heading, 1.0):
		_stuck_for = 0.0
		var side := heading.cross(Vector3.UP)
		var left := _room(me, side, 6.0)
		var right := _room(me, -side, 6.0)
		_strafe = 1.0 if left >= right else -1.0
		_strafe_flip_at = _time + 2.0
		_slide_until = _time + 1.1
	return move


## How far one can walk along `heading` before hitting world geometry (up to `length`).
func _room(me: Fighter, heading: Vector3, length: float) -> float:
	var from := me.global_position + Vector3.UP * 0.6
	var hit := me.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + heading * length, 1))
	return length if hit.is_empty() else from.distance_to(hit.position)


## Notes enemy zones as they appear (each registers after a reaction delay,
## and whether the bot will think of dashing out of it is decided then) and
## lists the ones the bot has noticed. A zone is anything in the "zones"
## group with a team, contains() and exit_direction() (FlameWall,
## LightningStrike).
func _scan_zones(me: Fighter) -> void:
	_hazards.clear()
	for node in me.get_tree().get_nodes_in_group(&"zones"):
		var zone = node
		if zone.team == me.team:
			continue
		var id := node.get_instance_id()
		if not _zones.has(id):
			_zones[id] = [_time, _time + _zone_reaction(), rng.randf() < _strike_dash_odds()]
		if _time >= float(_zones[id][1]):
			_hazards.append(node)
	if _zones.size() > 24:
		for id: int in _zones.keys():
			if not is_instance_id_valid(id):
				_zones.erase(id)


## The short way out of any enemy zone we've noticed and are standing in
## (with no one to fight, nothing else competes with getting out).
func _leave_hazards(me: Fighter) -> Vector3:
	_scan_zones(me)
	for node in _hazards:
		var zone = node
		if zone.contains(me.global_position, Fighter.RADIUS + 0.5):
			return zone.exit_direction(me.global_position)
	return Vector3.ZERO


## A marked strike circle under us: the quickest clear way out before the
## bolt lands, sprinting or dashing if walking won't make it. Too late even
## for that, a skilled bot dashes as it lands so the dash's i-frames take it.
func _escape_strikes(me: Fighter, foe: Fighter) -> Vector3:
	for node in _hazards:
		var strike := node as LightningStrike
		if strike == null or not strike.contains(me.global_position, Fighter.RADIUS + 0.25):
			continue
		var s := me.state
		var tuning := me.tuning
		var centre := strike.global_position
		var edge := strike.spell.radius + Fighter.RADIUS + 0.3
		var time_left := strike.spell.delay - (_time - float(_zones[node.get_instance_id()][0]))
		var heading := _exit_heading(me, foe, centre, edge)
		var distance := BotAim.circle_exit_distance(me.global_position, heading, centre, edge)
		# a guard is no use against lightning from above, and a swing roots us
		_block_until = 0.0
		_parry_at = INF
		_dodge_at = INF
		_chain_left = 0
		var walk := BotRead.flee_speed(s, tuning)
		if distance / walk > time_left - 0.12 and s.can_spend():
			_hold |= InputCommand.SPRINT
			var sprint := walk * tuning.sprint_speed / tuning.walk_speed
			if distance / sprint > time_left - 0.1 and BotRead.has_dash(s) and bool(_zones[node.get_instance_id()][2]):
				var dash_time := tuning.dash_duration * clampf(distance / tuning.dash_distance, 0.0, 1.0)
				if distance <= tuning.dash_distance and dash_time <= time_left - 0.03:
					_press |= InputCommand.DASH
				elif time_left <= tuning.dash_iframes * 0.6 and difficulty >= 0.6:
					_press |= InputCommand.DASH
		return heading
	return Vector3.ZERO


## The quickest clear way out of a circle: straight out from its centre
## unless a wall or more ground fire is in the way.
func _exit_heading(me: Fighter, foe: Fighter, centre: Vector3, edge: float) -> Vector3:
	var radial := _flat(me.global_position - centre)
	if radial.length() < 0.15:
		# dead centre: out sideways from the opponent
		radial = _flat(foe.global_position - me.global_position).cross(Vector3.UP) * _strafe
	radial = radial.normalized() if radial.length() > 0.001 else Vector3.RIGHT
	var best := radial
	var best_distance := INF
	for angle in EXIT_ANGLES:
		var heading := radial.rotated(Vector3.UP, deg_to_rad(angle))
		var distance := BotAim.circle_exit_distance(me.global_position, heading, centre, edge)
		if distance >= best_distance:
			continue
		if _wall_ahead(me, heading, distance + 0.6) or _hazard_at(me.global_position + heading * (distance + 0.4), null):
			continue
		best = heading
		best_distance = distance
	return best


## Steps out of enemy ground fire the short way (once noticed).
func _escape_ground_fire(me: Fighter) -> Vector3:
	for node in _hazards:
		if node is LightningStrike:
			continue
		var zone = node
		if zone.contains(me.global_position, Fighter.RADIUS + 0.5):
			var out: Vector3 = zone.exit_direction(me.global_position)
			return -out if _wall_ahead(me, out, 1.5) else out
	return Vector3.ZERO


## Bends a move around noticed enemy zones instead of walking into them.
func _steer(me: Fighter, move: Vector3) -> Vector3:
	if _hazards.is_empty() or move.length() < 0.1:
		return move
	var heading := _flat(move).normalized()
	for angle in STEER_ANGLES:
		var turned := heading.rotated(Vector3.UP, deg_to_rad(angle) * _strafe)
		if not _hazard_ahead(me.global_position, turned):
			return turned * move.length()
	return Vector3.ZERO


func _hazard_ahead(from: Vector3, heading: Vector3) -> bool:
	for node in _hazards:
		var zone = node
		if zone.contains(from, Fighter.RADIUS):
			continue  # already in it: that's for the escape logic
		if zone.contains(from + heading * 0.8, Fighter.RADIUS + 0.2) or zone.contains(from + heading * 1.6, Fighter.RADIUS + 0.2):
			return true
	return false


func _hazard_at(point: Vector3, ignore: Node) -> bool:
	for node in _hazards:
		var zone = node
		if node != ignore and zone.contains(point, Fighter.RADIUS):
			return true
	return false


## Which way to be blown clear of the opponent: straight away from them,
## swung aside if a wall is close behind.
func _escape_heading(me: Fighter, foe: Fighter) -> Vector3:
	var away := _flat(me.global_position - foe.global_position).normalized()
	if away.length() < 0.01:
		away = -me.forward()
	for angle: float in [0.0, 45.0, -45.0, 90.0, -90.0]:
		var heading := away.rotated(Vector3.UP, deg_to_rad(angle))
		if not _wall_ahead(me, heading, 4.0):
			return heading
	return away


## `side` or its opposite, whichever has room for a dash.
func _open_side(me: Fighter, side: Vector3) -> Vector3:
	if _wall_ahead(me, side, me.tuning.dash_distance) and not _wall_ahead(me, -side, me.tuning.dash_distance):
		return -side
	return side


func _wall_ahead(me: Fighter, heading: Vector3, length: float) -> bool:
	var from := me.global_position + Vector3.UP * 0.6
	var ray := PhysicsRayQueryParameters3D.create(from, from + heading * length, 1)
	return not me.get_world_3d().direct_space_state.intersect_ray(ray).is_empty()


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
	var origin := me.cast_origin()
	return _clear_line(me, origin, foe.chest_position()) or _clear_line(me, origin, foe.global_position + Vector3.UP * 1.6)


func _clear_line(me: Fighter, from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	return me.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


static func _nearest_enemy(me: Fighter) -> Fighter:
	var best: Fighter = null
	for other in me.enemies():
		if best == null or me.global_position.distance_squared_to(other.global_position) \
				< me.global_position.distance_squared_to(best.global_position):
			best = other
	return best


## True if a projectile spell can reach `distance` (other spells always can).
static func _in_range(spell: SpellData, distance: float) -> bool:
	var shot := spell as ProjectileSpell
	return shot == null or distance < shot.max_range - 2.0
