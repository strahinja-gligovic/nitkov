class_name LightningChargeFx
extends Node3D
## Lightning gathering in the casting hand for the wind-up
## (LightningFx.charge): a shell of crackling arcs tightening round the
## gauntlet, little arcs jumping out of it, spitting sparks, and a flare and a
## flickering light that swell toward the release. A signature also sends
## arcs crawling up the arm from the hand to the shoulder as it is raised.
## It rides the hand (without the hand's swelling scale) and frees itself
## when the wind-up time is over, cast or not.

const REFRESH := 1.0 / 30.0
## Arm bones the crawl climbs, from the wrist up.
const ARM_BONES: Array[StringName] = [&"hand_l", &"lowerarm_l", &"upperarm_l"]

var seconds := 0.2
var signature := false

var _hand: Node3D
var _arcs: LightningArc
var _flare: LightningFlare
var _sparks: LightningSparks
var _light: OmniLight3D
var _skeleton: Skeleton3D
var _bones := PackedInt32Array()
## The arm's joints as last posed (wrist, elbow, shoulder), world space.
var _joints := PackedVector3Array()
var _age := 0.0
var _next := 0.0
var _jump_left := 0.0
var _jump_next := 0.0
var _jump := PackedVector3Array()
var _jump_fork := PackedVector3Array()
var _spark_next := 0.0


static func attach(hand: Node3D, wind_up: float, is_signature: bool) -> LightningChargeFx:
	var fx := LightningChargeFx.new()
	fx.name = "LightningCharge"
	fx.seconds = maxf(wind_up, 0.05)
	fx.signature = is_signature
	fx._hand = hand
	hand.add_child(fx)
	return fx


func _ready() -> void:
	top_level = true
	global_transform = Transform3D(Basis.IDENTITY, _hand.global_position)
	_arcs = LightningArc.new()
	_arcs.style(false, LightningFx.COLOR)
	add_child(_arcs)
	_flare = LightningFlare.attach(self, 0.3)
	_light = LightningFx.lamp(LightningFx.COLOR, 0.0, 3.5 if signature else 2.5)
	add_child(_light)
	_sparks = LightningSparks.spawn(self, LightningFx.HOT)
	_sparks.gravity = 5.0
	_sparks.drag = 3.0
	_sparks.hold = true
	if signature:
		_find_arm()


func _exit_tree() -> void:
	if _skeleton and is_instance_valid(_skeleton) and _skeleton.skeleton_updated.is_connected(_on_posed):
		_skeleton.skeleton_updated.disconnect(_on_posed)


func _process(delta: float) -> void:
	_age += delta
	if _age >= seconds or not is_instance_valid(_hand):
		# let the last sparks finish their fall in the world
		var scene := LightningFx.world_of(self)
		if scene and _sparks.alive() > 0:
			_sparks.hold = false
			_sparks.reparent(scene)
		queue_free()
		return
	global_position = _hand.global_position
	var p := _age / seconds
	_next -= delta
	if _next <= 0.0:
		_next = REFRESH
		_redraw(p)
	_jump_left -= delta
	_spark_next -= delta
	if _spark_next <= 0.0:
		_spark_next = lerpf(0.05, 0.018, p)
		_sparks.emit(global_position + LightningArc.scatter(Vector3.UP, PI) * 0.1, 1 + int(p * 2.0),
				Vector3.UP, PI, Vector2(1.2, 3.0), Vector2(0.1, 0.25), 0.025)
	var flicker := randf_range(0.65, 1.0)
	var size := lerpf(0.2, 0.4, p) * (1.3 if signature else 1.0)
	_flare.scale = Vector3.ONE * size
	_light.light_energy = lerpf(0.6, 2.4, p) * flicker * (1.3 if signature else 1.0)


