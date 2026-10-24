class_name FireKit
extends RefCounted
## Shared pieces for the fire effects: the shaders, cached materials, meshes
## and particle recipes, the scorch textures (painted in code on first use),
## and small helpers. Everything here is built once and shared; what varies
## per spawn goes through instance uniforms.

const BALL := preload("res://src/vfx/fire/fire_ball.gdshader")
const BALL_SOFT := preload("res://src/vfx/fire/fire_ball_soft.gdshader")
const TRAIL := preload("res://src/vfx/fire/fire_trail.gdshader")
const MOTE := preload("res://src/vfx/fire/fire_mote.gdshader")
const SMOKE := preload("res://src/vfx/fire/fire_smoke.gdshader")
const RING := preload("res://src/vfx/fire/fire_ring.gdshader")
const FLASH := preload("res://src/vfx/fire/fire_flash.gdshader")
const TONGUE := preload("res://src/vfx/fire/fire_tongue.gdshader")
const BED := preload("res://src/vfx/fire/fire_bed.gdshader")

## Firelight, for every fire lamp.
const LIGHT := Color(1.0, 0.56, 0.24)

## Transparent draw order among the fire's own layers: smoke behind flames,
## sparks on top.
const ORDER_SMOKE := -2
const ORDER_FLAME := 0
const ORDER_SPARK := 1

static var _materials := {}
static var _meshes := {}
static var _recipes := {}
static var _textures := {}


# --- materials -------------------------------------------------------------------------

## The roiling fireball (opaque, instance uniforms: seed, heat, dissolve,
## stretch, boil, flow).
static func ball_material() -> ShaderMaterial:
	return _material(&"ball", BALL, {})


## The same fireball in the transparent pass, out of the ink outline's sight:
## for flames that burn open into scraps (each scrap would get an outline).
static func ball_soft_material() -> ShaderMaterial:
	return _material(&"ball_soft", BALL_SOFT, {}, ORDER_FLAME)


static func trail_material() -> ShaderMaterial:
	return _material(&"trail", TRAIL, {}, ORDER_FLAME)


## Round embers that cool from white-hot to ash.
static func ember_material() -> ShaderMaterial:
	return _material(&"ember", MOTE, {&"streak": 0.0, &"heat_start": 1.05, &"heat_end": 0.12}, ORDER_SPARK)


## Sparks for GPU particles: streaks six times as long as they're wide along
## the velocity (needs particle_flag_align_y).
static func spark_material() -> ShaderMaterial:
	return _material(&"spark", MOTE, {&"streak": 6.0, &"heat_start": 1.2, &"heat_end": 0.35, &"flicker": 0.1}, ORDER_SPARK)


## Sparks for FireMotes, which put the streak's full length in the Y axis.
static func spark_cpu_material() -> ShaderMaterial:
	return _material(&"spark_cpu", MOTE, {&"streak": 1.0, &"heat_start": 1.2, &"heat_end": 0.35, &"flicker": 0.1}, ORDER_SPARK)


static func smoke_material() -> ShaderMaterial:
	return _material(&"smoke", SMOKE, {}, ORDER_SMOKE)


## Thinner smoke, for wisps that must not hide what's behind them.
static func smoke_thin_material() -> ShaderMaterial:
	return _material(&"smoke_thin", SMOKE, {&"opacity": 0.42, &"glow_time": 0.25}, ORDER_SMOKE)


## Ash smoke off dying embers on the ground: no fire glow underneath (a
## glowing underside on the floor reads as an orange lump, not smoke).
static func smoke_ash_material() -> ShaderMaterial:
	return _material(&"smoke_ash", SMOKE, {&"opacity": 0.42, &"glow_time": 0.0, &"swell": 1.0}, ORDER_SMOKE)


static func ring_material() -> ShaderMaterial:
	return _material(&"ring", RING, {}, ORDER_FLAME)


static func flash_material() -> ShaderMaterial:
	return _material(&"flash", FLASH, {}, ORDER_SPARK)


static func tongue_material() -> ShaderMaterial:
	return _material(&"tongue", TONGUE, {}, ORDER_FLAME)


