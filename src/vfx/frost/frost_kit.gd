class_name FrostKit
extends RefCounted
## Frost's shared pieces: the palette, the crystal meshes (built once from
## code) and materials, and the small fire-and-forget parts FrostFx builds
## its effects from (flash, light, shock ring, frost patch). Cosmetic only:
## everything here reads nothing back and frees itself.

const COLOR := Color(0.35, 0.8, 1.0)
const PALE := Color(0.82, 0.96, 1.0)
const WHITE_VIOLET := Color(0.86, 0.78, 1.0)

const CRYSTAL_SHADER := preload("res://src/vfx/frost/frost_crystal.gdshader")
const GLASS_SHADER := preload("res://src/vfx/frost/frost_crystal_glass.gdshader")
const PUFF_SHADER := preload("res://src/vfx/frost/frost_puff.gdshader")
const GLINT_SHADER := preload("res://src/vfx/frost/frost_glint.gdshader")
const FLASH_SHADER := preload("res://src/vfx/frost/frost_flash.gdshader")
const RING_SHADER := preload("res://src/vfx/frost/frost_ring.gdshader")
const PATCH_SHADER := preload("res://src/vfx/frost/frost_patch.gdshader")
const TRAIL_SHADER := preload("res://src/vfx/frost/frost_trail.gdshader")
const HALO_SHADER := preload("res://src/vfx/frost/frost_halo.gdshader")

## Ice Spike length, tip to tail (the spurs reach a little further back).
const SPIKE_TIP := -0.62
const SPIKE_TAIL := 0.42

static var _cache := {}


# --- meshes ---------------------------------------------------------------

