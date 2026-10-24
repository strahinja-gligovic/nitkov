class_name WindFx
extends RefCounted
## How Wind looks: Wind Slash's crescent, the Wind Spear and the burst where
## it lands, and wind's charge-up, release gust and impacts. Wind reads as
## flowing, translucent air: crescents and spirals of streak lines, bent
## light, dust kicked up and things blown away. Cosmetic only (see SpellFx):
## nothing here writes gameplay state, and every effect frees itself.

const COLOR := Color(0.5, 1.0, 0.72)
const PALE := Color(0.85, 1.0, 0.92)

const FLASH_SHADER := preload("res://src/vfx/wind/wind_flash.gdshader")
const CORE_SHADER := preload("res://src/vfx/wind/wind_core.gdshader")
const SHOCK_SHADER := preload("res://src/vfx/wind/wind_shock.gdshader")
const SPRAY_SHADER := preload("res://src/vfx/wind/wind_spray.gdshader")
const RING_SHADER := preload("res://src/vfx/wind/wind_ring.gdshader")
const MARK_SHADER := preload("res://src/vfx/wind/wind_mark.gdshader")
## Variants built per spray pattern (each spawn picks one and turns it).
const SPRAY_VARIANTS := 3

static var _materials := {}
static var _meshes := {}
static var _sprays := {}


## Wind Slash's body: a crescent of air as wide as its hit, bowed forward
## like a parabola (-Z is the direction of flight). See WindSlashLook.
static func slash(spell: ProjectileSpell) -> Node3D:
	return WindSlashLook.create(spell)


## The Wind Spear's body: a heavy javelin of storm wind (-Z is the direction
## of flight). See WindSpearLook.
static func spear(spell: ProjectileSpell) -> Node3D:
	return WindSpearLook.create(spell)


## Where a Wind Slash ends (the Wind Spear bursts instead; see burst()). On a
## fighter or a wall it splashes into a gust: a flash, streaks fanning out, a
## gust ring and a puff of dust. At the end of its range it doesn't pop; it
## unravels into streaks that drift on and fade.
static func impact(world: Node, at: Vector3, normal: Vector3, struck: bool, fizzled: bool, spell: ProjectileSpell) -> void:
	if fizzled:
		_unravel(world, at, -normal, spell)
	elif struck:
		_splash(world, _body_contact(world, at), normal, true)
	else:
		_splash(world, at, normal, false)


## Wind gathering in the casting hand over the windup (see WindChargeFx).
static func charge(hand: Node3D, seconds: float, signature: bool) -> void:
	WindChargeFx.attach(hand, seconds, signature)


## The spell leaving the hand: a pinwheel flash, a gust ring blown along the
## throw and a cone of speed lines. The spear's throw is bigger, with a second
## ring and dust kicked back off the ground behind the thrower.
static func release(world: Node, at: Vector3, direction: Vector3, signature: bool) -> void:
	var forward := Vector3(direction.x, 0.0, direction.z)
	forward = forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD
	var fx := WindOneShot.spawn(world, at, Basis.looking_at(forward, Vector3.UP))
	var size := 1.0 if not signature else 1.7
	fx.add(_flash(0.55 * size), 0.0, 0.09)
	# the gust rings are blown away down the throw, so they read as a launch
	# shockwave and never hang around the thrower hiding what's ahead
	var ring := _ring(&"ring_gust", 0.12 * size, 0.62 * (1.0 if not signature else 1.45))
	ring.rotation.x = PI * 0.5
	ring.position.z = -0.3
	fx.add_moving(ring, 0.0, 0.18 if not signature else 0.22, Vector3.FORWARD * (2.4 if not signature else 4.0))
	if signature:
		var second := _ring(&"ring_gust", 0.15, 0.75)
		second.rotation.x = PI * 0.5
		second.position.z = -0.8
		fx.add_moving(second, 0.04, 0.22, Vector3.FORWARD * 5.5)
	var cone := _spray(&"gust_cone")
	cone.set_instance_shader_parameter(&"reach", size)
	fx.add(cone, 0.0, 0.22 if not signature else 0.3)
	fx.add_light(COLOR, 1.6 * size, 3.5 * size, 0.12)
	if signature:
		_recoil_dust(world, at, forward)


