extends GutTest
## Mix-and-match loadouts: data registries, applying a loadout to a fighter,
## and the menu-to-match hand-off defaults.

const FIGHTER := preload("res://src/combat/fighter.tscn")


func test_every_spell_is_a_primary_or_a_signature() -> void:
	var primaries := GameData.spells_for(SpellData.Slot.PRIMARY)
	var signatures := GameData.spells_for(SpellData.Slot.SIGNATURE)
	assert_eq(primaries.size() + signatures.size(), GameData.spells.size())
	assert_gt(primaries.size(), 1, "there's a real choice of primaries")
	assert_gt(signatures.size(), 1, "and of signatures")
	for spell: SpellData in primaries:
		assert_gt(spell.stamina_cost, 0.0, "%s: primaries cost stamina" % spell.id)
		assert_ne(spell.description, "", "%s has a menu description" % spell.id)
	for spell: SpellData in signatures:
		assert_gt(spell.cooldown, 0.0, "%s: signatures have a cooldown" % spell.id)
		assert_ne(spell.description, "", "%s has a menu description" % spell.id)


func test_every_character_has_a_model() -> void:
	assert_gt(GameData.characters.size(), 1)
	for id: StringName in GameData.characters:
		var character: CharacterData = GameData.characters[id]
		assert_eq(character.id, id)
		assert_not_null(character.outfit, "%s has an outfit" % id)
		assert_not_null(character.head_from, "%s has a head" % id)
		assert_ne(character.display_name, "")


func test_every_character_assembles() -> void:
	for id: StringName in GameData.characters:
		var rig := CharacterRig.build(GameData.characters[id])
		assert_not_null(rig.skeleton, "%s has a skeleton" % id)
		assert_eq(rig.skeleton.get_bone_count(), 65, "%s is on the shared rig" % id)
		var head := rig.skeleton.get_node_or_null(^"Head") as MeshInstance3D
		assert_not_null(head, "%s has a head" % id)
		if head:
			assert_gt(head.mesh.get_surface_count(), 1, "%s: face, eyes, brows" % id)
		assert_not_null(rig.sword, "%s holds the sword" % id)
		assert_gt(rig.materials.size(), 3, "%s is toon-shaded" % id)
		assert_gt(rig.upper_body_filter().size(), 40, "upper body: spine, head, both arms and fingers")
		var left := rig.left_arm_filter()
		assert_true(left.has(NodePath("Armature/Skeleton3D:hand_l")))
		assert_false(left.has(NodePath("Armature/Skeleton3D:hand_r")), "the sword arm keeps running")
		rig.free()


func test_match_config_defaults_point_at_real_data() -> void:
	for loadout: Loadout in [MatchConfig.player, MatchConfig.bot]:
		assert_true(GameData.characters.has(loadout.character))
		assert_eq((GameData.spells[loadout.primary] as SpellData).slot, SpellData.Slot.PRIMARY)
		assert_eq((GameData.spells[loadout.signature] as SpellData).slot, SpellData.Slot.SIGNATURE)
		assert_true(GameData.runes.has(loadout.rune))


func test_applying_a_cross_element_loadout() -> void:
	var fighter: Fighter = FIGHTER.instantiate()
	add_child_autofree(fighter)
	watch_signals(fighter)
	fighter.apply_loadout(Loadout.make(&"tavernkeep", &"ice_spike", &"flame_wall", &"blink"))
	assert_eq(fighter.character.id, &"tavernkeep")
	assert_eq(fighter.primary.id, &"ice_spike")
	assert_eq(fighter.signature.id, &"flame_wall")
	assert_eq(fighter.rune.id, &"blink")
	assert_signal_emitted(fighter, "loadout_changed")


func test_unknown_ids_keep_the_current_pick() -> void:
	var fighter: Fighter = FIGHTER.instantiate()
	add_child_autofree(fighter)
	var before := fighter.primary
	fighter.apply_loadout(Loadout.make(fighter.character.id, &"no_such_spell", fighter.signature.id, fighter.rune.id))
	assert_eq(fighter.primary, before)


func test_quick_swap_cycles_through_primaries() -> void:
	var fighter: Fighter = FIGHTER.instantiate()
	add_child_autofree(fighter)
	var seen := {}
	for i in GameData.spells_for(SpellData.Slot.PRIMARY).size():
		seen[fighter.primary.id] = true
		fighter.cycle_primary()
	assert_eq(seen.size(), GameData.spells_for(SpellData.Slot.PRIMARY).size())