## The ember bed, for an area of `size` metres.
static func bed_material(size: Vector2) -> ShaderMaterial:
	var key := StringName("bed_%d_%d" % [roundi(size.x * 100.0), roundi(size.y * 100.0)])
	return _material(key, BED, {&"size": size}, ORDER_SMOKE - 1)


static func _material(key: StringName, shader: Shader, params: Dictionary, priority := 0) -> ShaderMaterial:
	if _materials.has(key):
		return _materials[key]
	var material := ShaderMaterial.new()
	material.shader = shader
	material.render_priority = priority
	for param: StringName in params:
		material.set_shader_parameter(param, params[param])
	_materials[key] = material
	return material


# --- meshes ----------------------------------------------------------------------------

## Unit sphere (radius 1) for fireballs.
static func sphere(detailed := false) -> SphereMesh:
	var key := &"sphere_hi" if detailed else &"sphere_lo"
	if not _meshes.has(key):
		var mesh := SphereMesh.new()
		mesh.radius = 1.0
		mesh.height = 2.0
		mesh.radial_segments = 32 if detailed else 20
		mesh.rings = 16 if detailed else 10
		_meshes[key] = mesh
	return _meshes[key]


## 1x1 quad facing +Z, centred (billboards, motes).
static func quad() -> QuadMesh:
	if not _meshes.has(&"quad"):
		var mesh := QuadMesh.new()
		mesh.size = Vector2.ONE
		_meshes[&"quad"] = mesh
	return _meshes[&"quad"]


## 1x1 quad standing on its bottom edge (flame tongues).
static func standing_quad() -> QuadMesh:
	if not _meshes.has(&"standing_quad"):
		var mesh := QuadMesh.new()
		mesh.size = Vector2.ONE
		mesh.center_offset = Vector3(0.0, 0.5, 0.0)
		_meshes[&"standing_quad"] = mesh
	return _meshes[&"standing_quad"]


## 2x2 plane in local XZ (rings).
static func plane() -> PlaneMesh:
	if not _meshes.has(&"plane"):
		var mesh := PlaneMesh.new()
		mesh.size = Vector2(2.0, 2.0)
		_meshes[&"plane"] = mesh
	return _meshes[&"plane"]


## A particle draw pass: a quad carrying `material`.
static func draw_pass(material: Material) -> QuadMesh:
	var key := StringName("pass_%d" % material.get_instance_id())
	if not _meshes.has(key):
		var mesh := QuadMesh.new()
		mesh.size = Vector2.ONE
		mesh.material = material
		_meshes[key] = mesh
	return _meshes[key]


# --- building blocks -------------------------------------------------------------------

## A fireball of `radius` metres.
static func ball(radius: float, heat: float, seed := -1.0, detailed := false) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.mesh = sphere(detailed)
	mesh.material_override = ball_material()
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.scale = Vector3.ONE * radius
	mesh.set_instance_shader_parameter(&"seed", seed if seed >= 0.0 else randf() * 100.0)
	mesh.set_instance_shader_parameter(&"heat", heat)
	return mesh


## A flat quad effect (ring, flash) with its own instance seed.
static func card(mesh: Mesh, material: Material) -> MeshInstance3D:
	var card_mesh := MeshInstance3D.new()
	card_mesh.mesh = mesh
	card_mesh.material_override = material
	card_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	card_mesh.set_instance_shader_parameter(&"seed", randf() * 100.0)
	card_mesh.set_instance_shader_parameter(&"progress", 0.0)
	return card_mesh


static func light(energy: float, reach: float) -> OmniLight3D:
	var lamp := OmniLight3D.new()
	lamp.light_color = LIGHT
	lamp.light_energy = energy
	lamp.omni_range = reach
	lamp.omni_attenuation = 1.4
	lamp.shadow_enabled = false
	return lamp


