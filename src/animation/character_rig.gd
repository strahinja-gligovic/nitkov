class_name CharacterRig
extends Node3D
## One assembled fighter body: the outfit with a head and hair, the
## longsword in the right fist and an anchor for the gauntlet orb on the left
## hand, converted to the toon look, with an AnimationPlayer ready for the
## shared clips. Everything is on the shared 65-bone humanoid rig.

const SWORD_SCENE := preload("res://assets/kaykit/weapons/sword_1handed.gltf")
## The sword's axes in hand_r space, fitted to the fist every sword clip is
## authored with: blade out of the thumb side, flat parallel to the palm.
const GRIP_BASIS := Basis(Vector3(0.01154, 0.94703, -0.32094), Vector3(-0.03402, 0.32114, 0.94642),
		Vector3(0.99936, 0.0, 0.03592))
## A 1.07 m longsword.
const SWORD_SCALE := 0.6
## Sword-local hilt and tip (KayKit blade along +Y, tip at 1.41).
const SWORD_HILT := Vector3(0.0, 0.25, 0.0)
const SWORD_TIP := Vector3(0.0, 1.41, 0.0)
const COLLAR_FILL := {
	false: {"bones": ["spine_03"], "min_y": 1.40, "radius": 0.10, "inset": 0.015},
	true: {"bones": ["spine_03", "clavicle_l", "clavicle_r"], "min_y": 1.36, "radius": 0.11, "inset": 0.012},
}
const LEFT_ARM_BONES: Array[String] = ["spine_02", "spine_03", "neck_01", "Head",
		"clavicle_l", "upperarm_l", "lowerarm_l", "hand_l"]

## The outfit's scene root: clip track paths ("Armature/Skeleton3D:bone") start here.
var model: Node3D
var skeleton: Skeleton3D
var anim_player: AnimationPlayer
var sword: Node3D
var sword_hilt := SWORD_HILT
var sword_tip := SWORD_TIP
var left_hand: BoneAttachment3D
## The gauntlet orb's spot in left_hand's space.
var knuckles_l := Vector3.ZERO
var materials: Array[ShaderMaterial] = []
var sword_materials: Array[ShaderMaterial] = []
var head_bone := &"Head"
var neck_bone := &"neck_01"
var chest_bone := &"spine_03"
var spine_bones: Array[StringName] = [&"spine_01", &"spine_02", &"spine_03"]
## The Head bone's own axis that points out of the face, and the one that
## points up, at rest (for the look-at).
var head_forward_axis := SkeletonModifier3D.BONE_AXIS_PLUS_Z
var head_up_axis := Vector3.AXIS_Y

var _hand_r := -1


static func build(character: CharacterData) -> CharacterRig:
	var rig := CharacterRig.new()
	rig.name = "Rig"
	rig._assemble(character)
	return rig


func _assemble(character: CharacterData) -> void:
	model = character.outfit.instantiate() as Node3D
	model.rotation.y = PI  # the models face +Z; fighters face -Z
	add_child(model)
	skeleton = model.get_node("Armature/Skeleton3D") as Skeleton3D
	_hand_r = skeleton.find_bone("hand_r")

	var fill: Dictionary = COLLAR_FILL[character.female] if character.collar_fill else {}
	var head: Array = HeadBuilder.build(character.head_from, character.head_mesh, fill)
	_add_skinned(head[0], head[1], "Head")
	for piece_scene in character.hair:
		var piece := piece_scene.instantiate()
		for found in piece.find_children("*", "MeshInstance3D", true, false):
			var part := found as MeshInstance3D
			_add_skinned(part.mesh, part.skin, piece_scene.resource_path.get_file().get_basename())
		piece.free()

	var hand := BoneAttachment3D.new()
	hand.name = "RightHand"
	hand.bone_name = "hand_r"
	skeleton.add_child(hand)
	sword = SWORD_SCENE.instantiate() as Node3D
	sword.name = "Longsword"
	sword.transform = Transform3D(GRIP_BASIS.scaled(Vector3.ONE * SWORD_SCALE), character.grip)
	hand.add_child(sword)
	left_hand = BoneAttachment3D.new()
	left_hand.name = "LeftHand"
	left_hand.bone_name = "hand_l"
	skeleton.add_child(left_hand)
	knuckles_l = character.orb_anchor

	anim_player = AnimationPlayer.new()
	anim_player.name = "AnimationPlayer"
	model.add_child(anim_player)
	anim_player.root_node = NodePath("..")

	var hair_tint := {&"MI_Hair_1": character.hair_color, &"MI_Hair_2": character.hair_color}
	materials = ToonMaterials.convert_model(model, hair_tint)
	sword_materials = []
	for node in sword.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		for surface in mesh_instance.get_surface_override_material_count():
			var material := mesh_instance.get_surface_override_material(surface) as ShaderMaterial
			if material:
				sword_materials.append(material)
	_find_head_axes()


