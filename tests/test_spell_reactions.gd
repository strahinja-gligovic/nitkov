extends GutTest
## CombatRules.resolve_spell reactions added with Lightning and Wind:
## flinch, stun (stagger), shove (push) and pop (launch), and apply_push.

var tuning: CombatTuning
var defender: FighterState


func before_each() -> void:
	tuning = CombatTuning.new()
	defender = FighterState.new()
	defender.reset(tuning)


func _bolt(flinch := 0.25) -> SpellHit:
	var hit := SpellHit.new()
	hit.element = SpellData.Element.LIGHTNING
	hit.damage = 9.0
	hit.flinch = flinch
	hit.source = &"lightning_bolt"
	return hit


func _gust(push := Vector3(0, 0, -5), launch := 0.0) -> SpellHit:
	var hit := SpellHit.new()
	hit.element = SpellData.Element.WIND
	hit.damage = 8.0
	hit.push = push
	hit.launch = launch
	hit.source = &"wind_slash"
	return hit


func test_a_flinching_spell_interrupts_a_cast() -> void:
	defender.start_action(FighterState.Action.CAST)
	CombatRules.resolve_spell(defender, _bolt(), true, tuning)
	assert_eq(defender.action, FighterState.Action.FLINCH)
	assert_almost_eq(defender.action_duration, 0.25, 0.001)


func test_a_heavy_wind_up_shrugs_off_a_spell_flinch() -> void:
	var weapon: WeaponData = load("res://data/weapons/longsword.tres")
	defender.start_action(FighterState.Action.ATTACK)
	defender.attack = weapon.heavy
	CombatRules.resolve_spell(defender, _bolt(), true, tuning)
	assert_eq(defender.action, FighterState.Action.ATTACK)


func test_a_spell_flinch_never_shortens_a_running_stun() -> void:
	defender.apply_stagger(1.0, &"shock")
	CombatRules.resolve_spell(defender, _bolt(), true, tuning)
	assert_eq(defender.action, FighterState.Action.STAGGER)
	assert_eq(defender.stagger_kind, &"shock")


func test_a_blocked_spell_neither_flinches_nor_pops_and_takes_half_the_shove() -> void:
	defender.blocking = true
	var hit := _gust(Vector3(0, 0, -6), 5.0)
	hit.flinch = 0.25
	CombatRules.resolve_spell(defender, hit, true, tuning)
	assert_eq(defender.action, FighterState.Action.IDLE)
	assert_almost_eq(defender.knockback.length(), 3.0, 0.001)
	assert_eq(defender.launch, 0.0)


func test_a_stun_goes_through_hyperarmor_and_names_its_cause() -> void:
	var weapon: WeaponData = load("res://data/weapons/longsword.tres")
	defender.start_action(FighterState.Action.ATTACK)
	defender.attack = weapon.heavy
	var hit := SpellHit.new()
	hit.element = SpellData.Element.LIGHTNING
	hit.damage = 24.0
	hit.blockable = false
	hit.stagger = 1.0
	hit.stagger_kind = &"shock"
	hit.launch = 2.5
	CombatRules.resolve_spell(defender, hit, false, tuning)
	assert_eq(defender.action, FighterState.Action.STAGGER)
	assert_eq(defender.stagger_kind, &"shock")
	assert_eq(defender.launch, 2.5)


func test_a_hit_shoves_flat_and_pops_up() -> void:
	CombatRules.resolve_spell(defender, _gust(Vector3(3, 2, -4), 4.0), true, tuning)
	assert_eq(defender.knockback, Vector3(3, 0, -4), "the shove is horizontal")
	assert_eq(defender.launch, 4.0)


func test_shoves_do_not_stack_the_stronger_one_wins() -> void:
	CombatRules.apply_push(defender, Vector3(0, 0, -12), 5.0)
	CombatRules.apply_push(defender, Vector3(5, 0, 0), 2.0)
	assert_eq(defender.knockback, Vector3(0, 0, -12))
	assert_eq(defender.launch, 5.0)
	CombatRules.apply_push(defender, Vector3(13, 0, 0), 0.0)
	assert_eq(defender.knockback, Vector3(13, 0, 0))


func test_dodging_fighters_ignore_shoves_and_stuns() -> void:
	defender.invulnerable = 0.1
	var result := CombatRules.resolve_spell(defender, _gust(Vector3(0, 0, -12), 5.0), true, tuning)
	assert_eq(result.outcome, HitResult.Outcome.IGNORED)
	assert_eq(defender.knockback, Vector3.ZERO)
	assert_eq(defender.launch, 0.0)