## A GPU particle system from a recipe (see recipe()), drawn with
## `material`. World-space; bursts free with their effect's root.
static func particles(process: ParticleProcessMaterial, material: Material, amount: int, lifetime: float,
		one_shot := true, explosiveness := 1.0) -> GPUParticles3D:
	var system := GPUParticles3D.new()
	system.process_material = process
	system.draw_pass_1 = draw_pass(material)
	system.amount = amount
	system.lifetime = lifetime
	system.one_shot = one_shot
	system.explosiveness = explosiveness
	system.local_coords = false
	system.fixed_fps = 0
	system.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	system.visibility_aabb = AABB(Vector3(-5.0, -5.0, -5.0), Vector3(10.0, 10.0, 10.0))
	if material.render_priority == ORDER_SMOKE or material.render_priority == ORDER_SMOKE - 1:
		system.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	system.emitting = true
	return system


## A basis whose Y axis is `normal` (for effects laid on a surface), spun
## randomly about it.
static func basis_from_normal(normal: Vector3) -> Basis:
	var y := normal.normalized() if normal.length() > 0.001 else Vector3.UP
	var reference := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := reference.cross(y).normalized()
	var basis := Basis(x, y, x.cross(y))
	return basis.rotated(y, randf() * TAU)


## Frees `node` after `seconds` (the node must be in the tree).
static func free_after(node: Node, seconds: float) -> void:
	var tween := node.create_tween()
	tween.tween_interval(seconds)
	tween.tween_callback(node.queue_free)


static func random_unit() -> Vector3:
	var v := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
	while v.length_squared() > 1.0 or v.length_squared() < 0.0001:
		v = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
	return v.normalized()


# --- particle recipes ------------------------------------------------------------------

## A shared particle process material by name. Directions are local +Y: the
## surface normal for bursts, the aim for muzzle sprays.
static func recipe(key: StringName) -> ParticleProcessMaterial:
	if _recipes.has(key):
		return _recipes[key]
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3.UP
	match key:
		&"burst_sparks":
			# out of the surface (local +Y), falling
			m.spread = 70.0
			m.initial_velocity_min = 6.0
			m.initial_velocity_max = 14.0
			m.gravity = Vector3(0.0, -14.0, 0.0)
			m.damping_min = 2.0
			m.damping_max = 5.0
			m.scale_min = 0.03
			m.scale_max = 0.055
			m.particle_flag_align_y = true
		&"burst_embers":
			m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			m.emission_sphere_radius = 0.35
			m.spread = 110.0
			m.initial_velocity_min = 1.5
			m.initial_velocity_max = 5.5
			m.gravity = Vector3(0.0, 1.4, 0.0)
			m.damping_min = 2.0
			m.damping_max = 4.0
			m.scale_min = 0.04
			m.scale_max = 0.075
			m.turbulence_enabled = true
			m.turbulence_noise_strength = 1.4
			m.turbulence_noise_scale = 1.6
			m.turbulence_influence_min = 0.05
			m.turbulence_influence_max = 0.15
		&"burst_smoke":
			m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			m.emission_sphere_radius = 0.5
			m.spread = 70.0
			m.initial_velocity_min = 0.6
			m.initial_velocity_max = 1.8
			m.gravity = Vector3(0.0, 1.1, 0.0)
			m.damping_min = 1.5
			m.damping_max = 2.5
			m.angle_min = 0.0
			m.angle_max = 360.0
			m.scale_min = 0.5
			m.scale_max = 0.8
		&"muzzle_sparks":
			# a cone along local +Y
			m.spread = 28.0
			m.initial_velocity_min = 5.0
			m.initial_velocity_max = 11.0
			m.gravity = Vector3(0.0, -8.0, 0.0)
			m.damping_min = 3.0
			m.damping_max = 6.0
			m.scale_min = 0.022
			m.scale_max = 0.04
			m.particle_flag_align_y = true
		&"muzzle_smoke":
			m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			m.emission_sphere_radius = 0.12
			m.spread = 40.0
			m.initial_velocity_min = 0.6
			m.initial_velocity_max = 1.5
			m.gravity = Vector3(0.0, 1.2, 0.0)
			m.damping_min = 2.5
			m.damping_max = 3.5
			m.angle_min = 0.0
			m.angle_max = 360.0
			m.scale_min = 0.16
			m.scale_max = 0.26
		&"fizzle_smoke":
			m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			m.emission_sphere_radius = 0.2
			m.spread = 180.0
			m.initial_velocity_min = 0.3
			m.initial_velocity_max = 1.0
			m.gravity = Vector3(0.0, 0.8, 0.0)
			m.damping_min = 1.5
			m.damping_max = 2.5
			m.angle_min = 0.0
			m.angle_max = 360.0
			m.scale_min = 0.22
			m.scale_max = 0.38
		&"fizzle_embers":
			m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			m.emission_sphere_radius = 0.2
			m.spread = 180.0
			m.initial_velocity_min = 0.4
			m.initial_velocity_max = 1.8
			m.gravity = Vector3(0.0, -1.5, 0.0)
			m.damping_min = 1.0
			m.damping_max = 2.0
			m.scale_min = 0.025
			m.scale_max = 0.045
	_recipes[key] = m
	return m


