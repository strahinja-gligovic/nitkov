class_name LeanModifier
extends SkeletonModifier3D
## Leans the upper body into acceleration and turns, spread over the spine so
## the legs stay planted (tilting the whole model would sink a foot in a wide
## stance). FighterVisual feeds it BodyDynamics' spring-driven angles.

## Radians: forward (+) / back, and toward the character's right (+) / left.
var pitch := 0.0
var roll := 0.0
var spine_bones: Array[StringName] = [&"spine_01", &"spine_02", &"spine_03"]
var shares: Array[float] = [0.4, 0.35, 0.25]


func _process_modification_with_delta(_delta: float) -> void:
	if absf(pitch) + absf(roll) < 0.001:
		return
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	# skeleton space: the character faces +Z and its right is -X, so tipping
	# the top forward turns about +X and tipping it right turns about +Z
	for i in spine_bones.size():
		var bone := skeleton.find_bone(spine_bones[i])
		if bone < 0:
			continue
		var turn := Quaternion(Vector3.RIGHT, pitch * shares[i]) * Quaternion(Vector3.BACK, roll * shares[i])
		var global_basis := skeleton.get_bone_global_pose(bone).basis.orthonormalized()
		# the same turn expressed in the bone's own frame
		var local := Quaternion(global_basis.inverse() * Basis(turn) * global_basis)
		skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone) * local)
