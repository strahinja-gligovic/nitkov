extends GutTest
## SfxPool stays bounded and cleans up after its targets; every sound the
## game asks for exists. (Headless, so voices run their logic silently.)

const SOUNDS := [
	&"fire_charge", &"fire_charge_sig", &"fire_release", &"fire_release_sig", &"fire_loop", &"fire_hit",
	&"fire_surface", &"fire_fizzle", &"flame_wall_ignite", &"flame_wall_loop",
	&"frost_charge", &"frost_charge_sig", &"frost_release", &"frost_loop", &"frost_hit", &"frost_surface",
	&"frost_fizzle", &"frost_nova", &"shatter",
	&"lightning_charge", &"lightning_charge_sig", &"lightning_release", &"lightning_release_sig", &"lightning_loop",
	&"lightning_hit", &"lightning_surface", &"lightning_fizzle", &"strike_warning", &"strike_thunder", &"shock_loop",
	&"wind_charge", &"wind_charge_sig", &"wind_release", &"wind_release_sig", &"wind_loop", &"wind_spear_loop",
	&"wind_hit", &"wind_surface", &"wind_fizzle", &"wind_burst",
	&"sword_swing", &"sword_swing_heavy", &"flesh_hit", &"block_clang", &"parry_ring", &"guard_break", &"dash",
	&"land", &"death",
]

var world: Node3D


func before_each() -> void:
	world = Node3D.new()
	add_child_autofree(world)
	SfxPool.of(world).stop_all()


func test_every_sound_exists() -> void:
	for sound in SOUNDS:
		assert_gt(SfxBank.streams(sound).size(), 0, "missing sound %s" % sound)


func test_loops_loop_and_one_shots_do_not() -> void:
	var loop := SfxBank.pick(&"fire_loop") as AudioStreamWAV
	assert_eq(loop.loop_mode, AudioStreamWAV.LOOP_FORWARD)
	var once := SfxBank.pick(&"fire_hit") as AudioStreamWAV
	assert_eq(once.loop_mode, AudioStreamWAV.LOOP_DISABLED)


func test_pool_is_bounded() -> void:
	var pool := SfxPool.of(world)
	var children := pool.get_child_count()
	var params := SfxPool.Params.new()
	for i in 200:
		pool.play(SfxBank.pick(&"fire_hit"), Vector3(i % 7, 0, 0), params)
	assert_eq(pool.busy_voices(), SfxPool.ONE_SHOT_VOICES)
	assert_eq(pool.get_child_count(), children, "voices are made once, never added")
	assert_eq(SfxPool.of(world), pool, "one pool per viewport")


func test_important_sounds_steal_unimportant_ones() -> void:
	var pool := SfxPool.of(world)
	var low := SfxPool.Params.new(0.0, 5.0, 50.0, 0.0, 1)
	var high := SfxPool.Params.new(0.0, 5.0, 50.0, 0.0, 3)
	for i in SfxPool.ONE_SHOT_VOICES:
		pool.play(SfxBank.pick(&"fire_hit"), Vector3.ZERO, high)
	assert_eq(pool.play(SfxBank.pick(&"fire_hit"), Vector3.ZERO, low), 0, "a full pool drops the less important sound")
	assert_ne(pool.play(SfxBank.pick(&"shatter"), Vector3.ZERO, high), 0)


func test_loop_fades_when_its_target_goes() -> void:
	var pool := SfxPool.of(world)
	var look := Node3D.new()
	world.add_child(look)
	var handle := pool.loop(SfxBank.pick(&"fire_loop"), look, SfxPool.Params.new())
	assert_true(pool.is_playing(handle))
	look.free()
	await wait_frames(20)
	assert_false(pool.is_playing(handle))


func test_projectile_loop_starts_once_its_look_is_placed() -> void:
	var spell: ProjectileSpell = GameData.spells[&"firebolt"]
	var look := Node3D.new()
	SpellSfx.projectile(spell, look)
	world.add_child(look)
	await wait_frames(2)
	var pool := SfxPool.of(world)
	var busy := pool.busy_voices()
	assert_gt(busy, 0)
	SpellSfx.projectile_end(look)
	look.queue_free()
	await wait_frames(20)
	assert_lt(pool.busy_voices(), busy)


func test_scheduled_stop_and_extend() -> void:
	var pool := SfxPool.of(world)
	var body := Node3D.new()
	world.add_child(body)
	SpellSfx.shock(body, 0.1)
	SpellSfx.shock(body, 0.1)  # re-applied: extends, doesn't stack
	await wait_frames(2)
	assert_eq(pool.busy_voices(), 1)
	await wait_seconds(0.5)
	assert_eq(pool.busy_voices(), 0)


func test_spell_calls_survive_nodes_outside_the_tree() -> void:
	var loose := Node3D.new()
	SpellSfx.charge(GameData.spells[&"firebolt"], loose, 0.14)
	SpellSfx.shock(loose, 1.0)
	SpellSfx.projectile_end(loose)
	loose.free()
	assert_true(true, "no crash")