## A recipe for an emitter spread over a box (Flame Wall): `extents` are half
## sizes in the emitter's space. Cached per shape.
static func box_recipe(base: StringName, extents: Vector3) -> ParticleProcessMaterial:
	var key := StringName("%s_%d_%d_%d" % [base, roundi(extents.x * 100.0), roundi(extents.y * 100.0), roundi(extents.z * 100.0)])
	if _recipes.has(key):
		return _recipes[key]
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = extents
	m.direction = Vector3.UP
	match base:
		&"wall_embers":
			m.spread = 18.0
			m.initial_velocity_min = 1.4
			m.initial_velocity_max = 3.4
			m.gravity = Vector3(0.0, 0.4, 0.0)
			m.damping_min = 0.3
			m.damping_max = 0.8
			m.scale_min = 0.03
			m.scale_max = 0.06
			m.turbulence_enabled = true
			m.turbulence_noise_strength = 1.6
			m.turbulence_noise_scale = 1.3
			m.turbulence_influence_min = 0.05
			m.turbulence_influence_max = 0.14
		&"wall_sparks":
			m.spread = 30.0
			m.initial_velocity_min = 4.0
			m.initial_velocity_max = 8.0
			m.gravity = Vector3(0.0, -5.0, 0.0)
			m.damping_min = 1.0
			m.damping_max = 2.0
			m.scale_min = 0.022
			m.scale_max = 0.04
			m.particle_flag_align_y = true
		&"wall_erupt":
			m.spread = 35.0
			m.initial_velocity_min = 5.0
			m.initial_velocity_max = 12.0
			m.gravity = Vector3(0.0, -9.0, 0.0)
			m.damping_min = 1.0
			m.damping_max = 2.5
			m.scale_min = 0.03
			m.scale_max = 0.055
			m.particle_flag_align_y = true
		&"wall_smoke":
			m.spread = 15.0
			m.initial_velocity_min = 1.0
			m.initial_velocity_max = 1.8
			m.gravity = Vector3(0.0, 0.4, 0.0)
			m.damping_min = 0.2
			m.damping_max = 0.5
			m.angle_min = 0.0
			m.angle_max = 360.0
			m.scale_min = 0.35
			m.scale_max = 0.6
		&"ash_embers":
			# the dying wall: slow embers drifting up off the scorch
			m.spread = 25.0
			m.initial_velocity_min = 0.4
			m.initial_velocity_max = 1.6
			m.gravity = Vector3(0.0, 0.5, 0.0)
			m.damping_min = 0.5
			m.damping_max = 1.0
			m.scale_min = 0.025
			m.scale_max = 0.05
			m.turbulence_enabled = true
			m.turbulence_noise_strength = 1.2
			m.turbulence_noise_scale = 1.5
			m.turbulence_influence_min = 0.05
			m.turbulence_influence_max = 0.12
		&"ash_smoke":
			m.spread = 12.0
			m.initial_velocity_min = 0.8
			m.initial_velocity_max = 1.5
			m.gravity = Vector3(0.0, 0.5, 0.0)
			m.damping_min = 0.3
			m.damping_max = 0.6
			m.angle_min = 0.0
			m.angle_max = 360.0
			m.scale_min = 0.22
			m.scale_max = 0.4
	_recipes[key] = m
	return m


