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


# --- spells -----------------------------------------------------------------------

const ELEMENTS: Array[SpellData.Element] = [SpellData.Element.FIRE, SpellData.Element.FROST,
		SpellData.Element.LIGHTNING, SpellData.Element.WIND]


func test_eight_spells_load_with_unique_ids() -> void:
	assert_eq(GameData.SPELL_PATHS.size(), 8)
	var ids := {}
	for path in GameData.SPELL_PATHS:
		var spell := load(path) as SpellData
		assert_not_null(spell, "%s is a spell" % path)
		if spell == null:
			continue
		assert_ne(spell.id, &"", "%s has an id" % path)
		assert_false(ids.has(spell.id), "%s: id %s is unique" % [path, spell.id])
		ids[spell.id] = true
		assert_ne(spell.display_name, "", "%s has a name" % spell.id)
		assert_has(ELEMENTS, spell.element, "%s has an element" % spell.id)
		assert_gt(spell.windup, 0.0, "%s winds up" % spell.id)
	assert_eq(GameData.spells.size(), 8, "and each is registered under its id")


func test_each_slot_offers_four_spells() -> void:
	assert_eq(GameData.spells_for(SpellData.Slot.PRIMARY).size(), 4)
	assert_eq(GameData.spells_for(SpellData.Slot.SIGNATURE).size(), 4)


func test_every_element_has_a_primary_and_a_signature() -> void:
	for element in ELEMENTS:
		for slot: SpellData.Slot in [SpellData.Slot.PRIMARY, SpellData.Slot.SIGNATURE]:
			var matching := GameData.spells_for(slot).filter(func(spell: SpellData) -> bool: return spell.element == element)
			assert_eq(matching.size(), 1, "%s has one %s" % [SpellData.Element.keys()[element], SpellData.Slot.keys()[slot]])


func test_every_spell_plays_a_move_in_the_move_set() -> void:
	for spell: SpellData in GameData.spells.values():
		assert_true(GameData.moves.has_move(spell.animation), "%s plays %s" % [spell.id, spell.animation])


func test_each_element_has_its_own_colour() -> void:
	var seen := {}
	for element in ELEMENTS:
		var colour := SpellData.element_color(element)
		assert_false(seen.has(colour), "%s's colour is its own" % SpellData.Element.keys()[element])
		seen[colour] = true
		assert_ne(colour, SpellData.element_color(SpellData.Element.NONE))


func test_ice_spike_is_one_spike() -> void:
	var ice := GameData.spells[&"ice_spike"] as ProjectileSpell
	assert_not_null(ice)
	assert_eq(ice.count, 1, "three spikes were overpowered")
	assert_eq(ice.chill_stacks, 1)
	assert_false(GameData.spells.has(&"shard_volley"), "the old volley is gone")


func test_lightning_bolt_is_fast_and_jolts_and_the_strike_is_the_heavy_hitter() -> void:
	var bolt := GameData.spells[&"lightning_bolt"] as ProjectileSpell
	var strike := GameData.spells[&"lightning_strike"] as LightningStrikeSpell
	assert_not_null(bolt)
	assert_not_null(strike)
	if bolt == null or strike == null:
		return
	assert_gt(bolt.flinch, 0.0, "the bolt interrupts")
	for other: SpellData in GameData.spells_for(SpellData.Slot.PRIMARY):
		if other != bolt:
			assert_gt(bolt.speed, (other as ProjectileSpell).speed, "the bolt outflies %s" % other.id)
	assert_eq(strike.slot, SpellData.Slot.SIGNATURE)
	assert_gt(strike.delay, 0.0, "the strike lands after a delay")
	assert_gt(strike.damage, bolt.damage, "and hits harder")
	assert_gt(strike.stagger, 0.0, "and stuns")
	assert_gt(strike.radius, 0.0)
	assert_lt(strike.min_range, strike.max_range)


func test_wind_slash_is_wide_and_the_spear_bursts() -> void:
	var slash := GameData.spells[&"wind_slash"] as ProjectileSpell
	var spear := GameData.spells[&"wind_spear"] as ProjectileSpell
	assert_not_null(slash)
	assert_not_null(spear)
	if slash == null or spear == null:
		return
	assert_gt(slash.push, 0.0, "the slash shoves")
	assert_eq(slash.burst_radius, 0.0, "but doesn't burst")
	for other: SpellData in GameData.spells_for(SpellData.Slot.PRIMARY):
		if other != slash:
			assert_gt(slash.radius, (other as ProjectileSpell).radius * 2.0, "the crescent is far wider than %s" % other.id)
	assert_eq(spear.slot, SpellData.Slot.SIGNATURE)
	assert_eq(spear.count, 1, "one big spear")
	assert_gt(spear.burst_radius, 0.0, "it bursts")
	assert_gt(spear.burst_push, 0.0, "pushing everything")
	assert_gt(spear.burst_launch, 0.0)
	assert_gt(spear.damage, slash.damage, "and hits harder than the slash")
	assert_true(spear.burst_deflects, "and blows enemy spells off course")
