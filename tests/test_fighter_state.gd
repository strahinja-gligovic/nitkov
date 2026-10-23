extends GutTest
## FighterState: stamina, timers, the input buffer and action transitions.

var tuning: CombatTuning
var state: FighterState


func before_each() -> void:
	tuning = CombatTuning.new()
	state = FighterState.new()
	state.reset(tuning)


func test_reset_fills_health_and_stamina() -> void:
	assert_eq(state.hp, tuning.max_hp)
	assert_eq(state.stamina, tuning.max_stamina)
	assert_eq(state.action, FighterState.Action.IDLE)


func test_reset_drops_any_shove_or_pop_still_pending() -> void:
	state.knockback = Vector3(9.0, 0.0, -3.0)
	state.launch = 5.0
	state.apply_stagger(1.0, &"shock")
	state.reset(tuning)
	assert_eq(state.knockback, Vector3.ZERO)
	assert_eq(state.launch, 0.0, "a respawn doesn't pop you up")
	assert_eq(state.action, FighterState.Action.IDLE)
	assert_eq(state.stagger_kind, &"")


func test_stamina_floors_at_zero_and_any_stamina_allows_actions() -> void:
	state.stamina = 5.0
	assert_true(state.can_spend())
	state.spend_stamina(20.0, tuning)
	assert_eq(state.stamina, 0.0)
	assert_false(state.can_spend())


func test_regen_waits_for_the_delay() -> void:
	state.spend_stamina(50.0, tuning)
	state.tick(tuning.stamina_regen_delay - 0.1, tuning)
	assert_eq(state.stamina, 50.0, "no regen during the delay")
	state.tick(0.1, tuning)
	state.tick(1.0, tuning)
	assert_almost_eq(state.stamina, 50.0 + tuning.stamina_regen, 0.01)


func test_blocking_halves_regen() -> void:
	state.stamina = 50.0
	state.blocking = true
	state.tick(1.0, tuning)
	assert_almost_eq(state.stamina, 50.0 + tuning.stamina_regen * tuning.block_regen_mult, 0.01)


func test_exhaustion_blocks_spending_and_regen() -> void:
	state.stamina = 0.0
	state.exhausted = tuning.exhausted_duration
	state.tick(1.0, tuning)
	assert_eq(state.stamina, 0.0)
	assert_false(state.can_spend())
	state.tick(tuning.exhausted_duration, tuning)
	assert_eq(state.exhausted, 0.0)


func test_buffered_presses_expire() -> void:
	state.buffer_presses(InputCommand.LIGHT | InputCommand.DASH, tuning)
	assert_true(state.has_buffered(InputCommand.LIGHT))
	assert_true(state.consume_buffered(InputCommand.DASH))
	assert_false(state.has_buffered(InputCommand.DASH), "consumed presses are gone")
	state.tick(tuning.input_buffer + 0.01, tuning)
	assert_false(state.has_buffered(InputCommand.LIGHT), "stale presses expire")


func test_flinch_never_shortens_a_stagger() -> void:
	state.apply_stagger(1.0, &"parried")
	state.action_time = 0.2
	state.apply_flinch(0.25)
	assert_eq(state.action, FighterState.Action.STAGGER)
	assert_eq(state.stagger_kind, &"parried")


func test_stagger_overrides_flinch() -> void:
	state.apply_flinch(0.25)
	state.apply_stagger(0.8, &"guard_break")
	assert_eq(state.action, FighterState.Action.STAGGER)
	assert_eq(state.action_duration, 0.8)


func test_damage_kills_at_zero_and_interrupts_healing() -> void:
	state.heal_time = 1.0
	assert_false(state.take_damage(40.0))
	assert_eq(state.heal_time, 0.0, "damage interrupts orb healing")
	assert_true(state.take_damage(100.0))
	assert_true(state.is_dead())
	assert_false(state.take_damage(10.0), "the dead can't die twice")


func test_each_action_gets_a_new_serial() -> void:
	var before := state.action_serial
	state.start_action(FighterState.Action.DASH, 0.25)
	state.end_action()
	assert_eq(state.action_serial, before + 2)
