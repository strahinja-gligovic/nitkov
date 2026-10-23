class_name SpellSfx
extends RefCounted
## How spells sound. SpellFx calls these next to each visual; every sound is
## cosmetic, plays through SfxPool's bounded voices, frees itself, and reads
## nothing back. The sounds are procedural (tools/sfx/build_sfx.py writes
## assets/sfx/); each element has a charge, a release, a flight loop, a hit on
## a fighter, a hit on a surface and a fizzle, plus the signatures' own
## moments.

## Charge risers keep 0.08 s of decay after their peak (build_sfx.py); the peak
## is lined up with the release.
const CHARGE_TAIL := 0.08
## Strike warning: built as a 0.9 s countdown, then a held top.
const WARNING_BUILT_FOR := 0.9

static var _params := {}
## Body instance id -> the shock loop's voice handle.
static var _shocks := {}


## How each kind of sound plays: volume_db, near (m), max distance (m), pitch
## jitter, priority. Big moments carry further and win voice fights.
static func _p(kind: StringName) -> SfxPool.Params:
	if _params.is_empty():
		_params = {
			&"charge": SfxPool.Params.new(-3.0, 5.5, 40.0, 0.03, 1),
			&"release": SfxPool.Params.new(-1.0, 6.0, 50.0, 0.06, 2),
			&"flight": SfxPool.Params.new(-1.0, 5.5, 45.0, 0.04, 1),
			&"hit": SfxPool.Params.new(0.0, 7.0, 55.0, 0.06, 2),
			&"surface": SfxPool.Params.new(-1.0, 7.0, 55.0, 0.06, 2),
			&"fizzle": SfxPool.Params.new(-2.0, 5.0, 40.0, 0.06, 1),
			&"big": SfxPool.Params.new(0.0, 9.0, 75.0, 0.04, 3),
			&"warning": SfxPool.Params.new(-1.0, 8.0, 55.0, 0.0, 3),
			&"wall": SfxPool.Params.new(-1.0, 5.0, 50.0, 0.03, 2),
			&"shock": SfxPool.Params.new(-3.0, 5.5, 40.0, 0.04, 2),
		}
	return _params[kind]


## Forgets cached settings and handles (SfxPool calls this on its way out).
static func clear() -> void:
	_params.clear()
	_shocks.clear()


static func _element(element: SpellData.Element) -> String:
	match element:
		SpellData.Element.FIRE:
			return "fire"
		SpellData.Element.FROST:
			return "frost"
		SpellData.Element.LIGHTNING:
			return "lightning"
		SpellData.Element.WIND:
			return "wind"
	return ""


## The wind-up in the casting hand (`hand` follows the gauntlet): a riser
## whose peak lands on the release, `seconds` from now.
static func charge(spell: SpellData, hand: Node3D, seconds: float) -> void:
	var pool := SfxPool.of(hand)
	var element := _element(spell.element)
	if pool == null or element == "":
		return
	var signature := spell.slot == SpellData.Slot.SIGNATURE
	var stream := SfxBank.pick(StringName(element + ("_charge_sig" if signature else "_charge")))
	if stream == null:
		return
	var built := stream.get_length() - CHARGE_TAIL
	var from := maxf(built - seconds, 0.0)
	pool.play(stream, hand.global_position, _p(&"charge"), hand, Vector3.ZERO, from, 0.03 if from > 0.0 else 0.0, true)


## The spell leaving the hand at `at`. (Frost Nova's burst is its release.)
static func release(spell: SpellData, world: Node, at: Vector3) -> void:
	var element := _element(spell.element)
	if spell is NovaSpell or element == "":
		return
	var signature := spell.slot == SpellData.Slot.SIGNATURE
	_one_shot(world, StringName(element + ("_release_sig" if signature else "_release")), at, &"release")


## The flight: `look` is the projectile's body, which moves with it. The loop
## follows it, bends its pitch as it passes, and stops in projectile_end().
static func projectile(spell: ProjectileSpell, look: Node3D) -> void:
	var element := _element(spell.element)
	if element == "" or look == null:
		return
	var loop_name := StringName(element + "_loop")
	if spell.element == SpellData.Element.WIND and spell.burst_radius > 0.0:
		loop_name = &"wind_spear_loop"
	_when_in_tree(look, func() -> void:
		var pool := SfxPool.of(look) if is_instance_valid(look) else null
		if pool:
			pool.loop(SfxBank.pick(loop_name), look, _p(&"flight"), Vector3.ZERO, 0.04, true))


