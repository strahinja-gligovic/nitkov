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


## Paying for a block you can't afford: the guard shatters and you're exhausted.
static func break_guard_from_empty_stamina(defender: FighterState, tuning: CombatTuning) -> void:
	defender.stamina = 0.0
	defender.exhausted = tuning.exhausted_duration
	defender.apply_stagger(tuning.guard_break_stagger, &"guard_break")
