@tool
class_name ArenaBuilder
extends Node3D
## Builds the greybox training arena from the layout tables below, along with
## its lighting and environment. It's a @tool script, so the arena also shows
## up when you open arena.tscn in the editor. Reshape the arena by editing
## BLOCKS; everything generated lives under a "Generated" child that's
## rebuilt on load and never saved.
##
## Layout: 40x40m. Player spawn is south (+Z), bot spawn north (-Z). The ledge
## sits on the east side with a ramp up from the south.

const SPAWNS := {
	0: [Vector3(0.0, 0.0, 17.0), 0.0],
	1: [Vector3(0.0, 0.0, -17.0), PI],
}
const ORB_SPOTS: Array[Vector3] = [Vector3(17.5, 3.0, -3.0), Vector3(-17.0, 0.0, 0.0)]

# [centre, size, material, rotation in degrees (optional)]
const BLOCKS := [
	[Vector3(0, -0.5, 0), Vector3(46, 1, 46), &"floor"],
	[Vector3(0, 3, -22.5), Vector3(46, 6, 1), &"wall"],
	[Vector3(0, 3, 22.5), Vector3(46, 6, 1), &"wall"],
	[Vector3(-22.5, 3, 0), Vector3(1, 6, 44), &"wall"],
	[Vector3(22.5, 3, 0), Vector3(1, 6, 44), &"wall"],
	# cover pillars
	[Vector3(-7, 2.5, -6), Vector3(1.6, 5, 1.6), &"pillar"],
	[Vector3(7, 2.5, 6), Vector3(1.6, 5, 1.6), &"pillar"],
	[Vector3(-7, 2.5, 6), Vector3(1.6, 5, 1.6), &"pillar"],
	[Vector3(6, 2.5, -7), Vector3(1.6, 5, 1.6), &"pillar"],
	# waist-high walls: block bolts, not blades
	[Vector3(0, 0.6, 12), Vector3(6, 1.2, 0.8), &"low_wall"],
	[Vector3(0, 0.6, -12), Vector3(6, 1.2, 0.8), &"low_wall"],
	[Vector3(-14, 0.6, -7), Vector3(0.8, 1.2, 5), &"low_wall"],
	[Vector3(-14, 0.6, 7), Vector3(0.8, 1.2, 5), &"low_wall"],
	# the ledge (top at y = 3) and its ramp, rising north along the east wall
	[Vector3(17.5, 1.5, -1), Vector3(9, 3, 12), &"ledge"],
	[Vector3(19.5, 1.266, 8.912), Vector3(4, 0.5, 8.544), &"ramp", Vector3(20.556, 0, 0)],
	# team banners
	[Vector3(0, 3.6, 21.95), Vector3(3.2, 4.2, 0.1), &"banner_0", Vector3.ZERO, false],
	[Vector3(0, 3.6, -21.95), Vector3(3.2, 4.2, 0.1), &"banner_1", Vector3.ZERO, false],
	# glowing crystals in the corners
	[Vector3(-20.5, 1.2, -20.5), Vector3(1.1, 2.6, 1.1), &"crystal", Vector3(0, 45, 12), false],
	[Vector3(20.5, 1.2, -20.5), Vector3(1.1, 2.6, 1.1), &"crystal", Vector3(0, 45, -12), false],
	[Vector3(-20.5, 1.2, 20.5), Vector3(1.1, 2.6, 1.1), &"crystal", Vector3(0, 45, -12), false],
	[Vector3(20.5, 1.2, 20.5), Vector3(1.1, 2.6, 1.1), &"crystal", Vector3(0, 45, 12), false],
]
const TORCHES: Array[Vector3] = [
	Vector3(-10, 3.4, -21.7), Vector3(10, 3.4, -21.7),
	Vector3(-10, 3.4, 21.7), Vector3(10, 3.4, 21.7),
	Vector3(-21.7, 3.4, -10), Vector3(-21.7, 3.4, 10),
]

var _materials := {}


func _ready() -> void:
	var old := get_node_or_null(^"Generated")
	if old:
		remove_child(old)
		old.free()
	var root := Node3D.new()
	root.name = "Generated"
	add_child(root)
	_build_materials()
	for block: Array in BLOCKS:
		var rot: Vector3 = block[3] if block.size() > 3 else Vector3.ZERO
		var solid: bool = block[4] if block.size() > 4 else true
		_add_block(root, block[0], block[1], _materials[block[2]], rot, solid)
	for spot in TORCHES:
		_add_torch(root, spot)
	_add_lighting(root)