## The Wind Spear bursting at `at` (in mid-air where it struck someone, or on
## a wall or the floor). A white-hot pop, then a sphere of shoved air slams
## out to `radius` in about 0.15 s with speed lines blasting past it and a
## swirl spinning out at its heart. Near the ground a shock ring races across
## the floor, a ring of dust rolls out and chips fly, leaving the floor
## scoured. Leaves and motes are flung everywhere, and everyone it blows away
## trails speed lines as they go.
static func burst(world: Node, at: Vector3, radius: float) -> void:
	var floor_y := _floor_below(world, at, radius * 0.75)
	var height := at.y - floor_y
	var fx := WindOneShot.spawn(world, at)
	fx.add(_flash(2.6), 0.0, 0.09)
	var heart := _part(&"sphere", &"core")
	heart.scale = Vector3.ONE * 0.6
	fx.add(heart, 0.0, 0.05)
	var shock := _part(&"sphere", &"shock")
	shock.set_instance_shader_parameter(&"radius", radius)
	shock.set_instance_shader_parameter(&"seed", randf() * 10.0)
	fx.add(shock, 0.0, 0.34)
	var lines := _spray(&"burst_ground" if height < 0.6 else &"burst_air")
	lines.set_instance_shader_parameter(&"reach", radius / 4.0)
	fx.add(lines, 0.0, 0.42)
	var swirl := _ring(&"ring_swirl", 0.3, radius * 0.7)
	fx.add(swirl, 0.0, 0.32)
	fx.add_light(COLOR, 5.0, radius * 2.2, 0.32, Vector3.UP * 0.4)
	var bits := WindParticles.spawn(world, 64)
	bits.floor_y = floor_y
	if height < radius * 0.8:
		var ground := Vector3(at.x, floor_y, at.z)
		var reach := sqrt(maxf(radius * radius - height * height, 1.0))
		var ground_ring := _ring(&"ring_ground", 0.4, reach * 1.08)
		ground_ring.position.y = -height + 0.06
		fx.add(ground_ring, 0.0, 0.3)
		var mark := _part(&"flat_quad", &"mark")
		mark.position.y = -height + 0.025
		mark.scale = Vector3.ONE * reach * 2.4
		mark.rotation.y = randf() * TAU
		mark.set_instance_shader_parameter(&"seed", randf() * 10.0)
		fx.add(mark, 0.0, 2.8)
		_dust_ring(bits, ground, reach)
		_dust_settle(bits, ground, reach)
		for i in 8:
			var out := _flat_dir()
			bits.emit(WindParticles.Kind.CHIP, ground + out * 0.4 + Vector3.UP * 0.1,
					out * randf_range(4.0, 8.0) + Vector3.UP * randf_range(3.0, 6.0), randf_range(0.1, 0.17), randf_range(0.8, 1.1), 14.0)
	for i in 9:
		var out := (_flat_dir() + Vector3.UP * randf_range(-0.2, 0.6)).normalized()
		bits.emit(WindParticles.Kind.LEAF, at + out * 0.5, out * randf_range(6.0, 10.0) + Vector3.UP * randf_range(1.5, 4.0),
				randf_range(0.18, 0.26), randf_range(1.1, 1.5), 9.0)
	for i in 12:
		var out := Vector3(randf_range(-1.0, 1.0), randf_range(-0.3, 0.8), randf_range(-1.0, 1.0)).normalized()
		bits.emit(WindParticles.Kind.MOTE, at + out * 0.4, out * randf_range(10.0, 16.0), 0.07, randf_range(0.35, 0.55))
	_trail_pushed(world, at, radius, floor_y)


