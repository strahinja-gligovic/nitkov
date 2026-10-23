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


## Like _tick, but inside real physics frames. move_and_slide() takes its
## delta from the engine, so tests that measure distance need this.
func _tick_physics(cmd: InputCommand, ticks := 1) -> void:
	for i in ticks:
		await get_tree().physics_frame
		fighter.simulate(cmd, get_physics_process_delta_time())
		cmd.pressed = 0


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


func _move_cmd(direction: Vector2, pressed := 0) -> InputCommand:
	var cmd := _cmd(0, pressed)
	cmd.move = direction
	return cmd


func test_dash_covers_its_distance_with_iframes() -> void:
	var start := fighter.global_position
	await _tick_physics(_move_cmd(Vector2(1, 0), InputCommand.DASH))
	assert_eq(fighter.state.action, FighterState.Action.DASH)
	assert_gt(fighter.state.invulnerable, 0.0)
	assert_almost_eq(fighter.state.stamina, fighter.tuning.max_stamina - fighter.tuning.dash_stamina, 0.01)
	await _tick_physics(_move_cmd(Vector2(1, 0)), int(fighter.tuning.dash_duration / DT) - 1)
	var travelled := fighter.global_position - start
	assert_almost_eq(travelled.x, fighter.tuning.dash_distance, 0.5)
	assert_almost_eq(travelled.z, 0.0, 0.05)


func test_dash_without_input_steps_backwards() -> void:
	_tick(_cmd(0, InputCommand.DASH))
	assert_almost_eq(fighter.state.dash_dir.dot(fighter.forward()), -1.0, 0.001)


func test_exhausted_fighters_cannot_dash() -> void:
	fighter.state.exhausted = 1.0
	_tick(_cmd(0, InputCommand.DASH))
	assert_eq(fighter.state.action, FighterState.Action.IDLE)


func test_dash_cancels_late_recovery_but_not_windup() -> void:
	_tick(_cmd(0, InputCommand.HEAVY))
	_tick(_cmd(0, InputCommand.DASH))
	assert_eq(fighter.state.action, FighterState.Action.ATTACK, "no dodging out of a committed wind-up")
	var heavy := fighter.weapon.heavy
	var to_cancel := heavy.windup + heavy.active + heavy.dodge_cancel_after
	_tick(_cmd(), int(ceil(to_cancel / DT)))
	_tick(_cmd(0, InputCommand.DASH))
	assert_eq(fighter.state.action, FighterState.Action.DASH)


func _add_wall(x: float) -> void:
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1, 6, 20)
	shape.shape = box
	wall.add_child(shape)
	wall.position = Vector3(x, 3, 0)
	add_child_autofree(wall)


func test_leap_reaches_ledge_height_and_lands() -> void:
	fighter.rune = GameData.runes[&"leap"]
	await _tick_physics(_cmd(0, InputCommand.RUNE))
	assert_true(fighter.state.leaping)
	assert_eq(fighter.state.rune_cd, fighter.rune.cooldown)
	var peak := 0.0
	for i in 240:
		await _tick_physics(_cmd())
		peak = maxf(peak, fighter.global_position.y)
		if not fighter.state.leaping:
			break
	assert_between(peak, 3.3, 4.3, "peak %.2fm clears the 3m ledge" % peak)
	assert_false(fighter.state.leaping, "landed")


func test_runes_respect_their_cooldown() -> void:
	fighter.rune = GameData.runes[&"blink"]
	_tick(_cmd(0, InputCommand.RUNE))
	var after_first := fighter.global_position
	_tick(_cmd(0, InputCommand.RUNE))
	assert_eq(fighter.global_position, after_first, "second blink is on cooldown")


func test_blink_teleports_forward_and_stops_at_walls() -> void:
	fighter.rune = GameData.runes[&"blink"]
	_add_wall(5.0)  # wall face at x = 4.5
	_tick(_move_cmd(Vector2(1, 0), InputCommand.RUNE))
	assert_lt(fighter.global_position.x, 4.5 - Fighter.RADIUS + 0.05, "stopped short of the wall")
	assert_gt(fighter.global_position.x, 3.0, "but went most of the way")
	assert_gt(fighter.state.invulnerable, 0.0)


func test_blink_in_open_ground_covers_its_distance() -> void:
	fighter.rune = GameData.runes[&"blink"]
	_tick(_move_cmd(Vector2(0, -1), InputCommand.RUNE))
	assert_almost_eq(fighter.global_position.z, -(GameData.runes[&"blink"] as BlinkRune).distance, 0.1)


func test_exhausted_fighters_cannot_use_runes() -> void:
	fighter.rune = GameData.runes[&"blink"]
	fighter.state.exhausted = 1.0
	_tick(_move_cmd(Vector2(1, 0), InputCommand.RUNE))
	assert_almost_eq(fighter.global_position.x, 0.0, 0.01)


func test_presses_during_a_flinch_are_buffered() -> void:
	fighter.state.apply_flinch(0.1)
	_tick(_cmd(0, InputCommand.LIGHT))
	assert_eq(fighter.state.action, FighterState.Action.FLINCH)
	_tick(_cmd(), 6)
	assert_eq(fighter.state.action, FighterState.Action.ATTACK, "the buffered light fires when the flinch ends")
