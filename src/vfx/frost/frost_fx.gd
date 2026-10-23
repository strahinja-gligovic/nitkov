class_name FrostFx
extends RefCounted
## How Frost looks: the Ice Spike, Frost Nova, and frost's charge-up,
## release flash and impacts. Cosmetic only (see SpellFx).

const COLOR := Color(0.35, 0.8, 1.0)
const PALE := Color(0.8, 0.95, 1.0)


## The Ice Spike's body: one long crystal, point first (-Z is the direction
## of flight).
static func ice_spike(spell: ProjectileSpell) -> Node3D:
	var root := Node3D.new()
	var crystal := CylinderMesh.new()
	crystal.top_radius = 0.0
	crystal.bottom_radius = spell.radius * 0.7
	crystal.height = spell.radius * 6.0
	crystal.radial_segments = 6
	crystal.rings = 1
	var body := MeshInstance3D.new()
	body.mesh = crystal
	body.material_override = ToonMaterials.make(PALE, {&"glow_color": COLOR, &"glow_energy": 1.6})
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.rotation.x = -PI * 0.5  # the cylinder's tip (+Y) along -Z
	root.add_child(body)
	root.add_child(ElementFxKit.light(COLOR, 1.2, 3.0))
	return root


static func impact(world: Node, at: Vector3, normal: Vector3, struck: bool, fizzled: bool, _spell: ProjectileSpell) -> void:
	if fizzled:
		Vfx.shards(world, at, COLOR, 4, 0.6, 0.3)
		return
	ElementFxKit.flash(world, at, PALE, 1.0 if struck else 0.8, 0.18)
	Vfx.shards(world, at + normal * 0.1, COLOR, 7, 1.2, 0.4)


static func charge(hand: Node3D, seconds: float, signature: bool) -> void:
	ElementFxKit.hand_glow(hand, COLOR, seconds, 0.2 if signature else 0.12)


static func release(world: Node, at: Vector3, _direction: Vector3, signature: bool) -> void:
	ElementFxKit.flash(world, at, PALE, 0.8 if signature else 0.45, 0.12)


## The ice on a Chilled target bursting when Fire hits it (Shatter), at
## the point of the hit.
static func shatter(world: Node, at: Vector3) -> void:
	Vfx.shards(world, at, COLOR, 12, 2.2)


## Frost Nova bursting out of the caster's feet at `at`.
static func nova(world: Node, at: Vector3, radius: float) -> void:
	Vfx.ring(world, at, COLOR, radius, 0.4)
	Vfx.dome(world, at, COLOR, radius, 0.45)
	Vfx.shards(world, at + Vector3.UP * 0.4, COLOR, 14, radius * 0.8)