# --- the slash's ends ------------------------------------------------------------

## A slash splashing on a fighter (`on_body`) or a surface, at `at` with
## `normal` facing back out: a flash, a gust ring, a fan of streaks (around
## the body and on past it, or out along the wall), dust and a leaf or two.
static func _splash(world: Node, at: Vector3, normal: Vector3, on_body: bool) -> void:
	var basis := _facing(normal)
	var fx := WindOneShot.spawn(world, at, basis)
	fx.add(_flash(0.95 if on_body else 0.8), 0.0, 0.1)
	var ring := _ring(&"ring_gust", 0.3, 1.5)
	ring.rotation.x = PI * 0.5
	ring.position.z = 0.05
	fx.add(ring, 0.0, 0.24)
	var fan := _spray(&"splash_body" if on_body else &"splash_wall")
	fan.rotation.z = randf() * TAU
	fx.add(fan, 0.0, 0.34)
	fx.add_light(COLOR, 2.2, 4.0, 0.15)
	if not on_body:
		var mark := _part(&"quad", &"mark_small")
		mark.position.z = 0.02
		mark.scale = Vector3.ONE * 1.9
		mark.rotation.z = randf() * TAU
		mark.set_instance_shader_parameter(&"seed", randf() * 10.0)
		fx.add(mark, 0.0, 2.2)
	var bits := WindParticles.spawn(world, 12)
	bits.floor_y = _floor_below(world, at, 2.0)
	for i in 7:
		var angle := randf() * TAU
		var spread := basis * Vector3(cos(angle), sin(angle) * 0.7, randf_range(0.1, 0.5) if not on_body else -randf_range(0.0, 0.6))
		bits.emit(WindParticles.Kind.DUST, at + spread * 0.2, spread * randf_range(3.0, 5.5), randf_range(0.22, 0.34), randf_range(0.45, 0.65), 0.0, 1.3)
	for i in 2:
		var fling := basis * Vector3(randf_range(-1.0, 1.0), randf_range(0.2, 1.0), randf_range(-0.6, 0.6))
		bits.emit(WindParticles.Kind.LEAF, at, fling.normalized() * randf_range(4.0, 6.5), randf_range(0.16, 0.22), randf_range(0.9, 1.2), 10.0)


## A slash running out of range: no flash, no pop. Its streaks drift on,
## spread apart and fade, with a few motes and a leaf carried along.
static func _unravel(world: Node, at: Vector3, travel: Vector3, spell: ProjectileSpell) -> void:
	var forward := travel.normalized() if travel.length() > 0.01 else Vector3.FORWARD
	var fx := WindOneShot.spawn(world, at, Basis.looking_at(forward, Vector3.UP if absf(forward.y) < 0.95 else Vector3.BACK))
	var lines := _spray(&"unravel")
	var span := (maxf(spell.radius, 0.3) + 0.35) / 1.35
	lines.scale = Vector3(span, 1.0, 1.0)
	fx.add(lines, 0.0, 0.55)
	var bits := WindParticles.spawn(world, 8)
	for i in 6:
		var side := randf_range(-1.2, 1.2) * span
		var drift := forward * randf_range(4.0, 8.0) + Vector3(randf_range(-1.0, 1.0), randf_range(-0.5, 1.0), randf_range(-1.0, 1.0))
		bits.emit(WindParticles.Kind.MOTE, at + forward.cross(Vector3.UP).normalized() * side, drift, 0.06, randf_range(0.4, 0.6))
	for i in 2:
		bits.emit(WindParticles.Kind.LEAF, at + Vector3(randf_range(-0.6, 0.6), 0.0, randf_range(-0.6, 0.6)),
				forward * randf_range(5.0, 7.0) + Vector3.UP * randf_range(0.5, 1.5), 0.2, randf_range(1.0, 1.3), 7.0)


# --- helpers -----------------------------------------------------------------------

