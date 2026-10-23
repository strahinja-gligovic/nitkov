extends "res://tests/spell_world_test.gd"
## Every spell cast end to end through a real fighter, the way a player
## casts it: the button press, the wind-up, the release, the flight or the
## wait, the landing. Engine and script errors fail a GUT test, so this also
## runs every spell's charge, release, flight, impact and aftermath visuals
## and sounds headless, and checks that everything cleans up after itself.


## A caster at the origin with `id` in its slot, and a foe standing where
## the spell reaches it, facing the caster.
func _duel(id: StringName) -> Array[Fighter]:
	var data := spell(id)
	var caster := add_fighter(Vector3.ZERO, 0)
	if data.slot == SpellData.Slot.PRIMARY:
		caster.primary = data
	else:
		caster.signature = data
	var distance := 3.0 if data is NovaSpell else 8.0
	var foe := add_fighter(Vector3(0.0, 0.0, -distance), 1, PI)
	return [caster, foe]


static func _button(data: SpellData) -> int:
	return InputCommand.PRIMARY if data.slot == SpellData.Slot.PRIMARY else InputCommand.SIGNATURE


func test_every_spell_casts_end_to_end(id: StringName = use_parameters(GameData.spells.keys())) -> void:
	var data := spell(id)
	var pair := _duel(id)
	var caster := pair[0]
	var foe := pair[1]
	var cmd := command(caster, 0, _button(data), foe.chest_position())
	var in_play: Array[Node] = []
	var stamina_after_press := -1.0
	for tick in ticks(6.0):
		var before := spell_nodes()
		drive(caster, cmd)
		if tick == 0:
			stamina_after_press = caster.state.stamina
			assert_eq(caster.state.action, FighterState.Action.CAST, "%s: the press starts a cast" % id)
		in_play.append_array(adopt_new(before))
		step(in_play)
		if tick % 3 == 0:
			await get_tree().process_frame  # let the visuals run
		var settled := not casts.is_empty() and caster.state.action == FighterState.Action.IDLE
		if settled and not in_play.any(alive):
			break
	var mine := casts.filter(func(cast: Dictionary) -> bool: return cast.fighter == caster)
	assert_eq(mine.size(), 1, "%s leaves the hand once" % id)
	if not mine.is_empty():
		assert_eq(mine[0].spell, data)
	if data.slot == SpellData.Slot.PRIMARY:
		assert_almost_eq(stamina_after_press, caster.state.max_stamina - data.stamina_cost, 0.001, "%s costs stamina" % id)
	else:
		assert_eq(stamina_after_press, caster.state.max_stamina, "%s costs no stamina" % id)
		assert_gt(caster.state.signature_cd, data.cooldown - 6.5, "%s starts its cooldown" % id)
	assert_gt(hits_on(foe).size(), 0, "%s reaches the foe" % id)
	assert_lt(foe.state.hp, foe.state.max_hp, "%s hurts" % id)
	assert_true(impacts.any(func(impact: Dictionary) -> bool: return impact.spell == data), "%s reports where it landed" % id)
	assert_eq(caster.state.action, FighterState.Action.IDLE, "%s: the caster recovers" % id)
	for node in in_play:
		assert_false(alive(node), "%s: %s ends by itself" % [id, node])


## All eight at once from eight casters, run by the engine itself this time
## (physics on), then everything they spawned (spell nodes, visuals,
## sounds, ground marks) must be gone again.
func test_spells_and_their_effects_clean_up_after_themselves() -> void:
	var casters: Array[Fighter] = []
	var foes: Array[Fighter] = []
	var ids: Array = GameData.spells.keys()
	for i in ids.size():
		var data := spell(ids[i])
		var x := (i - ids.size() * 0.5) * 14.0
		var caster := add_fighter(Vector3(x, 0.0, 0.0), 0)
		if data.slot == SpellData.Slot.PRIMARY:
			caster.primary = data
		else:
			caster.signature = data
		casters.append(caster)
		foes.append(add_fighter(Vector3(x, 0.0, -3.0 if data is NovaSpell else -8.0), 1, PI))
	await wait_process_frames(3)  # the fighters' visuals settle in
	SfxPool.of(world)  # the sound pool is made once and kept
	var baseline := get_tree().get_node_count()
	var commands: Array[InputCommand] = []
	for i in casters.size():
		commands.append(command(casters[i], 0, _button(spell(ids[i])), foes[i].chest_position()))
	for tick in ticks(2.0):  # long enough for the slowest to land (Lightning Strike: wind-up + delay)
		await get_tree().physics_frame
		for i in casters.size():
			casters[i].simulate(commands[i], get_physics_process_delta_time())
			commands[i].pressed = 0
	assert_eq(casts.size(), ids.size(), "every spell went off")
	for i in foes.size():
		assert_lt(foes[i].state.hp, foes[i].state.max_hp, "%s landed" % ids[i])
	# a fighter's burning embers are made on its first burn and kept for the next
	var kept := func() -> int:
		return casters.filter(func(f: Fighter) -> bool: return f.find_child("Embers", true, false) != null).size() 				+ foes.filter(func(f: Fighter) -> bool: return f.find_child("Embers", true, false) != null).size()
	var clean: bool = await wait_until(func() -> bool:
		return spell_nodes().is_empty() and get_tree().get_node_count() <= baseline + kept.call(), 9.0)
	assert_true(clean, "%d nodes left over (%d spell nodes)" % [get_tree().get_node_count() - baseline - kept.call(),
			spell_nodes().size()])