## A GPU particle system emitting over a box (see box_recipe).
static func box_particles(base: StringName, extents: Vector3, material: Material, amount: int,
		lifetime: float, one_shot := false, explosiveness := 0.0) -> GPUParticles3D:
	return particles(box_recipe(base, extents), material, amount, lifetime, one_shot, explosiveness)


# --- scorch textures ---------------------------------------------------------------------

## A round scorch: charred, ragged and splattered (albedo with alpha).
static func scorch_albedo() -> Texture2D:
	_ensure_scorch(&"round")
	return _textures[&"round_albedo"]


## Glowing cracks for the round scorch (for the decal's emission).
static func scorch_glow() -> Texture2D:
	_ensure_scorch(&"round")
	return _textures[&"round_glow"]


## A long scorched strip with ragged edges (the Flame Wall's burn).
static func strip_albedo() -> Texture2D:
	_ensure_scorch(&"strip")
	return _textures[&"strip_albedo"]


static func strip_glow() -> Texture2D:
	_ensure_scorch(&"strip")
	return _textures[&"strip_glow"]


## Paints a scorch mark once: hard-stepped char tones (comic, like the rest
## of the fire) with ragged edges, and a second image of glowing cracks.
static func _ensure_scorch(kind: StringName) -> void:
	if _textures.has(StringName("%s_albedo" % kind)):
		return
	var strip := kind == &"strip"
	var w := 256 if strip else 128
	var h := 40 if strip else 128
	var blotch := FastNoiseLite.new()
	blotch.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	blotch.seed = 11 if strip else 7
	blotch.frequency = 0.045
	blotch.fractal_octaves = 3
	var cells := FastNoiseLite.new()
	cells.noise_type = FastNoiseLite.TYPE_CELLULAR
	cells.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	cells.frequency = 0.075
	cells.fractal_type = FastNoiseLite.FRACTAL_NONE
	cells.seed = 5
	var albedo := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var glow := Image.create(w, h, false, Image.FORMAT_RGB8)
	var core := Color(0.045, 0.03, 0.035, 0.93)
	var char_mid := Color(0.1, 0.055, 0.05, 0.85)
	var soot := Color(0.16, 0.1, 0.1, 0.6)
	for y in h:
		for x in w:
			var u := (x + 0.5) / w * 2.0 - 1.0
			var v := (y + 0.5) / h * 2.0 - 1.0
			var b := blotch.get_noise_2d(x, y)
			var d: float
			if strip:
				# ragged long edges, rounded ends
				var edge := 0.7 + 0.22 * blotch.get_noise_1d(x * 1.7 + 300.0)
				var end := 0.93 + 0.06 * blotch.get_noise_1d(y * 4.0 + 900.0)
				d = maxf(absf(v) / edge, pow(absf(u) / end, 6.0))
			else:
				var angle := atan2(v, u)
				var spokes := maxf(blotch.get_noise_1d(angle * 40.0 + 50.0), 0.0)
				var reach := 0.66 + 0.14 * blotch.get_noise_1d(angle * 9.0) + 0.35 * spokes * spokes
				d = sqrt(u * u + v * v) / minf(reach, 0.98)
			d += b * 0.12
			if d >= 1.0:
				albedo.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))
				continue
			var tone := soot
			if d < 0.42:
				tone = core
			elif d < 0.78:
				tone = char_mid
			albedo.set_pixel(x, y, tone)
			var crack := cells.get_noise_2d(x, y)
			var hot := 0.0
			if d < 0.7 and crack < -0.82:
				hot = 1.0 - d / 0.7
			if d < 0.22:
				hot = maxf(hot, 0.6)
			glow.set_pixel(x, y, Color(1.0, 0.42, 0.1) * hot)
	_textures[StringName("%s_albedo" % kind)] = ImageTexture.create_from_image(albedo)
	_textures[StringName("%s_glow" % kind)] = ImageTexture.create_from_image(glow)
