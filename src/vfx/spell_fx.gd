class_name SpellFx
extends RefCounted
## How spells look and sound: routed to one module per element
## (src/vfx/<element>/) and to SpellSfx. Gameplay code calls these and never
## builds a spell's visuals itself; every effect is cosmetic, frees itself,
## and reads nothing back.
##
## Each element module provides:
##   charge(hand, seconds, signature)       a charge-up held in the casting hand
##   release(world, at, direction, signature)  the flash as the spell leaves it
##   impact(world, at, normal, struck, fizzled, spell)  where a projectile ends
## plus its own spells' bodies and areas (see each module).


## The projectile's body. Its -Z is the direction of flight; the Projectile
## places it every frame. It may implement finish() to fade out its trail
## after the projectile is gone (see release_look).
static func projectile(spell: ProjectileSpell) -> Node3D:
	var look: Node3D
	match spell.element:
		SpellData.Element.FIRE:
			look = FireFx.firebolt(spell)
		SpellData.Element.FROST:
			look = FrostFx.ice_spike(spell)
		SpellData.Element.LIGHTNING:
			look = LightningFx.bolt(spell)
		SpellData.Element.WIND:
			look = WindFx.spear(spell) if spell.burst_radius > 0.0 else WindFx.slash(spell)
		_:
			look = Node3D.new()
	SpellSfx.projectile(spell, look)
	return look


## Where a projectile ended: `struck` it hit a fighter, `fizzled` it ran out
## of range without hitting anything. `normal` faces back toward the shooter
## (or out of the wall it hit). A Wind Spear bursts here.
static func impact(spell: ProjectileSpell, world: Node, at: Vector3, normal: Vector3, struck: bool, fizzled: bool) -> void:
	match spell.element:
		SpellData.Element.FIRE:
			FireFx.impact(world, at, normal, struck, fizzled, spell)
		SpellData.Element.FROST:
			FrostFx.impact(world, at, normal, struck, fizzled, spell)
		SpellData.Element.LIGHTNING:
			LightningFx.impact(world, at, normal, struck, fizzled, spell)
		SpellData.Element.WIND:
			if spell.burst_radius > 0.0:
				WindFx.burst(world, at, spell.burst_radius)
			else:
				WindFx.impact(world, at, normal, struck, fizzled, spell)
	SpellSfx.impact(spell, world, at, struck, fizzled)


## Hands a projectile's look to the world when the projectile ends, so its
## trail fades out instead of vanishing (if the look implements finish()).
static func release_look(look: Node3D, world: Node) -> void:
	if not is_instance_valid(look):
		return
	SpellSfx.projectile_end(look)
	if look.has_method(&"finish"):
		var where := look.global_transform
		look.get_parent().remove_child(look)
		world.add_child(look)
		look.global_transform = where
		look.call(&"finish")
	else:
		look.queue_free()


## A charge-up in the casting hand for the cast's wind-up.
static func charge(spell: SpellData, hand: Node3D, seconds: float) -> void:
	var signature := spell.slot == SpellData.Slot.SIGNATURE
	match spell.element:
		SpellData.Element.FIRE:
			FireFx.charge(hand, seconds, signature)
		SpellData.Element.FROST:
			FrostFx.charge(hand, seconds, signature)
		SpellData.Element.LIGHTNING:
			LightningFx.charge(hand, seconds, signature)
		SpellData.Element.WIND:
			WindFx.charge(hand, seconds, signature)
	SpellSfx.charge(spell, hand, seconds)


## The flash as a spell leaves the hand at `at`, toward `direction`.
static func release(spell: SpellData, world: Node, at: Vector3, direction: Vector3) -> void:
	var signature := spell.slot == SpellData.Slot.SIGNATURE
	match spell.element:
		SpellData.Element.FIRE:
			FireFx.release(world, at, direction, signature)
		SpellData.Element.FROST:
			FrostFx.release(world, at, direction, signature)
		SpellData.Element.LIGHTNING:
			LightningFx.release(world, at, direction, signature)
		SpellData.Element.WIND:
			WindFx.release(world, at, direction, signature)
	SpellSfx.release(spell, world, at)


## The Flame Wall's fire, added under the wall by the caller, which drives
## its set_intensity() every tick.
static func flame_wall(spell: FlameWallSpell) -> FlameWallLook:
	var look := FireFx.flame_wall(spell)
	SpellSfx.flame_wall(spell, look)
	return look


## Frost Nova going off around the caster's feet at `at`.
static func nova(spell: NovaSpell, world: Node, at: Vector3) -> void:
	FrostFx.nova(world, at, spell.radius)
	SpellSfx.nova(spell, world, at)


## Lightning Strike's warning mark under `mark` (the strike, at ground
## level). The strike frees what this returns when the bolt lands.
static func strike_warning(spell: LightningStrikeSpell, mark: Node3D) -> Node3D:
	var warning := LightningFx.strike_warning(mark, spell.radius, spell.delay)
	SpellSfx.strike_warning(spell, warning)
	return warning


## Lightning Strike's bolt landing at `at` (on the ground).
static func strike(spell: LightningStrikeSpell, world: Node, at: Vector3) -> void:
	LightningFx.strike(world, at, spell.radius)
	SpellSfx.strike(spell, world, at)


## Fire hitting a Chilled target: the ice bursts (at the point of the hit).
static func shatter(world: Node, at: Vector3) -> void:
	FrostFx.shatter(world, at)
	SpellSfx.shatter(world, at)


## A lightning stun crackling over a fighter's body (`body` is its visual
## pivot, origin at the feet) for `seconds`.
static func shock(body: Node3D, seconds: float) -> void:
	LightningFx.shock(body, seconds)
	SpellSfx.shock(body, seconds)
