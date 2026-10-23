class_name Afterimages
extends Node3D
## Ghost copies of a fighter's pose left along dashes and blinks, so a 4 m
## burst in a quarter second reads as motion and shows the opponent the
## path. A small pool of ghost rigs shares the character's meshes and skins;
## each snapshot copies every bone pose, then fades. Presentation only.

const GHOST_SHADER := preload("res://src/vfx/ghost.gdshader")

var lifetime := 0.25

var _source: Skeleton3D
var _ghosts: Array = []  # [root: Node3D, skeleton: Skeleton3D, materials: Array[ShaderMaterial], age: float]
var _next := 0
var _color := Color(0.6, 0.8, 1.0)


func setup(model: Node3D, skeleton: Skeleton3D, color: Color, count := 5) -> void:
	top_level = true
	_source = skeleton
	_color = color
	for ghost: Array in _ghosts:
		(ghost[0] as Node3D).queue_free()
	_ghosts.clear()
	for i in count:
		_ghosts.append(_make_ghost(model, skeleton))


func set_color(color: Color) -> void:
	_color = color
	for ghost: Array in _ghosts:
		for material: ShaderMaterial in ghost[2]:
			material.set_shader_parameter(&"color", color)


## Leaves a ghost of the current pose where the fighter is now, or at
## `where` (a skeleton transform), e.g. along a blink's path. `age` starts it
## part-way faded.
func snapshot(where := Transform3D(), use_where := false, age := 0.0) -> void:
	if _source == null or _ghosts.is_empty() or not _source.is_inside_tree():
		return
	var ghost: Array = _ghosts[_next]
	_next = (_next + 1) % _ghosts.size()
	var root: Node3D = ghost[0]
	var skeleton: Skeleton3D = ghost[1]
	root.global_transform = where if use_where else _source.global_transform
	for bone in _source.get_bone_count():
		skeleton.set_bone_pose(bone, _source.get_bone_pose(bone))
	ghost[3] = age
	root.visible = true


func _process(delta: float) -> void:
	for ghost: Array in _ghosts:
		var root: Node3D = ghost[0]
		if not root.visible:
			continue
		ghost[3] += delta
		var fade: float = 1.0 - ghost[3] / lifetime
		if fade <= 0.0:
			root.visible = false
			continue
		for material: ShaderMaterial in ghost[2]:
			material.set_shader_parameter(&"fade", fade)


func _make_ghost(model: Node3D, skeleton: Skeleton3D) -> Array:
	var root := Node3D.new()
	root.visible = false
	add_child(root)
	var copy := Skeleton3D.new()
	for bone in skeleton.get_bone_count():
		copy.add_bone(skeleton.get_bone_name(bone))
	for bone in skeleton.get_bone_count():
		copy.set_bone_parent(bone, skeleton.get_bone_parent(bone))
		copy.set_bone_rest(bone, skeleton.get_bone_rest(bone))
	root.add_child(copy)
	var materials: Array[ShaderMaterial] = []
	var material := ShaderMaterial.new()
	material.shader = GHOST_SHADER
	material.set_shader_parameter(&"color", _color)
	materials.append(material)
	for node in skeleton.get_children():
		if node is MeshInstance3D:
			var mesh := _copy_mesh(node as MeshInstance3D, material)
			mesh.skeleton = NodePath("..")
			copy.add_child(mesh)
		elif node is BoneAttachment3D:
			var attachment := BoneAttachment3D.new()
			attachment.bone_name = (node as BoneAttachment3D).bone_name
			copy.add_child(attachment)
			for child in node.find_children("*", "MeshInstance3D", true, false):
				var prop := _copy_mesh(child as MeshInstance3D, material)
				attachment.add_child(prop)
				prop.transform = (node as Node3D).global_transform.affine_inverse() * (child as Node3D).global_transform
	return [root, copy, materials, 1.0]


static func _copy_mesh(source: MeshInstance3D, material: Material) -> MeshInstance3D:
	var copy := MeshInstance3D.new()
	copy.mesh = source.mesh
	copy.skin = source.skin
	copy.transform = source.transform
	copy.material_override = material
	copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return copy
