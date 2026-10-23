@tool
class_name ToonMaterials
extends RefCounted
## Builds toon materials, and converts imported models to the toon look.

const TOON := preload("res://src/render/toon.gdshader")
const TOON_DOUBLE_SIDED := preload("res://src/render/toon_double_sided.gdshader")
const INK := preload("res://src/render/ink_outline.gdshader")


static func make(color: Color, params := {}) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = TOON
	material.set_shader_parameter(&"albedo", color)
	for key: StringName in params:
		material.set_shader_parameter(key, params[key])
	return material


## Unshaded emissive material for VFX. Additive by default, so it glows through
## the bloom without darkening what's behind it.
static func make_vfx(color: Color, energy := 2.0, additive := true) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.shadow_to_opacity = false
	return material


## Replaces every surface material under `root` with a toon material that keeps
## the original color, texture and sidedness. `tints` maps a source material's
## name to a color multiplied in (e.g. greyscale hair). Returns the new
## materials, e.g. for hit flashes.
static func convert_model(root: Node, tints := {}) -> Array[ShaderMaterial]:
	var created: Array[ShaderMaterial] = []
	var meshes: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.append(root)
	for node in meshes:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			var source := mesh_instance.get_active_material(surface)
			var material := make(Color.WHITE)
			if source is BaseMaterial3D:
				var base := source as BaseMaterial3D
				if base.cull_mode == BaseMaterial3D.CULL_DISABLED:
					material.shader = TOON_DOUBLE_SIDED
				var tint: Color = tints.get(base.resource_name, Color.WHITE)
				material.set_shader_parameter(&"albedo", base.albedo_color * tint)
				if base.albedo_texture:
					material.set_shader_parameter(&"albedo_texture", base.albedo_texture)
					material.set_shader_parameter(&"use_texture", true)
			mesh_instance.set_surface_override_material(surface, material)
			created.append(material)
	return created


## Full-screen ink outline pass; parent it to the active camera.
static func make_ink_pass() -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	var material := ShaderMaterial.new()
	material.shader = INK
	# lowest priority: drawn first among transparent objects, so VFX land on top
	material.render_priority = Material.RENDER_PRIORITY_MIN
	quad.material = material
	var pass_node := MeshInstance3D.new()
	pass_node.name = "InkOutlinePass"
	pass_node.mesh = quad
	pass_node.extra_cull_margin = 16384.0
	pass_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pass_node.position = Vector3(0.0, 0.0, -1.0)
	return pass_node
