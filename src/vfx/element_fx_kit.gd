class_name ElementFxKit
extends RefCounted
## Small building blocks shared by the element effect modules: glowing orbs,
## flashes, hand glows. Cosmetic only; everything frees itself.


## A glowing core with a stretched halo and a light (a basic projectile body;
## -Z is the direction of flight).
static func orb(color: Color, radius: float) -> Node3D:
	var root := Node3D.new()
	var core := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	core.mesh = sphere
	core.material_override = ToonMaterials.make_vfx(color.lightened(0.35), 4.0, false)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(core)
	var halo := MeshInstance3D.new()
	var halo_mesh := SphereMesh.new()
	halo_mesh.radius = radius * 1.8
	halo_mesh.height = radius * 3.6
	halo.mesh = halo_mesh
	halo.scale = Vector3(1.0, 1.0, 2.2)
	halo.position = Vector3(0.0, 0.0, radius * 1.5)
	var halo_material := ToonMaterials.make_vfx(color, 2.0)
	halo_material.albedo_color.a = 0.45
	halo.material_override = halo_material
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(halo)
	root.add_child(light(color, 1.6, 4.0))
	return root


static func light(color: Color, energy: float, reach: float) -> OmniLight3D:
	var lamp := OmniLight3D.new()
	lamp.light_color = color
	lamp.light_energy = energy
	lamp.omni_range = reach
	return lamp


## A short bright flash with a light at `at`.
static func flash(world: Node, at: Vector3, color: Color, size: float, duration := 0.18) -> void:
	Vfx.impact(world, at, color, size, duration, 6.0)
	var lamp := light(color, 3.0, size * 4.0)
	world.add_child(lamp)
	lamp.global_position = at
	var tween := lamp.create_tween()
	tween.tween_property(lamp, ^"light_energy", 0.0, duration)
	tween.tween_callback(lamp.queue_free)


## A glow that swells in the hand over `seconds`, then pops.
static func hand_glow(hand: Node3D, color: Color, seconds: float, size: float) -> void:
	if not is_instance_valid(hand):
		return
	var glow := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = size
	sphere.height = size * 2.0
	glow.mesh = sphere
	var material := ToonMaterials.make_vfx(color, 3.0)
	material.albedo_color.a = 0.6
	glow.material_override = material
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow.scale = Vector3.ONE * 0.3
	hand.add_child(glow)
	var tween := glow.create_tween()
	tween.tween_property(glow, ^"scale", Vector3.ONE, maxf(seconds, 0.05)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(glow.queue_free)
