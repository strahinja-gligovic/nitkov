class_name FlameWallLook
extends Node3D
## The Flame Wall's fire: a strip of embers, tongues of flame and a few
## lights. Local X runs along the wall, -Z is the way it faces, Y is up from
## the ground. The wall drives set_intensity() (0 out, 1 full blaze).

const FLAME := preload("res://src/vfx/fire/flame.gdshader")

var _flames: Array[ShaderMaterial] = []


func build(spell: FlameWallSpell) -> void:
	var embers := MeshInstance3D.new()
	var strip := BoxMesh.new()
	strip.size = Vector3(spell.length, 0.08, spell.width)
	embers.mesh = strip
	embers.position = Vector3(0.0, 0.04, 0.0)
	embers.material_override = ToonMaterials.make_vfx(Color(1.0, 0.3, 0.08), 2.5, false)
	add_child(embers)
	var tongues := int(spell.length / 0.55)
	for i in tongues:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.38
		cone.height = spell.height
		cone.radial_segments = 8
		cone.rings = 6
		var material := ShaderMaterial.new()
		material.shader = FLAME
		material.set_shader_parameter(&"flame_height", spell.height)
		material.set_shader_parameter(&"seed", randf() * 10.0)
		material.set_shader_parameter(&"intensity", 0.0)
		_flames.append(material)
		var flame := MeshInstance3D.new()
		flame.mesh = cone
		flame.material_override = material
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var along := (float(i) + 0.5) / tongues - 0.5
		flame.position = Vector3(along * spell.length, spell.height * 0.5 * randf_range(0.75, 1.0),
				randf_range(-0.2, 0.2) * spell.width)
		flame.scale = Vector3.ONE * randf_range(0.8, 1.15)
		add_child(flame)
	for i in 3:
		var lamp := ElementFxKit.light(Color(1.0, 0.5, 0.15), 1.4, 5.0)
		lamp.position = Vector3((i - 1) * spell.length * 0.33, 1.0, 0.0)
		add_child(lamp)


func set_intensity(value: float) -> void:
	for material in _flames:
		material.set_shader_parameter(&"intensity", value)
