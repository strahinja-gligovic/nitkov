extends GutTest
## BotAim and BotRead: the duelist's aiming math and its read of an opponent.

var tuning: CombatTuning
var foe: FighterState


func before_each() -> void:
	tuning = CombatTuning.new()
	foe = FighterState.new()
	foe.reset(tuning)


# --- BotAim ---------------------------------------------------------------------

func test_intercept_of_a_still_target_is_distance_over_speed() -> void:
	var t := BotAim.intercept_time(Vector3.ZERO, Vector3(0, 0, -20), Vector3.ZERO, 50.0)
	assert_almost_eq(t, 0.4, 0.001)


func test_a_lead_point_meets_a_crossing_target() -> void:
	var origin := Vector3.ZERO
	var target := Vector3(0, 0, -15)
	var velocity := Vector3(5, 0, 0)
	for speed: float in [30.0, 50.0, 80.0]:
		var point := BotAim.lead_point(origin, target, velocity, speed)
		var t := origin.distance_to(point) / speed
		assert_almost_eq(point.distance_to(target + velocity * t), 0.0, 0.01, "shot and target meet at %d m/s" % speed)


func test_slower_shots_lead_further() -> void:
	var target := Vector3(0, 0, -15)
	var velocity := Vector3(5, 0, 0)
	var bolt := BotAim.lead_point(Vector3.ZERO, target, velocity, 80.0)
	var slash := BotAim.lead_point(Vector3.ZERO, target, velocity, 30.0)
	assert_lt(bolt.x, 1.2, "Lightning Bolt barely leads")
	assert_gt(slash.x, bolt.x * 2.0, "Wind Slash leads much further")


func test_lead_zero_aims_where_they_are() -> void:
	var target := Vector3(0, 0, -15)
	assert_eq(BotAim.lead_point(Vector3.ZERO, target, Vector3(5, 0, 0), 30.0, 0.0), target)


func test_a_target_outrunning_the_shot_falls_back_to_a_plain_lead() -> void:
	assert_eq(BotAim.intercept_time(Vector3.ZERO, Vector3(0, 0, -10), Vector3(0, 0, -60), 50.0), -1.0)
	var point := BotAim.lead_point(Vector3.ZERO, Vector3(0, 0, -10), Vector3(0, 0, -60), 50.0)
	assert_true(point.is_finite())


func test_knockback_travel_matches_the_decay() -> void:
	var travel := BotAim.knockback_travel(Vector3(7, 3, 0))
	assert_almost_eq(travel.x, 49.0 / (2.0 * BotAim.KNOCKBACK_DECAY), 0.001)
	assert_eq(travel.y, 0.0, "only the ground part carries them")


func test_predict_waits_out_a_pin_then_drifts() -> void:
	var at := BotAim.predict_position(Vector3.ZERO, Vector3(4, 0, 0), Vector3.ZERO, 0.5, 1.5, 1.0)
	assert_almost_eq(at.x, 4.0, 0.001)
	at = BotAim.predict_position(Vector3.ZERO, Vector3(4, 0, 0), Vector3.ZERO, 0.0, 1.0, 0.5)
	assert_almost_eq(at.x, 2.0, 0.001, "lead scales the drift")


func test_circle_exit_distance() -> void:
	assert_almost_eq(BotAim.circle_exit_distance(Vector3.ZERO, Vector3.RIGHT, Vector3.ZERO, 2.5), 2.5, 0.001)
	# one metre right of centre: 1.5 m out to the right, 3.5 m out to the left
	var point := Vector3(1, 0, 0)
	assert_almost_eq(BotAim.circle_exit_distance(point, Vector3.RIGHT, Vector3.ZERO, 2.5), 1.5, 0.001)
	assert_almost_eq(BotAim.circle_exit_distance(point, Vector3.LEFT, Vector3.ZERO, 2.5), 3.5, 0.001)
	assert_eq(BotAim.circle_exit_distance(Vector3(4, 0, 0), Vector3.LEFT, Vector3.ZERO, 2.5), 0.0, "already out")