## The Ice Spike: one long six-sided crystal, its point at -Z, with an
## antiprism waist so every facet is a sharp triangle, and three smaller
## crystals flaring back from its rear like fletching. About 1.15 m long.
static func spike_mesh() -> ArrayMesh:
	if _cache.has(&"spike"):
		return _cache[&"spike"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var faces := []
	var sides := 6
	var radius := 0.155
	var tip := Vector3(0.0, 0.0, SPIKE_TIP)
	var tail := Vector3(0.01, -0.008, SPIKE_TAIL)
	var waist: Array[Vector3] = []
	var hips: Array[Vector3] = []
	for k in sides:
		var angle := TAU * k / sides + rng.randf_range(-0.12, 0.12)
		var r := radius * rng.randf_range(0.88, 1.1)
		waist.append(Vector3(cos(angle) * r, sin(angle) * r, -0.1 + rng.randf_range(-0.03, 0.03)))
		var angle_b := angle + PI / sides
		var r_b := radius * rng.randf_range(0.72, 0.84)
		hips.append(Vector3(cos(angle_b) * r_b, sin(angle_b) * r_b, 0.2 + rng.randf_range(-0.03, 0.03)))
	for k in sides:
		var n := (k + 1) % sides
		_face(faces, tip, waist[k], waist[n], Vector3(0.0, 0.0, -0.15))
		_face(faces, waist[k], hips[k], waist[n], Vector3(0.0, 0.0, 0.05))
		_face(faces, waist[n], hips[k], hips[n], Vector3(0.0, 0.0, 0.05))
		_face(faces, hips[k], tail, hips[n], Vector3(0.0, 0.0, 0.25))
	for s in 3:
		var phi := TAU * s / 3.0 + 0.5 + rng.randf_range(-0.25, 0.25)
		var root := Vector3(cos(phi) * radius * 0.5, sin(phi) * radius * 0.5, rng.randf_range(0.0, 0.14))
		var tilt := deg_to_rad(rng.randf_range(24.0, 34.0))
		var axis := Vector3(cos(phi) * sin(tilt), sin(phi) * sin(tilt), cos(tilt))
		_crystal(faces, root, axis, rng.randf_range(0.3, 0.42), radius * rng.randf_range(0.36, 0.44), 4, rng, 0.14, 0.36)
	var mesh := _build(faces)
	_cache[&"spike"] = mesh
	return mesh


## A small irregular ice chunk, pointed at both ends, about 1 unit long
## (scaled per instance). A few variants so bursts don't look stamped.
static func chunk_mesh(variant: int) -> ArrayMesh:
	var key := StringName("chunk_%d" % variant)
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + variant * 31
	var faces := []
	var sides := 4 + variant % 2
	_crystal(faces, Vector3(0.0, -0.45, 0.0), Vector3.UP, 1.0, rng.randf_range(0.3, 0.42), sides, rng,
			rng.randf_range(0.35, 0.6), rng.randf_range(0.3, 0.55))
	var mesh := _build(faces)
	_cache[key] = mesh
	return mesh


## A hexagonal ice crystal standing on its base at the origin, pointing up
## +Y: radius 1, height 1 (scaled per instance), with a stub below the base
## so it can sit buried in a surface.
static func growth_mesh() -> ArrayMesh:
	if _cache.has(&"growth"):
		return _cache[&"growth"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var faces := []
	var sides := 6
	var low: Array[Vector3] = []
	var high: Array[Vector3] = []
	for k in sides:
		var angle := TAU * k / sides + rng.randf_range(-0.1, 0.1)
		var r := rng.randf_range(0.85, 1.08)
		low.append(Vector3(cos(angle) * r, 0.0, sin(angle) * r))
		high.append(Vector3(cos(angle) * r * 0.86, 0.64 + rng.randf_range(-0.05, 0.05), sin(angle) * r * 0.86))
	var apex := Vector3(0.08, 1.0, -0.05)
	var stub := Vector3(0.0, -0.3, 0.0)
	var inside := Vector3(0.0, 0.4, 0.0)
	for k in sides:
		var n := (k + 1) % sides
		# the prism side is one quad: hide the diagonal's edge line
		_face(faces, low[k], high[k], high[n], inside, 4)
		_face(faces, low[k], high[n], low[n], inside, 1)
		_face(faces, apex, high[k], high[n], inside)
		_face(faces, stub, low[n], low[k], Vector3(0.0, -0.05, 0.0))
	var mesh := _build(faces)
	_cache[&"growth"] = mesh
	return mesh


## A 1x1 quad for camera-facing billboards.
static func quad_mesh() -> QuadMesh:
	if not _cache.has(&"quad"):
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE
		_cache[&"quad"] = quad
	return _cache[&"quad"]


## A flat 2x2 plane in XZ for shock rings (scaled to the ring's radius).
static func disc_mesh() -> PlaneMesh:
	if not _cache.has(&"disc"):
		var plane := PlaneMesh.new()
		plane.size = Vector2(2.0, 2.0)
		_cache[&"disc"] = plane
	return _cache[&"disc"]


## A unit box for the frost patch decal.
static func box_mesh() -> BoxMesh:
	if not _cache.has(&"box"):
		var box := BoxMesh.new()
		box.size = Vector3.ONE
		_cache[&"box"] = box
	return _cache[&"box"]


## Adds a pointed crystal along `axis` from `base` to `faces`: `sides`
## facets around, widest at `shoulder` of its length, with a short point
## (`butt` of its length) behind the base.
static func _crystal(faces: Array, base: Vector3, axis: Vector3, length: float, radius: float, sides: int,
		rng: RandomNumberGenerator, butt := 0.12, shoulder := 0.34) -> void:
	var u := axis.cross(Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT).normalized()
	var v := axis.cross(u)
	var ring: Array[Vector3] = []
	var phase := rng.randf() * TAU
	for k in sides:
		var angle := phase + TAU * k / sides + rng.randf_range(-0.2, 0.2)
		var r := radius * rng.randf_range(0.8, 1.15)
		ring.append(base + axis * length * shoulder + (u * cos(angle) + v * sin(angle)) * r)
	var tip := base + axis * length
	var bottom := base - axis * length * butt
	var inside := base + axis * length * shoulder
	for k in sides:
		var n := (k + 1) % sides
		_face(faces, tip, ring[k], ring[n], inside)
		_face(faces, bottom, ring[n], ring[k], inside)


## Queues one triangle. `inside` is any point inside the solid (the face is
## turned to face away from it); `hidden` is a bit mask of edges that get no
## edge line (1: a-b, 2: b-c, 4: c-a), for quads split in two.
static func _face(faces: Array, a: Vector3, b: Vector3, c: Vector3, inside: Vector3, hidden := 0) -> void:
	faces.append([a, b, c, inside, hidden])


## Flat-shaded faces -> ArrayMesh. COLOR carries per-edge barycentrics for the
## crystal shader's edge lines: a hidden edge gets 1 in the component that
## would be 0 along it. Godot's front faces wind clockwise.
static func _build(faces: Array) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for face: Array in faces:
		var a: Vector3 = face[0]
		var b: Vector3 = face[1]
		var c: Vector3 = face[2]
		var inside: Vector3 = face[3]
		var hidden: int = face[4]
		var ca := Color(1.0, 0.0, 0.0)
		var cb := Color(0.0, 1.0, 0.0)
		var cc := Color(0.0, 0.0, 1.0)
		if hidden & 1:  # a-b: the c component is 0 along it
			ca.b = 1.0
			cb.b = 1.0
		if hidden & 2:  # b-c: the a component
			cb.r = 1.0
			cc.r = 1.0
		if hidden & 4:  # c-a: the b component
			cc.g = 1.0
			ca.g = 1.0
		var cross := (b - a).cross(c - a)
		if cross.dot((a + b + c) / 3.0 - inside) > 0.0:
			# counter-clockwise from outside: swap to clockwise
			var t := b
			b = c
			c = t
			var tc := cb
			cb = cc
			cc = tc
			cross = -cross
		var normal := -cross.normalized()
		vertices.append_array([a, b, c])
		normals.append_array([normal, normal, normal])
		colors.append_array([ca, cb, cc])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# --- materials --------------------------------------------------------------

## The Ice Spike's own ice: a white-hot core glowing down its length.
static func spike_material() -> ShaderMaterial:
	if not _cache.has(&"m_spike"):
		var material := _crystal_material(false)
		material.set_shader_parameter(&"core_energy", 2.6)
		material.set_shader_parameter(&"core_axis", Vector3(0.0, 0.0, 1.0))
		material.set_shader_parameter(&"core_radius", 0.052)
		material.set_shader_parameter(&"core_span", Vector2(-0.52, 0.3))
		_cache[&"m_spike"] = material
	return _cache[&"m_spike"]


## Flying ice chunks (MultiMesh: per-instance dissolve/flash/violet/seed).
## Glass by default: small bits under an ink outline turn into black specks.
static func chunk_material(glass := true) -> ShaderMaterial:
	var key := &"m_chunk_glass" if glass else &"m_chunk"
	if not _cache.has(key):
		var material := _crystal_material(true, glass)
		material.set_shader_parameter(&"edge_width", 0.08)
		_cache[key] = material
	return _cache[key]


## Crystal growths (MultiMesh), each with a cold core up its middle. `glass`
## for small ones (no ink outline).
static func growth_material(glass := false) -> ShaderMaterial:
	var key := &"m_growth_glass" if glass else &"m_growth"
	if not _cache.has(key):
		var material := _crystal_material(true, glass)
		material.set_shader_parameter(&"core_energy", 1.9)
		material.set_shader_parameter(&"core_axis", Vector3(0.0, 1.0, 0.0))
		material.set_shader_parameter(&"core_radius", 0.42)
		material.set_shader_parameter(&"core_span", Vector2(-0.1, 0.95))
		material.set_shader_parameter(&"dissolve_scale", 3.2)
		_cache[key] = material
	return _cache[key]


static func _crystal_material(multimesh: bool, glass := false) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = GLASS_SHADER if glass else CRYSTAL_SHADER
	material.set_shader_parameter(&"use_custom", multimesh)
	return material


static func puff_material() -> ShaderMaterial:
	if not _cache.has(&"m_puff"):
		var material := ShaderMaterial.new()
		material.shader = PUFF_SHADER
		_cache[&"m_puff"] = material
	return _cache[&"m_puff"]


## Glitter (MultiMesh) or, with `single`, one glint driven by instance uniforms.
static func glint_material(single := false) -> ShaderMaterial:
	var key := &"m_glint_1" if single else &"m_glint"
	if not _cache.has(key):
		var material := ShaderMaterial.new()
		material.shader = GLINT_SHADER
		material.set_shader_parameter(&"use_custom", not single)
		_cache[key] = material
	return _cache[key]


static func trail_material() -> ShaderMaterial:
	return _simple(&"m_trail", TRAIL_SHADER)


## The cold glow behind the Ice Spike (see frost_halo.gdshader).
static func halo_material() -> ShaderMaterial:
	return _simple(&"m_halo", HALO_SHADER)


static func _simple(key: StringName, shader: Shader) -> ShaderMaterial:
	if not _cache.has(key):
		var material := ShaderMaterial.new()
		material.shader = shader
		_cache[key] = material
	return _cache[key]


# --- fire-and-forget parts ---------------------------------------------------

## The white-hot first frames of a frost burst: a camera-facing six-ray ice
## star that snaps out in held beats and fades within `duration`.
static func flash(world: Node, at: Vector3, size: float, duration: float, tint := COLOR, energy := 3.0) -> void:
	var star := MeshInstance3D.new()
	star.mesh = quad_mesh()
	star.material_override = _simple(&"m_flash", FLASH_SHADER)
	star.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	star.set_instance_shader_parameter(&"tint", tint)
	star.set_instance_shader_parameter(&"energy", energy)
	star.set_instance_shader_parameter(&"spin", randf() * TAU)
	world.add_child(star)
	star.global_position = at
	star.scale = Vector3.ONE * size
	var tween := star.create_tween()
	tween.tween_method(func(p: float) -> void: star.set_instance_shader_parameter(&"progress", p), 0.0, 1.0, duration)
	tween.tween_callback(star.queue_free)


## A short cold light flash (no shadows).
static func light(world: Node, at: Vector3, color: Color, energy: float, reach: float, duration: float) -> void:
	var lamp := OmniLight3D.new()
	lamp.light_color = color
	lamp.light_energy = energy
	lamp.omni_range = reach
	lamp.shadow_enabled = false
	world.add_child(lamp)
	lamp.global_position = at
	var tween := lamp.create_tween()
	tween.tween_property(lamp, ^"light_energy", 0.0, duration).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(lamp.queue_free)


## A frost shock ring in the plane facing `normal`: it races out to `radius`
## over `expand` seconds (ease-out), then thins and fades over `linger`. Its
## teeth point outward and their tips touch `radius` exactly.
static func ring(world: Node, at: Vector3, normal: Vector3, radius: float, expand: float, linger: float,
		width := 0.3, teeth := 18.0, violet := 0.0, start := 0.15) -> MeshInstance3D:
	var disc := MeshInstance3D.new()
	disc.mesh = disc_mesh()
	disc.material_override = _simple(&"m_ring", RING_SHADER)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	disc.set_instance_shader_parameter(&"width_m", width)
	disc.set_instance_shader_parameter(&"teeth", teeth)
	disc.set_instance_shader_parameter(&"tooth_m", minf(width * 0.45, radius * 0.05))
	disc.set_instance_shader_parameter(&"violet", violet)
	world.add_child(disc)
	disc.global_transform = Transform3D(basis_facing(normal), at)
	var set_radius := func(r: float) -> void:
		disc.scale = Vector3(r, 1.0, r)
		disc.set_instance_shader_parameter(&"radius_m", r)
	set_radius.call(radius * start)
	var tween := disc.create_tween()
	tween.tween_method(set_radius, radius * start, radius, expand).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_method(func(f: float) -> void: disc.set_instance_shader_parameter(&"fade", f), 0.0, 1.0, linger) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(disc.queue_free)
	return disc


## Frost spreading over the surface at `at` (facing `normal`) out to
## `radius` in `spread` seconds, glowing at first, then melting away so it's
## gone after `lifetime`. A screen-space decal: it paints floors and walls,
## not the air. `rim_heavy` piles the frost at the rim (the Nova) instead
## of the centre.
static func patch(world: Node, at: Vector3, normal: Vector3, radius: float, spread: float, lifetime: float,
		rim_heavy := 0.0, violet := 0.0) -> MeshInstance3D:
	var box := MeshInstance3D.new()
	box.mesh = box_mesh()
	box.material_override = _simple(&"m_patch", PATCH_SHADER)
	box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# drawn before the other frost effects, which then layer over it
	box.sorting_offset = -1.0
	box.set_instance_shader_parameter(&"radius_m", radius)
	box.set_instance_shader_parameter(&"seed", randf() * 10.0)
	box.set_instance_shader_parameter(&"rim_heavy", rim_heavy)
	box.set_instance_shader_parameter(&"violet", violet)
	box.set_instance_shader_parameter(&"grow", 0.0)
	world.add_child(box)
	var thickness := 0.7
	box.global_transform = Transform3D(basis_facing(normal) * Basis.from_scale(Vector3(radius * 2.0, thickness, radius * 2.0)), at)
	var tween := box.create_tween()
	tween.tween_method(func(g: float) -> void: box.set_instance_shader_parameter(&"grow", g), 0.15, 1.0, spread) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.parallel().tween_method(func(g: float) -> void: box.set_instance_shader_parameter(&"glow", g), 1.0, 0.0, lifetime * 0.22)
	var hold := maxf(lifetime * 0.18 - spread, 0.0)
	tween.tween_interval(hold)
	tween.tween_method(func(m: float) -> void: box.set_instance_shader_parameter(&"melt", m), 0.0, 1.0,
			maxf(lifetime - spread - hold, 0.1)).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(box.queue_free)
	return box


# --- helpers ------------------------------------------------------------------

## A basis whose +Y is `up` (any twist around it).
static func basis_facing(up: Vector3) -> Basis:
	var y := up.normalized() if up.length() > 0.001 else Vector3.UP
	var helper := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := helper.cross(y).normalized()
	var z := x.cross(y)
	return Basis(x, y, z)


## The floor height under `at` (the world below it, within `reach`), or
## `fallback` when there's nothing there. A read-only query for cosmetics.
static func floor_below(world: Node, at: Vector3, fallback: float, reach := 6.0) -> float:
	if not is_instance_valid(world) or not world.is_inside_tree() or world.get_viewport() == null:
		return fallback
	var world_3d := world.get_viewport().find_world_3d()
	if world_3d == null:
		return fallback
	var space := world_3d.direct_space_state
	if space == null:
		return fallback
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.05, at + Vector3.DOWN * reach, 1))
	return (hit.position as Vector3).y if hit else fallback


## A random unit vector.
static func random_direction() -> Vector3:
	var z := randf_range(-1.0, 1.0)
	var angle := randf() * TAU
	var r := sqrt(1.0 - z * z)
	return Vector3(r * cos(angle), r * sin(angle), z)


## A random direction within `degrees` of `axis`.
static func random_cone(axis: Vector3, degrees: float) -> Vector3:
	var y := axis.normalized()
	var b := basis_facing(y)
	var cos_max := cos(deg_to_rad(degrees))
	var c := randf_range(cos_max, 1.0)
	var s := sqrt(maxf(1.0 - c * c, 0.0))
	var angle := randf() * TAU
	return (b.x * cos(angle) * s + b.z * sin(angle) * s + y * c).normalized()
