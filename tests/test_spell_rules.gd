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


func _frost_hit(stacks := 1) -> SpellHit:
	var hit := SpellHit.new()
	hit.element = SpellData.Element.FROST
	hit.damage = 5.0
	hit.chill_stacks = stacks
	hit.source = &"shard_volley"
	return hit


func test_chill_stacks_cap_and_refresh() -> void:
	CombatRules.resolve_spell(defender, _frost_hit(), true, tuning)
	assert_eq(defender.chill_stacks, 1)
	assert_eq(defender.chill_time, tuning.chill_duration)
	for i in 5:
		CombatRules.resolve_spell(defender, _frost_hit(), true, tuning)
	assert_eq(defender.chill_stacks, tuning.chill_max_stacks)
	assert_almost_eq(CombatRules.move_speed_mult(defender, tuning), 1.0 - tuning.chill_slow, 0.001, "slowed at max stacks")


func test_chill_expires() -> void:
	CombatRules.resolve_spell(defender, _frost_hit(2), true, tuning)
	CombatRules.tick_statuses(defender, tuning.chill_duration + 0.01, tuning)
	assert_eq(defender.chill_stacks, 0)


func test_fire_on_a_chilled_target_shatters() -> void:
	CombatRules.resolve_spell(defender, _frost_hit(1), true, tuning)
	var hp_before := defender.hp
	var result := CombatRules.resolve_spell(defender, _fire_hit(12.0, false), true, tuning)
	assert_eq(result.reaction, &"shatter")
	assert_almost_eq(result.damage, 12.0 + tuning.shatter_damage, 0.001)
	assert_almost_eq(defender.hp, hp_before - 12.0 - tuning.shatter_damage, 0.001)
	assert_eq(defender.chill_stacks, 0, "Shatter consumes the Chill")
	assert_eq(defender.action, FighterState.Action.STAGGER)
	assert_eq(defender.stagger_kind, &"shatter")
	assert_eq(defender.action_duration, tuning.shatter_stagger)


func test_fire_on_an_unchilled_target_does_not_shatter() -> void:
	var result := CombatRules.resolve_spell(defender, _fire_hit(), true, tuning)
	assert_eq(result.reaction, &"")


func test_blocked_fire_does_not_shatter() -> void:
	CombatRules.resolve_spell(defender, _frost_hit(2), true, tuning)
	defender.blocking = true
	var result := CombatRules.resolve_spell(defender, _fire_hit(), true, tuning)
	assert_eq(result.outcome, HitResult.Outcome.BLOCKED)
	assert_eq(result.reaction, &"")
	assert_eq(defender.chill_stacks, 2)


func test_burn_ticks_do_not_shatter() -> void:
	CombatRules.apply_burn(defender, tuning)
	CombatRules.resolve_spell(defender, _frost_hit(2), true, tuning)
	CombatRules.tick_statuses(defender, 1.0, tuning)
	assert_eq(defender.chill_stacks, 2)
	assert_ne(defender.action, FighterState.Action.STAGGER)


func test_non_reacting_fire_does_not_shatter() -> void:
	CombatRules.resolve_spell(defender, _frost_hit(1), true, tuning)
	var hit := _fire_hit()
	hit.triggers_reactions = false
	assert_eq(CombatRules.resolve_spell(defender, hit, true, tuning).reaction, &"")


func test_nova_style_slow() -> void:
	var hit := _frost_hit(3)
	hit.slow_amount = 0.4
	hit.slow_duration = 2.0
	CombatRules.resolve_spell(defender, hit, true, tuning)
	assert_almost_eq(CombatRules.move_speed_mult(defender, tuning), 0.6, 0.001, "the stronger nova slow wins over max Chill")
	CombatRules.tick_statuses(defender, 2.01, tuning)
	assert_almost_eq(CombatRules.move_speed_mult(defender, tuning), 1.0 - tuning.chill_slow, 0.001)


func test_orb_heal_restores_half_over_its_duration() -> void:
	defender.hp = 20.0
	CombatRules.start_heal(defender, tuning)
	for i in int(tuning.orb_heal_duration * 60.0) + 5:
		CombatRules.tick_statuses(defender, 1.0 / 60.0, tuning)
	assert_almost_eq(defender.hp, 20.0 + tuning.max_hp * tuning.orb_heal_fraction, 0.5)


func test_damage_interrupts_the_orb_heal() -> void:
	defender.hp = 20.0
	CombatRules.start_heal(defender, tuning)
	CombatRules.tick_statuses(defender, tuning.orb_heal_duration * 0.5, tuning)
	defender.take_damage(1.0)
	var after_hit := defender.hp
	CombatRules.tick_statuses(defender, tuning.orb_heal_duration, tuning)
	assert_eq(defender.hp, after_hit, "no more healing after the hit")


func test_heal_never_overfills() -> void:
	defender.hp = defender.max_hp - 5.0
	CombatRules.start_heal(defender, tuning)
	CombatRules.tick_statuses(defender, tuning.orb_heal_duration + 0.1, tuning)
	assert_eq(defender.hp, defender.max_hp)


func test_slows_take_the_strongest_not_the_sum() -> void:
	defender.slow_amount = 0.4
	defender.slow_time = 1.0
	defender.chill_stacks = tuning.chill_max_stacks
	defender.chill_time = 1.0
	assert_almost_eq(CombatRules.move_speed_mult(defender, tuning), 0.6, 0.001)
	defender.slow_time = 0.0
	assert_almost_eq(CombatRules.move_speed_mult(defender, tuning), 1.0 - tuning.chill_slow, 0.001)
