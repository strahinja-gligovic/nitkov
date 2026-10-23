class_name FireFx
extends RefCounted
## How Fire looks: the Firebolt, the Flame Wall, and fire's charge-up,
## release flash and impacts. Cosmetic only (see SpellFx).

const COLOR := Color(1.0, 0.45, 0.12)
const HOT := Color(1.0, 0.85, 0.4)


## The Firebolt's body; -Z is the direction of flight.
static func firebolt(spell: ProjectileSpell) -> Node3D:
	return ElementFxKit.orb(COLOR, spell.radius)


static func impact(world: Node, at: Vector3, _normal: Vector3, struck: bool, fizzled: bool, spell: ProjectileSpell) -> void:
	if fizzled:
		ElementFxKit.flash(world, at, COLOR, 0.6, 0.15)
		return
	ElementFxKit.flash(world, at, HOT, 1.4 if struck else 1.1, 0.22)
	if spell.splash_radius > 0.0:
		Vfx.dome(world, at, COLOR, spell.splash_radius, 0.3)


static func charge(hand: Node3D, seconds: float, signature: bool) -> void:
	ElementFxKit.hand_glow(hand, COLOR, seconds, 0.2 if signature else 0.13)


static func release(world: Node, at: Vector3, _direction: Vector3, signature: bool) -> void:
	ElementFxKit.flash(world, at, HOT, 0.8 if signature else 0.5, 0.12)


## The Flame Wall's fire, added as a child of the wall (local X along the
## wall, -Z the way it faces, Y up from the ground). The wall calls
## set_intensity() every tick: 0 out, 1 full blaze.
static func flame_wall(spell: FlameWallSpell) -> FlameWallLook:
	var look := FlameWallLook.new()
	look.build(spell)
	return look