## The projectile is gone (its look may linger to fade its trail).
static func projectile_end(look: Node3D) -> void:
	var pool := SfxPool.of(look) if is_instance_valid(look) else null
	if pool:
		pool.stop_target(look.get_instance_id(), 0.09)


## Where a projectile ends (`struck` a fighter; `fizzled` out of range). A
## Wind Spear bursts here.
static func impact(spell: ProjectileSpell, world: Node, at: Vector3, struck: bool, fizzled: bool) -> void:
	var element := _element(spell.element)
	if element == "":
		return
	if spell.burst_radius > 0.0:
		_one_shot(world, &"wind_burst", at, &"big")
		if struck:
			_one_shot(world, &"wind_hit", at, &"hit")
		return
	if fizzled:
		_one_shot(world, StringName(element + "_fizzle"), at, &"fizzle")
	elif struck:
		_one_shot(world, StringName(element + "_hit"), at, &"hit")
	else:
		_one_shot(world, StringName(element + "_surface"), at, &"surface")


## The Flame Wall burning; `look` lives as long as the wall. It ignites with
## a whoomph, roars from the point of the wall nearest the listener, and dies
## down with the flames over the last 0.4 s.
static func flame_wall(spell: FlameWallSpell, look: Node3D) -> void:
	if look == null:
		return
	_when_in_tree(look, func() -> void:
		var pool := SfxPool.of(look) if is_instance_valid(look) else null
		if pool == null:
			return
		pool.play(SfxBank.pick(&"flame_wall_ignite"), look.global_position, _p(&"big"), look, Vector3.UP * 0.6)
		var roar := pool.loop(SfxBank.pick(&"flame_wall_loop"), look, _p(&"wall"), Vector3.UP * 0.8, 0.25,
				false, spell.length * 0.5)
		pool.stop_after(roar, maxf(spell.duration - 0.45, 0.0), 0.4))


static func nova(_spell: NovaSpell, world: Node, at: Vector3) -> void:
	_one_shot(world, &"frost_nova", at + Vector3.UP * 0.5, &"big")


## The strike's warning mark; `warning` is freed when the bolt lands. A buzz
## rising over the delay, timed so its top meets the bolt; it cuts off when
## the warning goes.
static func strike_warning(spell: LightningStrikeSpell, warning: Node3D) -> void:
	if warning == null:
		return
	_when_in_tree(warning, func() -> void:
		var pool := SfxPool.of(warning) if is_instance_valid(warning) else null
		if pool == null:
			return
		var from := maxf(WARNING_BUILT_FOR - spell.delay, 0.0)
		pool.play(SfxBank.pick(&"strike_warning"), warning.global_position, _p(&"warning"), warning,
				Vector3.UP * 0.3, from, 0.03 if from > 0.0 else 0.0, true))


static func strike(_spell: LightningStrikeSpell, world: Node, at: Vector3) -> void:
	_one_shot(world, &"strike_thunder", at + Vector3.UP, &"big")


static func shatter(world: Node, at: Vector3) -> void:
	_one_shot(world, &"shatter", at, &"big")


## A lightning stun on a fighter's body (`body` follows the fighter): a
## sputtering buzz at the chest for `seconds`. A stun while one is still
## crackling extends it instead of stacking a second loop.
static func shock(body: Node3D, seconds: float) -> void:
	var pool := SfxPool.of(body)
	if pool == null:
		return
	var key := body.get_instance_id()
	if pool.extend(_shocks.get(key, 0), seconds):
		return
	var handle := pool.loop(SfxBank.pick(&"shock_loop"), body, _p(&"shock"), Vector3.UP * 1.1, 0.03)
	pool.stop_after(handle, seconds, 0.12)
	_shocks[key] = handle


static func _one_shot(world: Node, sound: StringName, at: Vector3, kind: StringName) -> void:
	var pool := SfxPool.of(world)
	if pool:
		pool.play(SfxBank.pick(sound), at, _p(kind))


## Runs `start` once `node` is in the tree and placed: projectile looks and
## the flame wall's fire are handed to SpellSfx before they're added, and
## get their transform right after (so wait for the end of that frame).
static func _when_in_tree(node: Node, start: Callable) -> void:
	if node.is_inside_tree():
		start.call()
	else:
		node.tree_entered.connect(func() -> void: start.call_deferred(), CONNECT_ONE_SHOT)
