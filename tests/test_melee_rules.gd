extends GutTest
## CombatRules.resolve_melee: clean hits, flinch, hyperarmor, block, parry and
## guard breaks.

var tuning: CombatTuning
var attacker: FighterState
var defender: FighterState
var light: AttackData
var heavy: AttackData


func before_each() -> void:
	tuning = CombatTuning.new()
	attacker = FighterState.new()
	attacker.reset(tuning)
	defender = FighterState.new()
	defender.reset(tuning)
	var weapon: WeaponData = load("res://data/weapons/longsword.tres")
	light = weapon.light_chain[0]
	heavy = weapon.heavy


func _swing(attack: AttackData) -> void:
	attacker.start_action(FighterState.Action.ATTACK)
	attacker.attack = attack


func test_clean_light_hit_damages_and_flinches() -> void:
	_swing(light)
	var result := CombatRules.resolve_melee(attacker, defender, light, true, tuning)
	assert_eq(result.outcome, HitResult.Outcome.HIT)
	assert_eq(defender.hp, tuning.max_hp - light.damage)
	assert_eq(defender.action, FighterState.Action.FLINCH)
	assert_eq(defender.action_duration, light.flinch)


func test_light_does_not_flinch_a_heavy_windup() -> void:
	defender.start_action(FighterState.Action.ATTACK)
	defender.attack = heavy
	defender.action_time = heavy.windup * 0.5
	_swing(light)
	var result := CombatRules.resolve_melee(attacker, defender, light, true, tuning)
	assert_eq(result.outcome, HitResult.Outcome.HIT)
	assert_eq(defender.action, FighterState.Action.ATTACK, "hyperarmor keeps the heavy going")
	assert_eq(defender.hp, tuning.max_hp - light.damage, "hyperarmor still takes damage")


func test_light_interrupts_a_light_windup() -> void:
	defender.start_action(FighterState.Action.ATTACK)
	defender.attack = light
	defender.action_time = 0.05
	CombatRules.resolve_melee(attacker, defender, light, true, tuning)
	assert_eq(defender.action, FighterState.Action.FLINCH)


func test_dead_and_invulnerable_targets_are_ignored() -> void:
	defender.invulnerable = 0.1
	assert_eq(CombatRules.resolve_melee(attacker, defender, light, true, tuning).outcome, HitResult.Outcome.IGNORED)
	defender.invulnerable = 0.0
	defender.take_damage(1000.0)
	assert_eq(CombatRules.resolve_melee(attacker, defender, light, true, tuning).outcome, HitResult.Outcome.IGNORED)


func test_killing_blow_reports_the_kill() -> void:
	defender.hp = light.damage
	var result := CombatRules.resolve_melee(attacker, defender, light, true, tuning)
	assert_true(result.killed)
	assert_true(defender.is_dead())


func test_block_from_the_front_costs_stamina_and_no_health() -> void:
	defender.blocking = true
	var result := CombatRules.resolve_melee(attacker, defender, light, true, tuning)
	assert_eq(result.outcome, HitResult.Outcome.BLOCKED)
	assert_eq(defender.hp, tuning.max_hp)
	assert_eq(defender.stamina, tuning.max_stamina - light.block_stamina_cost)
	assert_eq(defender.action, FighterState.Action.IDLE, "a blocked light doesn't flinch")


func test_block_does_not_cover_the_back() -> void:
	defender.blocking = true
	var result := CombatRules.resolve_melee(attacker, defender, light, false, tuning)
	assert_eq(result.outcome, HitResult.Outcome.HIT)
	assert_eq(defender.hp, tuning.max_hp - light.damage)


func test_block_without_enough_stamina_breaks_the_guard_and_exhausts() -> void:
	defender.blocking = true
	defender.stamina = light.block_stamina_cost - 1.0
	var result := CombatRules.resolve_melee(attacker, defender, light, true, tuning)
	assert_eq(result.outcome, HitResult.Outcome.GUARD_BREAK)
	assert_eq(defender.stamina, 0.0)
	assert_eq(defender.exhausted, tuning.exhausted_duration)
	assert_eq(defender.action, FighterState.Action.STAGGER)
	assert_eq(defender.stagger_kind, &"guard_break")
	assert_eq(defender.action_duration, tuning.guard_break_stagger)


func test_heavy_always_breaks_block() -> void:
	defender.blocking = true
	_swing(heavy)
	var result := CombatRules.resolve_melee(attacker, defender, heavy, true, tuning)
	assert_eq(result.outcome, HitResult.Outcome.GUARD_BREAK)
	assert_eq(defender.action, FighterState.Action.STAGGER)
	assert_almost_eq(defender.hp, tuning.max_hp - heavy.damage * tuning.heavy_guard_break_damage, 0.001)
	assert_eq(defender.exhausted, 0.0, "a heavy break staggers but doesn't exhaust")
	assert_eq(defender.stamina, tuning.max_stamina, "and costs no stamina")


func test_parry_staggers_the_attacker_and_spares_the_defender() -> void:
	defender.parry_window = 0.1
	_swing(light)
	var result := CombatRules.resolve_melee(attacker, defender, light, true, tuning)
	assert_eq(result.outcome, HitResult.Outcome.PARRIED)
	assert_eq(defender.hp, tuning.max_hp)
	assert_eq(attacker.action, FighterState.Action.STAGGER)
	assert_eq(attacker.stagger_kind, &"parried")
	assert_eq(attacker.action_duration, light.parry_stagger)


func test_parried_heavy_staggers_longer() -> void:
	defender.parry_window = 0.1
	defender.blocking = true
	_swing(heavy)
	var result := CombatRules.resolve_melee(attacker, defender, heavy, true, tuning)
	assert_eq(result.outcome, HitResult.Outcome.PARRIED, "parry beats a heavy that would break the block")
	assert_eq(attacker.action_duration, heavy.parry_stagger)
	assert_gt(heavy.parry_stagger, light.parry_stagger)


func test_parry_fails_from_behind() -> void:
	defender.parry_window = 0.1
	var result := CombatRules.resolve_melee(attacker, defender, light, false, tuning)
	assert_eq(result.outcome, HitResult.Outcome.HIT)


func test_front_arc_geometry() -> void:
	var at := Vector3.ZERO
	# facing yaw 0 looks down -Z
	assert_true(CombatRules.is_in_front(0.0, at, Vector3(0, 0, -3), 180.0))
	assert_true(CombatRules.is_in_front(0.0, at, Vector3(2.9, 0, -0.1), 180.0), "just inside the side edge")
	assert_false(CombatRules.is_in_front(0.0, at, Vector3(0, 0, 3), 180.0))
	assert_false(CombatRules.is_in_front(0.0, at, Vector3(3, 0, 0.2), 180.0), "just behind the side edge")