## Where a struck slash meets the victim: the point on the nearest fighter's
## body toward `at` (the projectile's centre is up to a metre short of it).
static func _body_contact(world: Node, at: Vector3) -> Vector3:
	var best := at
	var best_distance := 2.2
	for node in world.get_tree().get_nodes_in_group(&"fighters"):
		var body := node as Node3D
		if body == null:
			continue
		var feet := body.global_position
		var axis := Vector3(feet.x, clampf(at.y, feet.y + 0.4, feet.y + 1.6), feet.z)
		var distance := axis.distance_to(at)
		if distance < best_distance:
			best_distance = distance
			best = axis + (at - axis).normalized() * 0.35 if distance > 0.35 else at
	return best


## Height of the floor under `at` within `reach` below it, or -INF.
static func _floor_below(world: Node, at: Vector3, reach: float) -> float:
	# `world` may be a plain Node, so ask its viewport for the 3D world
	if world == null or not world.is_inside_tree():
		return -INF
	var viewport := world.get_viewport()
	var space: World3D = viewport.find_world_3d() if viewport else null
	if space == null:
		return -INF
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.3, at + Vector3.DOWN * reach, 1)
	var hit := space.direct_space_state.intersect_ray(query)
	return (hit.position as Vector3).y if hit else -INF


## Fighters a burst blows away trail speed lines while they fly.
static func _trail_pushed(world: Node, at: Vector3, radius: float, floor_y: float) -> void:
	for node in world.get_tree().get_nodes_in_group(&"fighters"):
		var body := node as Node3D
		if body == null or (body.global_position + Vector3.UP * 0.9).distance_to(at) > radius + 0.6:
			continue
		var pivot := body.get_node_or_null(^"Visual") as Node3D
		WindPushTrail.follow(world, pivot if pivot else body, floor_y)


## A ring of dust rolling out across the floor from `ground` to about `reach`.
static func _dust_ring(bits: WindParticles, ground: Vector3, reach: float) -> void:
	var count := 18
	for i in count:
		var angle := (float(i) + randf_range(-0.3, 0.3)) / count * TAU
		var out := Vector3(cos(angle), 0.0, sin(angle))
		bits.emit(WindParticles.Kind.DUST, ground + out * randf_range(0.4, 0.9) + Vector3.UP * randf_range(0.15, 0.35),
				out * reach * randf_range(2.6, 3.4) + Vector3.UP * randf_range(0.3, 1.2), randf_range(0.26, 0.38),
				randf_range(0.6, 0.85), 0.0, 1.8)


## The aftermath: slow, billowing dust left hanging over the scoured floor
## once the blast has passed, curling round the way the swirl spun.
static func _dust_settle(bits: WindParticles, ground: Vector3, reach: float) -> void:
	var count := 8
	for i in count:
		var angle := (float(i) + randf()) / count * TAU
		var out := Vector3(cos(angle), 0.0, sin(angle))
		var around := Vector3(-out.z, 0.0, out.x)
		bits.emit(WindParticles.Kind.DUST, ground + out * reach * randf_range(0.35, 1.0) + Vector3.UP * randf_range(0.1, 0.4),
				around * randf_range(1.5, 3.0) + out * randf_range(0.5, 1.5) + Vector3.UP * randf_range(0.2, 0.6),
				randf_range(0.22, 0.32), randf_range(0.9, 1.2), 0.0, 2.0)


## Dust blown back off the floor behind someone hurling the spear.
static func _recoil_dust(world: Node, at: Vector3, forward: Vector3) -> void:
	var floor_y := _floor_below(world, at, 2.5)
	if floor_y == -INF:
		return
	var feet := Vector3(at.x, floor_y, at.z) - forward * 0.6
	var bits := WindParticles.spawn(world, 8)
	bits.floor_y = floor_y
	for i in 5:
		var out := (-forward * 0.6 + forward.cross(Vector3.UP) * randf_range(-1.4, 1.4)).normalized()
		bits.emit(WindParticles.Kind.DUST, feet + out * 0.3 + Vector3.UP * 0.1, out * randf_range(3.0, 5.0) + Vector3.UP * randf_range(0.3, 0.9),
				randf_range(0.13, 0.2), randf_range(0.4, 0.55), 0.0, 1.6)


