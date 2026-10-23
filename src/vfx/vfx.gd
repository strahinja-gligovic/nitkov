class_name Vfx
extends RefCounted
## Fire-and-forget cosmetic effects. Never called by simulation code paths
## that need determinism; randomness here is purely visual.

const IMPACT := preload("res://src/vfx/impact_star.gdshader")
const SLASH := preload("res://src/vfx/slash_arc.gdshader")

static var _slash_meshes := {}


## A sweeping slash crescent in the swing plane, synced to a strike.
## `origin` is the pivot (attacker's chest), `facing_yaw` the attacker's
## facing. Angles are degrees from straight ahead, positive to the right;
## `tilt` rolls the swing plane around the facing axis (0 = flat
## horizontal, 90 = vertical chop).
static func slash(parent: Node, origin: Vector3, facing_yaw: float, from_deg: float, to_deg: float,
		tilt_deg: float, radius: float, color: Color, duration := 0.2) -> void:
	var arc := MeshInstance3D.new()
	arc.mesh = _slash_mesh(from_deg, to_deg, radius)
	var material := ShaderMaterial.new()
	material.shader = SLASH
	material.set_shader_parameter(&"edge_color", color)
	material.set_shader_parameter(&"core_color", color.lightened(0.7))
	arc.material_override = material
	arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(arc)
	var facing := Basis(Vector3.UP, facing_yaw)
	var roll := Basis(Vector3.FORWARD, deg_to_rad(tilt_deg))
	arc.global_transform = Transform3D(facing * roll, origin)
	var tween := arc.create_tween()
	tween.tween_method(func(p: float) -> void: material.set_shader_parameter(&"progress", p), 0.0, 1.0, duration)
	tween.tween_callback(arc.queue_free)


## Ring segment in the local XZ plane: angle measured from -Z toward +X,
## UV.x along the sweep, UV.y inner to outer radius. Cached per shape.
static func _slash_mesh(from_deg: float, to_deg: float, radius: float) -> ArrayMesh:
	var key := "%d:%d:%d" % [roundi(from_deg), roundi(to_deg), roundi(radius * 100.0)]
	if _slash_meshes.has(key):
		return _slash_meshes[key]
	var segments := 28
	var inner := radius * 0.7
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	for i in segments + 1:
		var u := float(i) / segments
		var angle := deg_to_rad(lerpf(from_deg, to_deg, u))
		var dir := Vector3(sin(angle), 0.0, -cos(angle))
		vertices.append(dir * inner)
		uvs.append(Vector2(u, 0.0))
		vertices.append(dir * radius)
		uvs.append(Vector2(u, 1.0))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLE_STRIP, arrays)
	_slash_meshes[key] = mesh
	return mesh


## A comic impact star that pops and fades at `at`.
static func impact(parent: Node, at: Vector3, color: Color, size := 1.0, duration := 0.22, points := 8.0) -> void:
	var material := ShaderMaterial.new()
	material.shader = IMPACT
	material.set_shader_parameter(&"color", color)
	material.set_shader_parameter(&"points", points)
	material.set_shader_parameter(&"spin", randf() * TAU)
	var quad := QuadMesh.new()
	var star := MeshInstance3D.new()
	star.mesh = quad
	star.material_override = material
	star.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	star.scale = Vector3.ONE * size
	parent.add_child(star)
	star.global_position = at
	var tween := star.create_tween()
	tween.tween_method(func(p: float) -> void: material.set_shader_parameter(&"progress", p), 0.0, 1.0, duration)
	tween.tween_callback(star.queue_free)


## A translucent hemisphere that swells to `radius` and fades (novas).
static func dome(parent: Node, at: Vector3, color: Color, radius: float, duration := 0.45) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 1.0
	sphere.is_hemisphere = true
	var mesh := MeshInstance3D.new()
	mesh.mesh = sphere
	var material := ToonMaterials.make_vfx(color, 1.8)
	material.albedo_color.a = 0.5
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh)
	mesh.global_position = at
	mesh.scale = Vector3.ONE * 0.3
	var tween := mesh.create_tween().set_parallel()
	tween.tween_property(mesh, "scale", Vector3(radius, radius * 0.6, radius), duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(material, "albedo_color:a", 0.0, duration)
	tween.chain().tween_callback(mesh.queue_free)


## Crystal shards bursting outward (novas, Shatter).
static func shards(parent: Node, at: Vector3, color: Color, count := 10, reach := 2.0, duration := 0.5) -> void:
	var crystal := CylinderMesh.new()
	crystal.top_radius = 0.0
	crystal.bottom_radius = 0.09
	crystal.height = 0.5
	crystal.radial_segments = 4
	crystal.rings = 1
	var material := ToonMaterials.make(color.lightened(0.45), {&"glow_color": color, &"glow_energy": 1.4})
	for i in count:
		var shard := MeshInstance3D.new()
		shard.mesh = crystal
		shard.material_override = material
		shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(shard)
		shard.global_position = at
		var direction := Vector3(randf_range(-1, 1), randf_range(0.2, 1.0), randf_range(-1, 1)).normalized()
		shard.look_at(at + direction, Vector3.UP if absf(direction.y) < 0.95 else Vector3.RIGHT)
		shard.rotate_object_local(Vector3.RIGHT, -PI * 0.5)  # cylinder axis (+Y) along the flight direction
		var tween := shard.create_tween().set_parallel()
		tween.tween_property(shard, "global_position", at + direction * reach * randf_range(0.6, 1.0), duration) \
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tween.tween_property(shard, "scale", Vector3.ONE * 0.1, duration).set_ease(Tween.EASE_IN)
		tween.chain().tween_callback(shard.queue_free)


## An expanding glowing ring on the ground (novas, landings, blinks).
static func ring(parent: Node, at: Vector3, color: Color, radius: float, duration := 0.35) -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.85
	torus.outer_radius = 1.0
	torus.rings = 48
	var mesh := MeshInstance3D.new()
	mesh.mesh = torus
	var material := ToonMaterials.make_vfx(color, 3.0)
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh)
	mesh.global_position = at + Vector3.UP * 0.1
	mesh.scale = Vector3(0.2, 0.3, 0.2) * radius
	var tween := mesh.create_tween().set_parallel()
	tween.tween_property(mesh, "scale", Vector3(1.0, 0.3, 1.0) * radius, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(material, "albedo_color:a", 0.0, duration)
	tween.chain().tween_callback(mesh.queue_free)
