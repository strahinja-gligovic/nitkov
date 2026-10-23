class_name WindFx
extends RefCounted
## How Wind looks: Wind Slash's crescent, the Wind Spear and the burst where
## it lands, and wind's charge-up, release flash and impacts. Cosmetic only
## (see SpellFx).

const COLOR := Color(0.5, 1.0, 0.72)
const PALE := Color(0.85, 1.0, 0.92)


## Wind Slash's body: a crescent of air as wide as its hit radius, bowed
## forward like a parabola (-Z is the direction of flight).
static func slash(spell: ProjectileSpell) -> Node3D:
	var root := Node3D.new()
	var reach := maxf(spell.radius, 0.3) * 1.15
	var arc := MeshInstance3D.new()
	arc.mesh = _crescent(reach, 120.0)
	arc.position.z = reach  # the apex at the projectile, the wings trailing
	var material := ToonMaterials.make_vfx(COLOR, 2.2)
	material.albedo_color.a = 0.75
	arc.material_override = material
	arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(arc)
	root.add_child(ElementFxKit.light(COLOR, 1.0, 3.0))
	return root


## The Wind Spear's body: a long spear of compressed air ringed with gusts
## (-Z is the direction of flight).
static func spear(spell: ProjectileSpell) -> Node3D:
	var root := Node3D.new()
	var shaft := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = maxf(spell.radius, 0.15) * 0.8
	cone.height = 2.4
	cone.radial_segments = 8
	shaft.mesh = cone
	shaft.rotation.x = -PI * 0.5  # the cone's tip (+Y) along -Z
	shaft.position.z = 0.9  # the point leads
	var material := ToonMaterials.make_vfx(PALE, 2.5)
	material.albedo_color.a = 0.8
	shaft.material_override = material
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(shaft)
	for i in 3:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.18 + i * 0.06
		torus.outer_radius = 0.24 + i * 0.06
		ring.mesh = torus
		ring.rotation.x = PI * 0.5  # around the flight line
		ring.position.z = 0.3 + i * 0.55
		var ring_material := ToonMaterials.make_vfx(COLOR, 2.0)
		ring_material.albedo_color.a = 0.6
		ring.material_override = ring_material
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(ring)
	root.add_child(ElementFxKit.light(COLOR, 1.6, 4.0))
	return root


## Where a Wind Slash ends (the Wind Spear bursts instead; see burst()).
static func impact(world: Node, at: Vector3, _normal: Vector3, struck: bool, fizzled: bool, _spell: ProjectileSpell) -> void:
	ElementFxKit.flash(world, at, PALE, 0.4 if fizzled else (0.9 if struck else 0.6), 0.14)


static func charge(hand: Node3D, seconds: float, signature: bool) -> void:
	ElementFxKit.hand_glow(hand, COLOR, seconds, 0.2 if signature else 0.12)


static func release(world: Node, at: Vector3, _direction: Vector3, signature: bool) -> void:
	ElementFxKit.flash(world, at, PALE, 0.8 if signature else 0.45, 0.12)


## The Wind Spear bursting at `at`: a shock dome and ring as wide as its
## reach (`radius`).
static func burst(world: Node, at: Vector3, radius: float) -> void:
	ElementFxKit.flash(world, at, PALE, radius * 0.6, 0.2)
	Vfx.dome(world, at, COLOR, radius, 0.35)
	Vfx.ring(world, at, COLOR, radius, 0.3)


## A crescent in the XZ plane around the origin, bowed toward -Z: `reach` to
## its outer edge, `span_deg` wide, thickest in the middle and tapering to
## points at the tips.
static func _crescent(reach: float, span_deg: float) -> ArrayMesh:
	var segments := 24
	var vertices := PackedVector3Array()
	for i in segments + 1:
		var u := float(i) / segments
		var angle := deg_to_rad(lerpf(-span_deg * 0.5, span_deg * 0.5, u))
		var dir := Vector3(sin(angle), 0.0, -cos(angle))
		vertices.append(dir * reach * (1.0 - 0.28 * sin(PI * u)))
		vertices.append(dir * reach)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLE_STRIP, arrays)
	return mesh