func spawn_transform(team: int) -> Transform3D:
	var spawn: Array = SPAWNS.get(team, SPAWNS[0])
	return Transform3D(Basis(Vector3.UP, spawn[1]), spawn[0])


func _build_materials() -> void:
	_materials = {
		&"floor": ToonMaterials.make(Color(0.26, 0.23, 0.31), {&"world_grid": true, &"grid_size": 2.0, &"grunge_strength": 0.35}),
		&"wall": ToonMaterials.make(Color(0.45, 0.21, 0.25), {&"world_grid": true, &"grid_size": 1.5, &"grunge_strength": 0.5}),
		&"pillar": ToonMaterials.make(Color(0.8, 0.67, 0.48), {&"grunge_strength": 0.3}),
		&"low_wall": ToonMaterials.make(Color(0.52, 0.4, 0.66), {&"grunge_strength": 0.3}),
		&"ledge": ToonMaterials.make(Color(0.27, 0.47, 0.37), {&"world_grid": true, &"grid_size": 1.5, &"grunge_strength": 0.3}),
		&"ramp": ToonMaterials.make(Color(0.34, 0.53, 0.42), {&"grunge_strength": 0.25}),
		&"banner_0": ToonMaterials.make(Color(0.1, 0.72, 0.7), {&"glow_color": Color(0.1, 0.72, 0.7), &"glow_energy": 0.25}),
		&"banner_1": ToonMaterials.make(Color(1.0, 0.45, 0.15), {&"glow_color": Color(1.0, 0.45, 0.15), &"glow_energy": 0.25}),
		&"crystal": ToonMaterials.make(Color(0.95, 0.3, 0.85), {&"glow_color": Color(0.95, 0.3, 0.85), &"glow_energy": 1.6}),
	}


func _add_block(root: Node3D, centre: Vector3, size: Vector3, material: Material, rot_deg: Vector3, solid: bool) -> void:
	var box := BoxMesh.new()
	box.size = size
	var mesh := MeshInstance3D.new()
	mesh.mesh = box
	mesh.material_override = material
	if not solid:
		mesh.position = centre
		mesh.rotation_degrees = rot_deg
		root.add_child(mesh)
		return
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = centre
	body.rotation_degrees = rot_deg
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	body.add_child(mesh)
	root.add_child(body)


func _add_torch(root: Node3D, at: Vector3) -> void:
	var torch := Node3D.new()
	torch.position = at
	root.add_child(torch)
	var bracket := MeshInstance3D.new()
	var bracket_mesh := BoxMesh.new()
	bracket_mesh.size = Vector3(0.25, 0.6, 0.25)
	bracket.mesh = bracket_mesh
	bracket.material_override = ToonMaterials.make(Color(0.2, 0.16, 0.14))
	torch.add_child(bracket)
	var flame := MeshInstance3D.new()
	var flame_mesh := SphereMesh.new()
	flame_mesh.radius = 0.2
	flame_mesh.height = 0.55
	flame.mesh = flame_mesh
	flame.position = Vector3(0, 0.45, 0)
	flame.material_override = ToonMaterials.make_vfx(Color(1.0, 0.55, 0.15), 4.0)
	torch.add_child(flame)
	var light := OmniLight3D.new()
	light.position = Vector3(0, 0.6, 0) + (Vector3.ZERO - at).normalized() * Vector3(1, 0, 1) * 0.6
	light.light_color = Color(1.0, 0.6, 0.3)
	light.light_energy = 2.2
	light.omni_range = 9.0
	torch.add_child(light)


func _add_lighting(root: Node3D) -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-48.0, 38.0, 0.0)
	sun.light_color = Color(1.0, 0.84, 0.66)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 70.0
	root.add_child(sun)

	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.11, 0.08, 0.24)
	sky_material.sky_horizon_color = Color(0.88, 0.45, 0.4)
	sky_material.ground_horizon_color = Color(0.42, 0.22, 0.28)
	sky_material.ground_bottom_color = Color(0.06, 0.04, 0.09)
	var sky := Sky.new()
	sky.sky_material = sky_material

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.38, 0.62)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.75
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 1.1
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.25
	env.adjustment_contrast = 1.08
	env.fog_enabled = true
	env.fog_light_color = Color(0.36, 0.26, 0.46)
	env.fog_density = 0.006
	env.fog_sky_affect = 0.3
	var world_env := WorldEnvironment.new()
	world_env.name = "Environment"
	world_env.environment = env
	root.add_child(world_env)