func _add_skinned(mesh: Mesh, skin: Skin, node_name: String) -> void:
	var part := MeshInstance3D.new()
	part.name = node_name
	part.mesh = mesh
	part.skin = skin
	skeleton.add_child(part)
	part.skeleton = NodePath("..")


## "Armature/Skeleton3D:bone" paths for the upper-body layer: the spine from
## spine_02 up, the neck, the head and both arms down to the fingertips.
func upper_body_filter() -> Array[NodePath]:
	return _paths(func(bone: int) -> bool: return _is_or_under(bone, "spine_02"))


## The same for casting on the move: the spine, neck, head and the left arm
## only, so the sword arm keeps running.
func left_arm_filter() -> Array[NodePath]:
	return _paths(func(bone: int) -> bool:
		return skeleton.get_bone_name(bone) in LEFT_ARM_BONES or _is_or_under(bone, "hand_l"))


func _paths(wanted: Callable) -> Array[NodePath]:
	var out: Array[NodePath] = []
	for bone in skeleton.get_bone_count():
		if wanted.call(bone):
			out.append(NodePath("%s:%s" % [AnimLibrary.SKELETON_PATH, skeleton.get_bone_name(bone)]))
	return out


func _is_or_under(bone: int, ancestor: String) -> bool:
	while bone >= 0:
		if skeleton.get_bone_name(bone) == ancestor:
			return true
		bone = skeleton.get_bone_parent(bone)
	return false


## The sword in world space from the hand's current pose. Read it while the
## skeleton holds its final pose (its skeleton_updated signal): procedural
## layers are applied then and undone right after.
func sword_transform() -> Transform3D:
	if _hand_r < 0:
		return sword.global_transform
	return skeleton.global_transform * skeleton.get_bone_global_pose(_hand_r) * sword.transform


## Which of the head bone's axes looks out of the face and which points up,
## measured at rest (the face points along the feet, heel to toe).
func _find_head_axes() -> void:
	var head := skeleton.find_bone(String(head_bone))
	var foot := skeleton.find_bone("foot_l")
	var ball := skeleton.find_bone("ball_l")
	if head < 0 or foot < 0 or ball < 0:
		return
	var forward := skeleton.get_bone_global_rest(ball).origin - skeleton.get_bone_global_rest(foot).origin
	forward.y = 0.0
	var basis := skeleton.get_bone_global_rest(head).basis.orthonormalized()
	var axes := [Vector3.RIGHT, -Vector3.RIGHT, Vector3.UP, -Vector3.UP, Vector3.BACK, -Vector3.BACK]
	var best := -2.0
	for i in axes.size():
		var score := (basis * (axes[i] as Vector3)).normalized().dot(forward.normalized())
		if score > best:
			best = score
			head_forward_axis = i as SkeletonModifier3D.BoneAxis
	var up_best := -2.0
	for i in 3:
		var score := absf((basis * (axes[i * 2] as Vector3)).normalized().dot(Vector3.UP))
		if score > up_best:
			up_best = score
			head_up_axis = i as Vector3.Axis
