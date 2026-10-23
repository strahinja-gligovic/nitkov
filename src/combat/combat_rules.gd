class_name CombatRules
extends RefCounted
## The combat rules as pure functions over FighterState. No nodes and no
## physics, so everything here is unit tested headless (see tests/).


## Facing direction for a yaw angle. Godot's forward is -Z.
static func yaw_to_dir(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


static func dir_to_yaw(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)


## True when `source` lies within the `arc_deg` cone centred on the facing direction.
static func is_in_front(facing_yaw: float, at: Vector3, source: Vector3, arc_deg: float) -> bool:
	var to_source := Vector3(source.x - at.x, 0.0, source.z - at.z)
	if to_source.length_squared() < 0.0001:
		return true
	return yaw_to_dir(facing_yaw).dot(to_source.normalized()) >= cos(deg_to_rad(arc_deg * 0.5)) - 0.0001


## Where along the segment p0->p1 (0..1) it comes within `radius` of the
## capsule axis a->b, or -1 if it never does. Uses the closest approach,
## which is accurate enough for per-tick projectile sweeps.
static func segment_hits_capsule(p0: Vector3, p1: Vector3, a: Vector3, b: Vector3, radius: float) -> float:
	var closest := Geometry3D.get_closest_points_between_segments(p0, p1, a, b)
	if closest[0].distance_to(closest[1]) > radius:
		return -1.0
	var length := p0.distance_to(p1)
	return 0.0 if length < 0.0001 else p0.distance_to(closest[0]) / length


## Resolves a melee swing landing on `defender`. `from_front` says whether the
## attacker is inside the defender's block arc. Mutates both states.
static func resolve_melee(attacker: FighterState, defender: FighterState, attack: AttackData,
		from_front: bool, tuning: CombatTuning) -> HitResult:
	var result := HitResult.new()
	result.source = attack.id
	if defender.is_dead() or defender.invulnerable > 0.0:
		result.outcome = HitResult.Outcome.IGNORED
		return result

	if from_front and defender.parry_window > 0.0:
		result.outcome = HitResult.Outcome.PARRIED
		defender.parry_window = 0.0
		attacker.apply_stagger(attack.parry_stagger, &"parried")
		return result

	if from_front and defender.blocking:
		if attack.breaks_block:
			result.outcome = HitResult.Outcome.GUARD_BREAK
			result.damage = attack.damage * tuning.heavy_guard_break_damage
			defender.apply_stagger(tuning.guard_break_stagger, &"guard_break")
		elif defender.stamina < attack.block_stamina_cost:
			result.outcome = HitResult.Outcome.GUARD_BREAK
			result.damage = attack.damage * tuning.melee_block_chip
			break_guard_from_empty_stamina(defender, tuning)
		else:
			result.outcome = HitResult.Outcome.BLOCKED
			result.damage = attack.damage * tuning.melee_block_chip
			defender.spend_stamina(attack.block_stamina_cost, tuning)
		result.killed = defender.take_damage(result.damage)
		return result

	result.outcome = HitResult.Outcome.HIT
	result.damage = attack.damage
	if not defender.has_hyperarmor():
		defender.apply_flinch(attack.flinch)
	result.killed = defender.take_damage(result.damage)
	return result


## Resolves one spell effect reaching `defender`. Blocked spells chip, cost
## stamina, and apply no statuses or reactions. Spells never flinch.
static func resolve_spell(defender: FighterState, hit: SpellHit, from_front: bool,
		tuning: CombatTuning) -> HitResult:
	var result := HitResult.new()
	result.source = hit.source
	result.element = hit.element
	result.periodic = hit.periodic
	if defender.is_dead() or defender.invulnerable > 0.0:
		result.outcome = HitResult.Outcome.IGNORED
		return result

	if hit.blockable and from_front and defender.blocking:
		if defender.stamina < tuning.spell_block_stamina:
			result.outcome = HitResult.Outcome.GUARD_BREAK
			break_guard_from_empty_stamina(defender, tuning)
		else:
			result.outcome = HitResult.Outcome.BLOCKED
			defender.spend_stamina(tuning.spell_block_stamina, tuning)
		result.damage = hit.damage * tuning.spell_block_chip
		result.killed = defender.take_damage(result.damage)
		return result

	result.outcome = HitResult.Outcome.HIT
	result.damage = hit.damage
	if hit.applies_burn:
		apply_burn(defender, tuning)
	if hit.slow_duration > 0.0:
		apply_slow(defender, hit.slow_amount, hit.slow_duration)
	result.killed = defender.take_damage(result.damage)
	return result


## Burn refreshes rather than stacks.
static func apply_burn(state: FighterState, tuning: CombatTuning) -> void:
	if state.burn_time <= 0.0:
		state.burn_tick = 0.0
	state.burn_time = tuning.burn_duration


static func apply_slow(state: FighterState, amount: float, duration: float) -> void:
	if state.slow_time <= 0.0 or amount >= state.slow_amount:
		state.slow_amount = amount
	state.slow_time = maxf(state.slow_time, duration)


## Advances statuses and returns the burn damage that came due this tick
## (the caller applies it, so deaths are reported in one place).
static func tick_statuses(state: FighterState, delta: float, tuning: CombatTuning) -> float:
	var burn := 0.0
	if state.burn_time > 0.0:
		state.burn_tick += delta
		while state.burn_tick >= tuning.burn_tick:
			state.burn_tick -= tuning.burn_tick
			burn += tuning.burn_dps * tuning.burn_tick
		state.burn_time = maxf(state.burn_time - delta, 0.0)
	if state.chill_time > 0.0:
		state.chill_time = maxf(state.chill_time - delta, 0.0)
		if state.chill_time <= 0.0:
			state.chill_stacks = 0
	if state.slow_time > 0.0:
		state.slow_time = maxf(state.slow_time - delta, 0.0)
		if state.slow_time <= 0.0:
			state.slow_amount = 0.0
	if state.heal_time > 0.0 and not state.is_dead():
		var step := minf(delta, state.heal_time)
		state.hp = minf(state.hp + state.heal_rate * step, state.max_hp)
		state.heal_time -= step
	return burn


## Movement multiplier from slows. Slows don't add up: the strongest wins.
static func move_speed_mult(state: FighterState, tuning: CombatTuning) -> float:
	var slow := 0.0
	if state.slow_time > 0.0:
		slow = state.slow_amount
	if state.chill_stacks >= tuning.chill_max_stacks:
		slow = maxf(slow, tuning.chill_slow)
	return 1.0 - slow


## Paying for a block you can't afford: the guard shatters and you're exhausted.
static func break_guard_from_empty_stamina(defender: FighterState, tuning: CombatTuning) -> void:
	defender.stamina = 0.0
	defender.exhausted = tuning.exhausted_duration
	defender.apply_stagger(tuning.guard_break_stagger, &"guard_break")