## A random flat direction.
static func _flat_dir() -> Vector3:
	var angle := randf() * TAU
	return Vector3(cos(angle), 0.0, sin(angle))


## A basis whose +Z is `normal` (so -Z points into the surface).
static func _facing(normal: Vector3) -> Basis:
	var out := normal.normalized() if normal.length() > 0.01 else Vector3.BACK
	return Basis.looking_at(-out, Vector3.UP if absf(out.y) < 0.95 else Vector3.BACK)


static func _flash(size: float) -> MeshInstance3D:
	var flash := _part(&"quad", &"flash")
	flash.scale = Vector3.ONE * size
	flash.set_instance_shader_parameter(&"spin", randf() * TAU)
	return flash


static func _ring(material: StringName, from: float, to: float) -> MeshInstance3D:
	var ring := _part(&"disc" if material == &"ring_swirl" else &"annulus", material)
	ring.set_instance_shader_parameter(&"radius_from", from)
	ring.set_instance_shader_parameter(&"radius_to", to)
	ring.set_instance_shader_parameter(&"seed", randf())
	return ring


static func _spray(pattern: StringName) -> MeshInstance3D:
	_build_shared()
	if not _sprays.has(pattern):
		var variants: Array[ArrayMesh] = []
		for i in SPRAY_VARIANTS:
			variants.append(WindMeshes.spray(_spray_streaks(pattern)))
		_sprays[pattern] = variants
	var spray := MeshInstance3D.new()
	var variants: Array[ArrayMesh] = _sprays[pattern]
	spray.mesh = variants[randi() % variants.size()]
	spray.material_override = _materials[&"spray_" + pattern]
	return spray


static func _part(mesh: StringName, material: StringName) -> MeshInstance3D:
	_build_shared()
	var part := MeshInstance3D.new()
	part.mesh = _meshes[mesh]
	part.material_override = _materials[material]
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return part


## The streaks of one spray pattern (see WindMeshes.spray), with -Z the way
## the spell was going and +Z back out of whatever it hit.
static func _spray_streaks(pattern: StringName) -> Array:
	var streaks := []
	match pattern:
		&"burst_air", &"burst_ground":
			var ground := pattern == &"burst_ground"
			for direction in WindMeshes.sphere_directions(30 if ground else 34, 0.2):
				direction.y *= 0.65
				if ground:
					direction.y = absf(direction.y) * 0.8 + 0.02
				direction = direction.normalized()
				streaks.append([direction * 0.35, direction, randf_range(4.2, 5.6), randf(), randf(), randf()])
		&"splash_body":
			for i in 14:
				var angle := (float(i) + randf()) / 14.0 * TAU
				var direction := Vector3(cos(angle), sin(angle) * 0.7, -randf_range(0.3, 0.9))
				streaks.append([Vector3(cos(angle), sin(angle) * 0.7, 0.0) * 0.25, direction, randf_range(1.2, 2.3), randf(), randf(), randf()])
		&"splash_wall":
			for i in 14:
				var angle := (float(i) + randf()) / 14.0 * TAU
				var direction := Vector3(cos(angle), sin(angle), randf_range(0.1, 0.45))
				streaks.append([Vector3(cos(angle), sin(angle), 0.1) * 0.2, direction, randf_range(1.0, 2.0), randf(), randf(), randf()])
		&"gust_cone":
			for i in 11:
				var offset := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), 0.0) * 0.14
				var direction := Vector3(offset.x * 2.2, offset.y * 2.2, -1.0)
				streaks.append([offset, direction, randf_range(1.4, 2.6), randf(), randf(), randf() * 0.6])
		&"unravel":
			for i in 12:
				var c := randf_range(-1.0, 1.0)
				var start := Vector3(c * 1.35, 0.4 * c * c + randf_range(-0.15, 0.15), -0.3 + 0.95 * c * c)
				var direction := Vector3(c * 0.4 + randf_range(-0.1, 0.1), randf_range(-0.1, 0.18), -1.0)
				streaks.append([start, direction, randf_range(1.8, 3.2), randf(), randf(), randf() * 0.5])
	return streaks


