class_name LightningShockFx
extends Node3D
## A lightning stun crackling over a fighter (LightningFx.shock): arcs crawl
## along the limbs and spine, re-randomizing every couple of frames, with
## the odd arc leaping off the body or down to the floor; the whole thing
## strobes, sparks drip off it, and a light flickers on the body. It follows
## the skeleton's final pose (read in skeleton_updated, where modifiers are
## included); without a skeleton it crackles over a body-sized capsule.
## Rides on `body` (the visual pivot) and frees itself after `seconds`.

const REFRESH := 1.0 / 30.0
## Bone chains the arcs crawl along, with how far off the bone the skin is.
const CHAINS := [
	[[&"pelvis", &"spine_01", &"spine_02", &"spine_03", &"neck_01", &"Head"], 0.21],
	[[&"spine_03", &"clavicle_l", &"upperarm_l", &"lowerarm_l", &"hand_l"], 0.11],
	[[&"spine_03", &"clavicle_r", &"upperarm_r", &"lowerarm_r", &"hand_r"], 0.11],
	[[&"pelvis", &"thigh_l", &"calf_l", &"foot_l"], 0.12],
	[[&"pelvis", &"thigh_r", &"calf_r", &"foot_r"], 0.12],
]

var seconds := 1.0

var _body: Node3D
var _arcs: LightningArc
var _sparks: LightningSparks
var _light: OmniLight3D
var _skeleton: Skeleton3D
## Bone index per chain link, and the posed positions (world) per bone.
var _chain_bones: Array[PackedInt32Array] = []
var _chain_skin := PackedFloat32Array()
var _posed := {}
var _floor := 0.0
var _age := 0.0
var _next := 0.0
var _drip := 0.0
var _beat := 1.0


static func attach(body: Node3D, stun: float) -> LightningShockFx:
	var fx := LightningShockFx.new()
	fx.name = "LightningShock"
	fx.seconds = stun
	fx._body = body
	body.add_child(fx)
	return fx


func _ready() -> void:
	_floor = _body.global_position.y
	_arcs = LightningArc.new()
	_arcs.style(false, LightningFx.COLOR)
	add_child(_arcs)
	_sparks = LightningSparks.spawn(self, LightningFx.HOT, _floor)
	_sparks.hold = true
	_light = LightningFx.lamp(LightningFx.COLOR, 2.0, 3.5)
	_light.position = Vector3.UP * 1.1
	add_child(_light)
	_find_skeleton()
	_redraw()


func _exit_tree() -> void:
	if _skeleton and is_instance_valid(_skeleton) and _skeleton.skeleton_updated.is_connected(_on_posed):
		_skeleton.skeleton_updated.disconnect(_on_posed)


func _find_skeleton() -> void:
	var found := _body.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return
	_skeleton = found[0] as Skeleton3D
	for chain: Array in CHAINS:
		var indices := PackedInt32Array()
		for bone: StringName in chain[0]:
			var index := _skeleton.find_bone(bone)
			if index >= 0:
				indices.append(index)
		if indices.size() >= 2:
			_chain_bones.append(indices)
			_chain_skin.append(chain[1])
	if _chain_bones.is_empty():
		_skeleton = null
		return
	_skeleton.skeleton_updated.connect(_on_posed)
	_on_posed()


func _on_posed() -> void:
	if not is_instance_valid(_skeleton):
		return
	var to_world := _skeleton.global_transform
	for indices in _chain_bones:
		for index in indices:
			_posed[index] = to_world * _skeleton.get_bone_global_pose(index).origin


## How strongly it crackles: a hard jolt, then a stuttering buzz that dies
## down toward the end of the stun.
func _strength() -> float:
	var t := _age / maxf(seconds, 0.01)
	if _age < 0.12:
		return 1.3
	return lerpf(1.0, 0.45, t) * (1.0 if t < 0.8 else (1.0 - t) / 0.2)


func _process(delta: float) -> void:
	_age += delta
	if _age >= seconds or not is_instance_valid(_body):
		var scene := LightningFx.world_of(self)
		if scene and _sparks.alive() > 0:
			_sparks.hold = false
			_sparks.reparent(scene)
		queue_free()
		return
	_next -= delta
	if _next <= 0.0:
		_next = REFRESH
		_redraw()
	var strength := _strength()
	_arcs.set_brightness(strength * _beat)
	_light.light_energy = 2.4 * strength * _beat
	_drip -= delta
	if _drip <= 0.0:
		_drip = 0.045
		for i in 2:
			_sparks.add(_random_point(), Vector3(randf_range(-1.2, 1.2), randf_range(-0.5, 1.5), randf_range(-1.2, 1.2)),
					randf_range(0.35, 0.7), 0.03)


func _redraw() -> void:
	# the buzz stutters: some beats nearly drop out
	_beat = 0.15 if randf() < 0.18 and _age > 0.15 else randf_range(0.75, 1.0)
	_arcs.clear()
	if _skeleton and not _posed.is_empty():
		for i in 6:
			var c := randi() % _chain_bones.size()
			_arcs.add(_chain_path(c), 0.028, randf_range(0.8, 1.2), 0.4, 0.3)
	else:
		for i in 4:
			_arcs.add(LightningArc.jagged(_random_point(), _random_point(), 4, 0.2), 0.018, 0.9, 0.4, 0.3)
	# arcs leaping off the body, and now and then one down to the floor
	for i in 2:
		var from := _random_point()
		_arcs.add(LightningArc.jagged(from, from + LightningArc.scatter(Vector3.UP, 1.8) * randf_range(0.3, 0.6), 3, 0.3),
				0.02, 1.0, 0.8, 0.5)
	if randf() < 0.35:
		var from := _random_point()
		var to := Vector3(from.x, _floor, from.z) + LightningArc.along_surface(Vector3.UP) * randf_range(0.2, 0.6)
		_arcs.add(LightningArc.jagged(from, to, 4, 0.2), 0.016, 0.9, 0.6, 0.3)
	_arcs.commit()


## A path along part of a bone chain, kicked out to the skin.
func _chain_path(c: int) -> PackedVector3Array:
	var indices := _chain_bones[c]
	var skin := _chain_skin[c]
	var first := randi() % (indices.size() - 1)
	var last := mini(indices.size() - 1, first + randi_range(1, 3))
	var path := PackedVector3Array()
	for i in range(first, last):
		var a: Vector3 = _posed.get(indices[i], Vector3.ZERO)
		var b: Vector3 = _posed.get(indices[i + 1], Vector3.ZERO)
		var dir := (b - a).normalized()
		var side := dir.cross(Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT).normalized()
		for k in 4:
			var around := side.rotated(dir, randf() * TAU) * skin * randf_range(0.8, 1.4)
			path.append(a.lerp(b, k / 4.0) + around)
	var end: Vector3 = _posed.get(indices[last], Vector3.ZERO)
	path.append(end + LightningArc.scatter(Vector3.UP, PI) * skin)
	return path


## Somewhere on the body's surface.
func _random_point() -> Vector3:
	if _skeleton and not _posed.is_empty():
		var c := randi() % _chain_bones.size()
		var indices := _chain_bones[c]
		var i := randi() % (indices.size() - 1)
		var a: Vector3 = _posed.get(indices[i], Vector3.ZERO)
		var b: Vector3 = _posed.get(indices[i + 1], Vector3.ZERO)
		return a.lerp(b, randf()) + LightningArc.scatter(Vector3.UP, PI) * _chain_skin[c]
	var base := _body.global_position
	return base + Vector3(randf_range(-0.25, 0.25), randf_range(0.2, 1.7), randf_range(-0.25, 0.25))
