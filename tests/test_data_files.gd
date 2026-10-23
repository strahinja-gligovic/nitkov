extends GutTest
## The data files load as the right types with sane numbers.


func test_tuning_loads() -> void:
	var tuning = load("res://data/combat_tuning.tres")
	assert_true(tuning is CombatTuning)


func test_longsword_has_a_three_hit_chain_and_a_heavy() -> void:
	var weapon = load("res://data/weapons/longsword.tres")
	assert_true(weapon is WeaponData)
	assert_eq(weapon.light_chain.size(), 3)
	for attack: AttackData in weapon.light_chain:
		assert_false(attack.breaks_block, "%s: lights don't break blocks" % attack.id)
		assert_false(attack.hyperarmor, "%s: lights have no hyperarmor" % attack.id)
	assert_true(weapon.heavy.breaks_block)
	assert_true(weapon.heavy.hyperarmor)
	assert_almost_eq(weapon.heavy.windup, 0.7, 0.001)


func test_light_chain_lands_about_twenty_damage_per_second() -> void:
	# Spec: medium TTK, ~4-6s of sustained hits. With chained lights, each hit
	# lands one (windup + active + chain_after) after the previous one, plus
	# the hit-stop freeze that every landed swing costs both fighters.
	var weapon: WeaponData = load("res://data/weapons/longsword.tres")
	var damage := 0.0
	var time := 0.0
	for attack in weapon.light_chain:
		damage += attack.damage
		time += attack.windup + attack.active + attack.chain_after + attack.hitstop
	var ttk := 100.0 / (damage / time)
	assert_between(ttk, 4.0, 6.0, "sustained light-chain TTK is %.1fs" % ttk)


func test_a_full_stamina_bar_covers_most_of_a_kill() -> void:
	# Running dry mid-kill is meant to happen, but only near the end of it.
	var weapon: WeaponData = load("res://data/weapons/longsword.tres")
	var tuning := CombatTuning.new()
	var swings := floori(tuning.max_stamina / weapon.light_chain[0].stamina_cost)
	var per_swing := 0.0
	for attack in weapon.light_chain:
		per_swing += attack.damage / weapon.light_chain.size()
	assert_gt(swings * per_swing, tuning.max_hp * 0.8)
