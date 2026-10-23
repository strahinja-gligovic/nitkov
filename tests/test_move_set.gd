extends GutTest
## The move set covers everything the simulation can do, and every move's
## keys make sense for how it's played.

## Moves FighterVisual and AnimDirector ask for by name.
const REQUIRED := [
	&"idle", &"walk", &"run", &"jog", &"sprint",
	&"dash_f", &"dash_b", &"dash_l", &"dash_r",
	&"flinch", &"flinch_heavy", &"stagger", &"guard_break", &"knockdown",
	&"block", &"block_impact", &"parry",
	&"leap_start", &"leap_air", &"leap_fall", &"leap_land", &"entrance", &"blink", &"taunt",
]

var moves: MoveSet


func before_all() -> void:
	moves = load("res://data/moves/humanoid.tres")


func test_loads() -> void:
	assert_true(moves is MoveSet)


func test_required_moves_exist() -> void:
	for id in REQUIRED:
		assert_true(moves.has_move(id), "missing move %s" % id)
	var deaths := moves.moves.keys().filter(func(id: StringName) -> bool: return String(id).begins_with("death"))
	assert_gt(deaths.size(), 0, "at least one death")


func test_every_attack_and_spell_has_a_swing_move() -> void:
	var weapon: WeaponData = load("res://data/weapons/longsword.tres")
	var swings: Array = weapon.light_chain.duplicate()
	swings.append(weapon.heavy)
	for attack: AttackData in swings:
		var move := moves.get_move(attack.animation)
		assert_not_null(move, "%s plays %s" % [attack.id, attack.animation])
		if move:
			assert_eq(move.keys.size(), 6, "%s: start, antic, go, contact, settle, end" % attack.animation)
	for path in GameData.SPELL_PATHS:
		var spell: SpellData = load(path)
		var move := moves.get_move(spell.animation)
		assert_not_null(move, "%s plays %s" % [spell.id, spell.animation])
		if move:
			assert_eq(move.keys.size(), 6, "%s: start, antic, go, release, settle, end" % spell.animation)


func test_keys_ascend_and_clips_are_named_by_source() -> void:
	for id: StringName in moves.moves:
		var move: AnimMove = moves.moves[id]
		assert_eq(String(move.clip).split("/").size(), 2, "%s: clip is <source>/<name>" % id)
		assert_gt(move.keys.size(), 1, "%s has keys" % id)
		for i in range(1, move.keys.size()):
			assert_true(move.keys[i] >= move.keys[i - 1], "%s: keys ascend" % id)


func test_timed_keys_match_their_fractions() -> void:
	for id: StringName in moves.moves:
		var move: AnimMove = moves.moves[id]
		if move.sim_keys.is_empty():
			continue
		assert_eq(move.sim_keys.size(), move.keys.size(), "%s: one fraction per key" % id)
		assert_almost_eq(move.sim_keys[0], 0.0, 0.001, "%s starts at 0" % id)
		assert_almost_eq(move.sim_keys[move.sim_keys.size() - 1], 1.0, 0.001, "%s ends at 1" % id)


func test_locomotion_loops_are_ordered_by_speed() -> void:
	var last := 0.0
	for id in AnimDirector.LOCO:
		var move := moves.get_move(id)
		assert_gt(move.ground_speed, 0.5, "%s ground speed" % id)
		var at := move.play_at if move.play_at > 0.0 else move.ground_speed
		assert_gt(at, last, "%s is faster than the loop before it" % id)
		last = at


func test_recoveries_exist() -> void:
	for id: StringName in moves.moves:
		var move: AnimMove = moves.moves[id]
		if move.recover != &"":
			assert_true(moves.has_move(move.recover), "%s recovers with %s" % [id, move.recover])


func test_every_clip_exists_in_its_source() -> void:
	var available := {}
	for prefix: StringName in AnimLibrary.SOURCES:
		var scene: PackedScene = load(AnimLibrary.SOURCES[prefix])
		assert_not_null(scene, "source %s imports" % prefix)
		if scene == null:
			continue
		var instance := scene.instantiate()
		var player := instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if player:
			for clip in player.get_animation_list():
				available["%s/%s" % [prefix, clip.get_file()]] = player.get_animation(clip).length
		instance.free()
	for id: StringName in moves.moves:
		var move: AnimMove = moves.moves[id]
		assert_true(available.has(String(move.clip)), "%s: clip %s exists" % [id, move.clip])
		if move.has_chain():
			assert_true(available.has(String(move.chain_clip)), "%s: clip %s exists" % [id, move.chain_clip])
		if not available.has(String(move.clip)):
			continue
		var length: float = available[String(move.clip)]
		if move.has_chain():
			length = move.chain_at - move.chain_blend + move.chain_to - move.chain_from
		assert_true(move.keys[move.keys.size() - 1] <= length + 0.002, "%s: keys stay inside the clip" % id)
