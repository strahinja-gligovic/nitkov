class_name Vfx
extends RefCounted
## Fire-and-forget cosmetic effects. Never called by simulation code paths
## that need determinism; randomness here is purely visual.

const IMPACT := preload("res://src/vfx/impact_star.gdshader")


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
