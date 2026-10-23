class_name FireFx
extends RefCounted
## How Fire looks: the Firebolt, the Flame Wall, and fire's charge-up,
## release flash and impacts. Fire is heat and chaos: roiling toon-banded
## flames (white core, yellow, orange, red, an ink rim), embers, sparks and
## dark-edged smoke. Cosmetic only (see SpellFx); every effect frees itself.
## The pieces live next to this file: FireKit (shared shaders, materials and
## particle recipes), FireBoltLook, FireCharge, FireMuzzle, FireExplosion,
## FireScorch, FireMotes and FlameWallLook.

const COLOR := Color(1.0, 0.45, 0.12)
const HOT := Color(1.0, 0.85, 0.4)


## The Firebolt's body; -Z is the direction of flight. It implements
## finish(), so its trail and embers die out after the impact.
static func firebolt(spell: ProjectileSpell) -> Node3D:
	return FireBoltLook.create(spell.radius)


## Where a Firebolt ended: an explosion the size of its splash (on the body
## for a fighter hit, scorching a wall or the floor), or at the end of its
## range a sputter of smoke.
static func impact(world: Node, at: Vector3, normal: Vector3, struck: bool, fizzled: bool, spell: ProjectileSpell) -> void:
	if fizzled:
		FireExplosion.fizzle(world, at, -normal)
		return
	var splash := spell.splash_radius if spell.splash_radius > 0.0 else 1.0
	FireExplosion.burst(world, at, normal, splash, struck)


## Fire gathering in the fist over the wind-up (bigger for the signature).
static func charge(hand: Node3D, seconds: float, signature: bool) -> void:
	if not is_instance_valid(hand) or not hand.is_inside_tree():
		return
	FireCharge.start(hand, seconds, signature)


## The burst of flame as the spell leaves the fist.
static func release(world: Node, at: Vector3, direction: Vector3, signature: bool) -> void:
	FireMuzzle.fire(world, at, direction, signature)


## The Flame Wall's fire, added as a child of the wall (local X along the
## wall, -Z the way it faces, Y up from the ground). The wall calls
## set_intensity() every tick: 0 out, 1 full blaze.
static func flame_wall(spell: FlameWallSpell) -> FlameWallLook:
	var look := FlameWallLook.new()
	look.build(spell)
	return look
