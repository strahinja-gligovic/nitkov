class_name BotRead
extends RefCounted
## Reads a fighter the way a player reads an opponent: how long they're stuck
## in what they're doing, how fast they can get away, and whether a Lightning
## Strike marked on them would land. Pure functions over FighterState, so
## they're unit tested headless.


## Seconds before the fighter can move where they like again: a stagger,
## flinch or dash runs out, or a swing reaches the point where it can be
## dodge-cancelled. Hit-stop adds to it. 0 when free; casters still walk.
static func pinned_for(s: FighterState) -> float:
	var left := 0.0
	match s.action:
		FighterState.Action.STAGGER, FighterState.Action.FLINCH, FighterState.Action.DASH:
			left = s.action_duration - s.action_time
		FighterState.Action.ATTACK:
			if s.attack:
				var cancel := s.attack.windup + s.attack.active + s.attack.dodge_cancel_after
				left = minf(cancel, s.attack.duration()) - s.action_time
		FighterState.Action.DEAD:
			return INF
	return maxf(left, 0.0) + s.hitstop


## Seconds until a casting fighter's spell leaves the hand (0 if they aren't
## winding one up).
static func release_in(s: FighterState) -> float:
	if s.action != FighterState.Action.CAST or s.spell == null or s.spell_released:
		return 0.0
	return maxf(s.spell.windup - s.action_time, 0.0)


## Seconds until the fighter's swing reaches its active frames: 0 while it's
## cutting, INF if they aren't winding one up.
static func swing_lands_in(s: FighterState) -> float:
	if s.action != FighterState.Action.ATTACK or s.attack == null:
		return INF
	if s.action_time >= s.attack.windup + s.attack.active:
		return INF
	return maxf(s.attack.windup - s.action_time, 0.0)


## Walking speed they can get away at (slows apply; casting slows them too).
static func flee_speed(s: FighterState, tuning: CombatTuning) -> float:
	var speed := tuning.walk_speed * CombatRules.move_speed_mult(s, tuning)
	if s.action == FighterState.Action.CAST:
		speed *= tuning.cast_move_mult
	return speed


## Whether they have a dash to spend (now, or once their current action lets them).
static func has_dash(s: FighterState) -> bool:
	return s.on_floor and s.stamina > 0.0 and s.exhausted <= 0.0


## Seconds a fighter needs to get out of a strike circle marked on them
## `mark_in` seconds from now, if they notice it `react` seconds after it
## appears and have to cover `distance` to its edge: walking, or (with
## `dash`) dashing once they're free to.
static func escape_time(s: FighterState, tuning: CombatTuning, mark_in: float, distance: float, react: float,
		dash := true) -> float:
	var pinned := maxf(pinned_for(s) - mark_in, 0.0)
	var start := maxf(react, pinned)
	var walk := start + distance / maxf(flee_speed(s, tuning), 0.5)
	if not dash or not has_dash(s):
		return walk
	# a caster can't dash until their own spell is out
	var dash_from := maxf(start, release_in(s) - mark_in)
	return minf(walk, dash_from + tuning.dash_duration * clampf(distance / tuning.dash_distance, 0.0, 1.0))


## True while the fighter can't raise a guard: busy with an action, airborne
## or exhausted. Spells that reach them now can't be blocked.
static func guard_down(s: FighterState) -> bool:
	return s.action != FighterState.Action.IDLE or not s.on_floor or s.exhausted > 0.0