static func _build_shared() -> void:
	if not _materials.is_empty():
		return
	var quad := QuadMesh.new()
	_meshes[&"quad"] = quad
	var flat := QuadMesh.new()
	flat.orientation = PlaneMesh.FACE_Y
	_meshes[&"flat_quad"] = flat
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 48
	sphere.rings = 24
	_meshes[&"sphere"] = sphere
	_meshes[&"annulus"] = WindMeshes.annulus(0.5, 64)
	_meshes[&"disc"] = WindMeshes.annulus(0.02, 64)

	_materials[&"flash"] = _shader_material(FLASH_SHADER, {})
	_materials[&"core"] = _shader_material(CORE_SHADER, {&"hot_band": 0.7, &"ink_band": 0.9, &"hot_energy": 3.0})
	_materials[&"shock"] = _shader_material(SHOCK_SHADER, {})
	_materials[&"mark"] = _shader_material(MARK_SHADER, {&"groove_alpha": 0.42, &"dust_alpha": 0.26})
	_materials[&"mark_small"] = _shader_material(MARK_SHADER, {&"groove_alpha": 0.22, &"dust_alpha": 0.24})
	_materials[&"ring_gust"] = _shader_material(RING_SHADER, {&"arcs": 3.0, &"arc_fill": 0.78, &"swirl": 0.12,
			&"spin": 0.6, &"ink": 0.45, &"band_from": 0.2, &"band_to": 0.82, &"energy": 1.7})
	_materials[&"ring_ground"] = _shader_material(RING_SHADER, {&"arcs": 6.0, &"arc_fill": 0.85, &"swirl": 0.04,
			&"spin": 0.2, &"ink": 0.35, &"band_from": 0.25, &"band_to": 0.88, &"energy": 1.4})
	_materials[&"ring_swirl"] = _shader_material(RING_SHADER, {&"arcs": 4.0, &"arc_fill": 0.5, &"swirl": 0.8,
			&"spin": 1.2, &"ink": 0.0, &"band_from": 0.0, &"band_to": 0.55, &"energy": 1.3})
	_materials[&"spray_burst_air"] = _shader_material(SPRAY_SHADER, {&"line_length": 1.3, &"line_width": 0.09,
			&"delay_spread": 0.15, &"ease_power": 3.0, &"energy": 1.8})
	_materials[&"spray_burst_ground"] = _materials[&"spray_burst_air"]
	var splash := _shader_material(SPRAY_SHADER, {&"line_length": 0.6, &"line_width": 0.05,
			&"delay_spread": 0.2, &"ease_power": 2.5, &"energy": 1.6})
	_materials[&"spray_splash_body"] = splash
	_materials[&"spray_splash_wall"] = splash
	_materials[&"spray_gust_cone"] = _shader_material(SPRAY_SHADER, {&"line_length": 0.7, &"line_width": 0.045,
			&"delay_spread": 0.15, &"ease_power": 3.0, &"energy": 1.6})
	_materials[&"spray_unravel"] = _shader_material(SPRAY_SHADER, {&"line_length": 1.1, &"line_width": 0.035,
			&"delay_spread": 0.3, &"ease_power": 1.6, &"curl": 0.35, &"energy": 1.2})


static func _shader_material(shader: Shader, params: Dictionary) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	for key: StringName in params:
		material.set_shader_parameter(key, params[key])
	return material
