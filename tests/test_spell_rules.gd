extends GutTest
## CombatRules.resolve_spell and status effects: block chip, burn.

var tuning: CombatTuning
var defender: FighterState


func before_each() -> void:
	tuning = CombatTuning.new()
	defender = FighterState.new()
	defender.reset(tuning)


func _fire_hit(damage := 12.0, burn := true) -> SpellHit:
	var hit := SpellHit.new()
	hit.element = SpellData.Element.FIRE
	hit.damage = damage
	hit.applies_burn = burn
	hit.source = &"firebolt"
	return hit


func test_clean_spell_hit_damages_and_burns() -> void:
	var result := CombatRules.resolve_spell(defender, _fire_hit(), true, tuning)
	assert_eq(result.outcome, HitResult.Outcome.HIT)
	assert_eq(result.element, SpellData.Element.FIRE)
	assert_eq(defender.hp, tuning.max_hp - 12.0)
	assert_eq(defender.burn_time, tuning.burn_duration)


func test_spells_do_not_flinch() -> void:
	defender.start_action(FighterState.Action.CAST)
	CombatRules.resolve_spell(defender, _fire_hit(), true, tuning)
	assert_eq(defender.action, FighterState.Action.CAST)


func test_blocked_spell_chips_costs_stamina_and_applies_nothing() -> void:
	defender.blocking = true
	var result := CombatRules.resolve_spell(defender, _fire_hit(), true, tuning)
	assert_eq(result.outcome, HitResult.Outcome.BLOCKED)
	assert_almost_eq(defender.hp, tuning.max_hp - 12.0 * tuning.spell_block_chip, 0.001)
	assert_eq(defender.stamina, tuning.max_stamina - tuning.spell_block_stamina)
	assert_eq(defender.burn_time, 0.0, "blocked spells apply no statuses")


func test_spells_from_behind_ignore_block() -> void:
	defender.blocking = true
	var result := CombatRules.resolve_spell(defender, _fire_hit(), false, tuning)
	assert_eq(result.outcome, HitResult.Outcome.HIT)


func test_unblockable_ground_fire_ignores_block() -> void:
	defender.blocking = true
	var hit := _fire_hit(2.0, false)
	hit.blockable = false
	var result := CombatRules.resolve_spell(defender, hit, true, tuning)
	assert_eq(result.outcome, HitResult.Outcome.HIT)
	assert_eq(defender.hp, tuning.max_hp - 2.0)


func test_blocking_a_spell_on_empty_stamina_breaks_the_guard() -> void:
	defender.blocking = true
	defender.stamina = tuning.spell_block_stamina - 1.0
	var result := CombatRules.resolve_spell(defender, _fire_hit(), true, tuning)
	assert_eq(result.outcome, HitResult.Outcome.GUARD_BREAK)
	assert_eq(defender.exhausted, tuning.exhausted_duration)
	assert_eq(defender.action, FighterState.Action.STAGGER)


func test_invulnerable_ignores_spells() -> void:
	defender.invulnerable = 0.1
	assert_eq(CombatRules.resolve_spell(defender, _fire_hit(), true, tuning).outcome, HitResult.Outcome.IGNORED)


func test_burn_deals_its_total_then_expires() -> void:
	CombatRules.apply_burn(defender, tuning)
	var total := 0.0
	for i in int((tuning.burn_duration + 1.0) * 60.0):
		total += CombatRules.tick_statuses(defender, 1.0 / 60.0, tuning)
	assert_almost_eq(total, tuning.burn_dps * tuning.burn_duration, tuning.burn_dps * tuning.burn_tick)
	assert_eq(defender.burn_time, 0.0)


func test_reapplying_burn_refreshes_instead_of_stacking() -> void:
	CombatRules.apply_burn(defender, tuning)
	CombatRules.tick_statuses(defender, 1.0, tuning)
	CombatRules.apply_burn(defender, tuning)
	assert_eq(defender.burn_time, tuning.burn_duration)


func test_slows_take_the_strongest_not_the_sum() -> void:
	defender.slow_amount = 0.4
	defender.slow_time = 1.0
	defender.chill_stacks = tuning.chill_max_stacks
	defender.chill_time = 1.0
	assert_almost_eq(CombatRules.move_speed_mult(defender, tuning), 0.6, 0.001)
	defender.slow_time = 0.0
	assert_almost_eq(CombatRules.move_speed_mult(defender, tuning), 1.0 - tuning.chill_slow, 0.001)