func test_floor_point_of_a_descending_shot() -> void:
	var at := BotAim.floor_point(Vector3(0, 1.3, 0), Vector3(0, -1.3, -10), 0.0)
	assert_almost_eq(at.z, -10.0, 0.001)
	assert_eq(BotAim.floor_point(Vector3(0, 1.3, 0), Vector3(0, 0.5, -10), 0.0), Vector3.INF, "climbing shots never land")


func test_heading_steadiness() -> void:
	assert_almost_eq(BotAim.heading_steadiness(Vector3(5, 0, 0), 5.0), 1.0, 0.001)
	assert_almost_eq(BotAim.heading_steadiness(Vector3(0.5, 0, 0), 5.0), 0.1, 0.001, "jinking averages out")
	assert_eq(BotAim.heading_steadiness(Vector3.ZERO, 0.1), 0.0, "standing still")


# --- BotRead --------------------------------------------------------------------

func _swing(at: float) -> AttackData:
	var attack := AttackData.new()
	attack.windup = 0.3
	attack.active = 0.1
	attack.recovery = 0.4
	attack.dodge_cancel_after = 0.1
	foe.start_action(FighterState.Action.ATTACK, attack.duration())
	foe.attack = attack
	foe.action_time = at
	return attack


func test_a_free_fighter_is_not_pinned() -> void:
	assert_eq(BotRead.pinned_for(foe), 0.0)


func test_a_stagger_pins_for_what_is_left_plus_hitstop() -> void:
	foe.apply_stagger(1.0, &"shock")
	foe.action_time = 0.25
	foe.hitstop = 0.05
	assert_almost_eq(BotRead.pinned_for(foe), 0.8, 0.001)


func test_a_swing_pins_until_it_can_be_dodge_cancelled() -> void:
	_swing(0.1)
	assert_almost_eq(BotRead.pinned_for(foe), 0.4, 0.001)
	assert_almost_eq(BotRead.swing_lands_in(foe), 0.2, 0.001)
	foe.action_time = 0.45
	assert_eq(BotRead.swing_lands_in(foe), INF, "past its active frames")


func test_release_in_counts_down_the_windup() -> void:
	var spell := SpellData.new()
	spell.windup = 0.4
	foe.start_action(FighterState.Action.CAST, 0.8)
	foe.spell = spell
	foe.action_time = 0.15
	assert_almost_eq(BotRead.release_in(foe), 0.25, 0.001)
	foe.spell_released = true
	assert_eq(BotRead.release_in(foe), 0.0)


func test_casting_slows_the_escape() -> void:
	var free := BotRead.flee_speed(foe, tuning)
	foe.start_action(FighterState.Action.CAST, 0.8)
	foe.spell = SpellData.new()
	assert_almost_eq(BotRead.flee_speed(foe, tuning), free * tuning.cast_move_mult, 0.001)


func test_no_dash_while_exhausted_or_airborne() -> void:
	assert_true(BotRead.has_dash(foe))
	foe.on_floor = false
	assert_false(BotRead.has_dash(foe))
	foe.on_floor = true
	foe.exhausted = 1.0
	assert_false(BotRead.has_dash(foe))


func test_a_dash_escapes_a_strike_faster_than_walking() -> void:
	var walk := BotRead.escape_time(foe, tuning, 0.4, 2.5, 0.3, false)
	var dash := BotRead.escape_time(foe, tuning, 0.4, 2.5, 0.3)
	assert_almost_eq(walk, 0.3 + 2.5 / tuning.walk_speed, 0.001)
	assert_lt(dash, walk)
	assert_lt(dash, 0.9, "a free fighter who reacts can dash out of a Lightning Strike")


func test_a_long_stagger_cannot_escape_a_strike() -> void:
	foe.apply_stagger(1.6, &"shatter")
	var escape := BotRead.escape_time(foe, tuning, 0.4, 2.0, 0.3)
	assert_gt(escape, 0.9, "still stuck when the bolt lands")


func test_guard_down() -> void:
	assert_false(BotRead.guard_down(foe))
	_swing(0.1)
	assert_true(BotRead.guard_down(foe))
