extends GutTest

var tuning: CombatTuning
var defender: FighterState


func before_each() -> void:
	tuning = CombatTuning.new()
	defender = FighterState.new()
	defender.reset(tuning)


func _bolt() -> SpellHit:
	var hit := SpellHit.new()
	hit.element = SpellData.Element.LIGHTNING
	hit.damage = 9.0
	hit.flinch = 0.25
	return hit


func test_a_stream_of_bolts_flinches_once_per_immunity_window() -> void:
	CombatRules.resolve_spell(defender, _bolt(), true, tuning)
	assert_eq(defender.action, FighterState.Action.FLINCH)
	defender.end_action()  # the flinch ran out
	CombatRules.resolve_spell(defender, _bolt(), true, tuning)
	assert_eq(defender.action, FighterState.Action.IDLE, "too soon: the bolt still hurts but doesn't flinch")
	assert_eq(defender.hp, tuning.max_hp - 18.0)
	defender.tick(0.25 + tuning.spell_flinch_immunity, tuning)
	CombatRules.resolve_spell(defender, _bolt(), true, tuning)
	assert_eq(defender.action, FighterState.Action.FLINCH)
