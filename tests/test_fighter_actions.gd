extends GutTest
## Fighter integration: a real fighter scene stepped tick by tick with
## crafted InputCommands, on a floor, with physics processing switched off.

const FIGHTER := preload("res://src/combat/fighter.tscn")
const DT := 1.0 / 60.0

var fighter: Fighter


func before_each() -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0, -0.5, 0)
	add_child_autofree(floor_body)
	fighter = FIGHTER.instantiate()
	add_child_autofree(fighter)
	fighter.set_physics_process(false)
	_tick(_cmd(), 3)  # settle onto the floor


func _cmd(held := 0, pressed := 0) -> InputCommand:
	var cmd := InputCommand.new()
	cmd.held = held | pressed
	cmd.pressed = pressed
	cmd.aim_yaw = fighter.state.facing_yaw
	return cmd


func _tick(cmd: InputCommand, ticks := 1) -> void:
	for i in ticks:
		fighter.simulate(cmd, DT)
		cmd.pressed = 0  # a press only counts on its first tick


func test_tapping_block_opens_a_parry_window_and_blocks() -> void:
	_tick(_cmd(0, InputCommand.BLOCK))
	assert_gt(fighter.state.parry_window, 0.0)
	assert_true(fighter.state.blocking)


func test_parry_attempts_have_a_cooldown_but_holding_still_blocks() -> void:
	_tick(_cmd(0, InputCommand.BLOCK))
	_tick(_cmd(), 12)  # let go; the window closes
	assert_eq(fighter.state.parry_window, 0.0)
	_tick(_cmd(0, InputCommand.BLOCK))
	assert_eq(fighter.state.parry_window, 0.0, "too soon for another parry")
	assert_true(fighter.state.blocking)
	_tick(_cmd(), int(fighter.tuning.parry_cooldown / DT))
	_tick(_cmd(0, InputCommand.BLOCK))
	assert_gt(fighter.state.parry_window, 0.0, "cooldown over")


func test_exhausted_fighters_cannot_block() -> void:
	fighter.state.exhausted = 1.0
	_tick(_cmd(InputCommand.BLOCK))
	assert_false(fighter.state.blocking)


func test_attacking_drops_the_guard() -> void:
	_tick(_cmd(InputCommand.BLOCK), 2)
	_tick(_cmd(InputCommand.BLOCK, InputCommand.LIGHT))
	assert_eq(fighter.state.action, FighterState.Action.ATTACK)
	assert_false(fighter.state.blocking)


func test_light_presses_walk_the_chain_and_wrap() -> void:
	var seen: Array[int] = []
	for press in 4:
		_tick(_cmd(0, InputCommand.LIGHT))
		seen.append(fighter.state.combo_index)
		var attack := fighter.state.attack
		var to_chain := attack.windup + attack.active + attack.chain_after
		_tick(_cmd(), int(ceil(to_chain / DT)))
	assert_eq(seen, [0, 1, 2, 0] as Array[int])


func test_chain_resets_after_a_pause() -> void:
	_tick(_cmd(0, InputCommand.LIGHT))
	_tick(_cmd(), int((fighter.state.attack.duration() + fighter.tuning.combo_reset + 0.1) / DT))
	_tick(_cmd(0, InputCommand.LIGHT))
	assert_eq(fighter.state.combo_index, 0)


func test_heavy_costs_its_stamina() -> void:
	_tick(_cmd(0, InputCommand.HEAVY))
	assert_eq(fighter.state.action, FighterState.Action.ATTACK)
	assert_eq(fighter.state.attack, fighter.weapon.heavy)
	assert_almost_eq(fighter.state.stamina, fighter.tuning.max_stamina - fighter.weapon.heavy.stamina_cost, 0.01)


func test_no_stamina_no_swing() -> void:
	fighter.state.spend_stamina(1000.0, fighter.tuning)  # empty, with the regen delay pending
	_tick(_cmd(0, InputCommand.LIGHT))
	assert_eq(fighter.state.action, FighterState.Action.IDLE)


func test_presses_during_a_flinch_are_buffered() -> void:
	fighter.state.apply_flinch(0.1)
	_tick(_cmd(0, InputCommand.LIGHT))
	assert_eq(fighter.state.action, FighterState.Action.FLINCH)
	_tick(_cmd(), 6)
	assert_eq(fighter.state.action, FighterState.Action.ATTACK, "the buffered light fires when the flinch ends")