func _redraw(p: float) -> void:
	var centre := global_position
	_arcs.clear()
	# the shell: arcs skating round the fist, closing in as the charge builds
	# (thick enough to read over the shoulder and from across the arena: the
	# fist must look electric, not just glow)
	var radius := lerpf(0.24, 0.12, p) * (1.25 if signature else 1.0)
	for i in 4 + int(p * 4.0):
		_arcs.add(_shell_arc(centre, radius), 0.014 + 0.01 * p, lerpf(0.75, 1.2, p), 0.5, 0.4)
	# now and then an arc jumps out of the hand, more often near the release
	_jump_next -= REFRESH
	if _jump_next <= 0.0:
		_jump_next = randf_range(0.04, 0.09) * lerpf(1.0, 0.45, p)
		_jump_left = REFRESH * 2.0
		_jump.clear()
		_jump_fork.clear()
		var out := LightningArc.scatter(Vector3.UP, PI)
		_jump = LightningArc.jagged(centre + out * radius, centre + out * randf_range(0.35, 0.7) * (1.0 + 0.5 * p), 3, 0.3)
		_jump_fork = LightningArc.fork(_jump, randf_range(0.15, 0.3), 0.9, 2, 0.3)
	if _jump_left > 0.0 and _jump.size() >= 2:
		_arcs.add(_jump, 0.018, 1.0, 0.8, 0.5)
		_arcs.add(_jump_fork, 0.01, 0.9, 0.8, 0.5)
	if signature and _joints.size() == ARM_BONES.size():
		_crawl(centre, p)
	_arcs.commit()
	_flare.show_state(lerpf(0.3, 0.1, p), lerpf(0.5, 1.0, p) * randf_range(0.75, 1.1), true)


## An arc along the surface of a ball round the fist.
static func _shell_arc(centre: Vector3, radius: float) -> PackedVector3Array:
	var start := LightningArc.scatter(Vector3.UP, PI)
	var axis := LightningArc.scatter(start.cross(Vector3.UP if absf(start.y) < 0.9 else Vector3.RIGHT), 0.6)
	var sweep := randf_range(1.0, 2.2)
	var points := PackedVector3Array()
	var steps := 6
	for k in steps + 1:
		var dir := start.rotated(axis.normalized(), sweep * k / steps)
		points.append(centre + dir * radius * randf_range(0.85, 1.25))
	return points


## Arcs climbing the arm from the fist toward the shoulder: the crawl's front
## reaches the shoulder as the wind-up ends.
func _crawl(centre: Vector3, p: float) -> void:
	var chain := PackedVector3Array([centre])
	chain.append_array(_joints)
	var total := 0.0
	for i in chain.size() - 1:
		total += chain[i].distance_to(chain[i + 1])
	var reach := total * clampf(p * 1.25, 0.12, 1.0)
	for strand in 2 + int(p * 2.0):
		var path := PackedVector3Array()
		var walked := 0.0
		for i in chain.size() - 1:
			var a := chain[i]
			var b := chain[i + 1]
			var length := a.distance_to(b)
			var dir := (b - a) / maxf(length, 0.001)
			var side := dir.cross(Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT).normalized()
			var steps := maxi(2, int(length / 0.07))
			for k in steps:
				if walked + length * k / steps > reach:
					break
				var around := side.rotated(dir, randf() * TAU) * randf_range(0.045, 0.085)
				path.append(a + dir * length * k / steps + around)
			walked += length
			if walked > reach:
				break
		if path.size() >= 2:
			_arcs.add(path, 0.012 + 0.006 * p, randf_range(0.75, 1.15), 0.3, 0.1)
	# the front of the crawl spits a short fork
	var front := _point_along(chain, reach)
	_arcs.add(LightningArc.jagged(front, front + LightningArc.scatter(Vector3.UP, PI) * 0.18, 2, 0.4), 0.007, 1.0, 0.6, 0.4)


static func _point_along(chain: PackedVector3Array, distance: float) -> Vector3:
	var left := distance
	for i in chain.size() - 1:
		var length := chain[i].distance_to(chain[i + 1])
		if left <= length:
			return chain[i].lerp(chain[i + 1], left / maxf(length, 0.001))
		left -= length
	return chain[chain.size() - 1]


## Finds the skeleton above the gauntlet and follows the arm's final pose.
func _find_arm() -> void:
	var node := _hand.get_parent()
	for i in 6:
		if node == null or node is Skeleton3D:
			break
		node = node.get_parent()
	_skeleton = node as Skeleton3D
	if _skeleton == null:
		return
	for bone in ARM_BONES:
		var index := _skeleton.find_bone(bone)
		if index < 0:
			_skeleton = null
			return
		_bones.append(index)
	_skeleton.skeleton_updated.connect(_on_posed)
	_on_posed()


## Reads the arm's joints once the skeleton has its final pose (modifiers
## included), which is only true inside this signal.
func _on_posed() -> void:
	if not is_instance_valid(_skeleton):
		return
	_joints.resize(_bones.size())
	var to_world := _skeleton.global_transform
	for i in _bones.size():
		_joints[i] = to_world * _skeleton.get_bone_global_pose(_bones[i]).origin
