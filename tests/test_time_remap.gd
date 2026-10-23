extends GutTest
## Pose-to-pose time remapping (TimeRemap).

const SIM := [0.0, 0.1, 0.2, 0.3]
const CLIP := [1.0, 1.5, 1.6, 2.6]


func test_keys_land_exactly() -> void:
	for i in SIM.size():
		assert_almost_eq(TimeRemap.map(SIM[i], PackedFloat32Array(SIM), PackedFloat32Array(CLIP)), CLIP[i], 0.0001)


func test_between_keys_is_linear() -> void:
	assert_almost_eq(TimeRemap.map(0.05, PackedFloat32Array(SIM), PackedFloat32Array(CLIP)), 1.25, 0.0001)
	assert_almost_eq(TimeRemap.map(0.25, PackedFloat32Array(SIM), PackedFloat32Array(CLIP)), 2.1, 0.0001)


func test_clamps_outside_the_keys() -> void:
	assert_almost_eq(TimeRemap.map(-1.0, PackedFloat32Array(SIM), PackedFloat32Array(CLIP)), 1.0, 0.0001)
	assert_almost_eq(TimeRemap.map(5.0, PackedFloat32Array(SIM), PackedFloat32Array(CLIP)), 2.6, 0.0001)


func test_zero_length_segments_do_not_divide_by_zero() -> void:
	var sim := PackedFloat32Array([0.0, 0.2, 0.2, 0.4])
	var clip := PackedFloat32Array([0.0, 1.0, 2.0, 3.0])
	assert_almost_eq(TimeRemap.map(0.21, sim, clip), 2.05, 0.0001)
	assert_almost_eq(TimeRemap.map(0.3, sim, clip), 2.5, 0.0001)


func test_swing_contact_lands_when_the_active_frames_begin() -> void:
	var keys := TimeRemap.swing_keys(0.7, 0.12, 0.5, 0.1, 0.25, 0.5)
	assert_eq(keys.size(), 6)
	assert_almost_eq(keys[3], 0.7, 0.0001, "contact")
	assert_almost_eq(keys[2], 0.6, 0.0001, "go = contact - strike")
	assert_almost_eq(keys[1], 0.35, 0.0001, "antic = go - hold")
	assert_almost_eq(keys[4], 0.7 + 0.12 + 0.25, 0.0001, "settle half way into recovery")
	assert_almost_eq(keys[5], 1.32, 0.0001, "end")


func test_short_windups_squeeze_hold_and_strike() -> void:
	var keys := TimeRemap.swing_keys(0.1, 0.08, 0.3, 0.09, 0.05, 0.5)
	for i in range(1, keys.size()):
		assert_true(keys[i] >= keys[i - 1], "keys ascend")
	assert_true(keys[2] >= 0.04 - 0.0001, "the strike never eats the whole wind-up")
	assert_true(keys[1] > 0.0, "there is always some anticipation")


func test_casts_have_no_active_frames() -> void:
	var keys := TimeRemap.swing_keys(0.14, 0.0, 0.26, 0.06, 0.0, 0.4)
	assert_almost_eq(keys[3], 0.14, 0.0001)
	assert_almost_eq(keys[5], 0.4, 0.0001)


func test_timed_lands_keys_at_their_fractions() -> void:
	var clip := PackedFloat32Array([0.0, 0.133, 0.233, 0.95, 1.067])
	var fractions := PackedFloat32Array([0.0, 0.125, 0.3, 0.9, 1.0])
	assert_almost_eq(TimeRemap.timed(0.1, 0.8, clip, fractions), 0.133, 0.0001, "peak at 0.1 s")
	assert_almost_eq(TimeRemap.timed(0.72, 0.8, clip, fractions), 0.95, 0.0001, "settle at 0.72 s")
	assert_almost_eq(TimeRemap.timed(2.0, 0.8, clip, fractions), 1.067, 0.0001, "holds the end")


func test_timed_without_fractions_plays_evenly() -> void:
	var clip := PackedFloat32Array([0.2, 0.45])
	assert_almost_eq(TimeRemap.timed(0.125, 0.25, clip), 0.325, 0.0001)
	var three := PackedFloat32Array([1.0, 1.5, 3.0])
	assert_almost_eq(TimeRemap.timed(0.25, 1.0, three), 1.5, 0.0001, "middle key keeps its place in the clip")
