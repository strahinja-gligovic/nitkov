class_name FrostCling
extends Node3D
## A frost burst clinging to a fighter where an Ice Spike struck: a crust of
## small crystals bristling out of the body and a wisp of cold vapour that
## ride along with it for a moment, then crumble. It follows its target's
## position only and reads nothing else.

const LIFE := 0.75

var _target: Node3D
var _offset := Vector3.ZERO
var _time := 0.0


## Clings to `target` (may be null: then it stays put) at `at`, bristling
## out along `normal`.
static func attach(world: Node, target: Node3D, at: Vector3, normal: Vector3) -> FrostCling:
	var cling := FrostCling.new()
	cling.name = "FrostCling"
	cling.top_level = true
	world.add_child(cling)
	cling.global_position = at
	if is_instance_valid(target):
		cling._target = target
		cling._offset = at - target.global_position
	var crystals := FrostCrystals.make(8, true)
	cling.add_child(crystals)
	for k in 8:
		var out := FrostKit.random_cone(normal, 80.0 if k > 2 else 35.0)
		var root := FrostKit.random_direction() * 0.06
		var height := randf_range(0.28, 0.42) if k < 3 else randf_range(0.14, 0.26)
		crystals.add(FrostCrystals.root_at(root - normal * 0.04, out, height, randf_range(0.038, 0.06)),
				k * 0.01, 0.06, randf_range(0.34, 0.46), 0.24)
	var mist := FrostBits.make(FrostBits.Kind.PUFF, 4)
	mist.drag = 2.5
	mist.gravity = -0.8
	mist.swell = 2.0
	cling.add_child(mist)
	for k in 4:
		var out := FrostKit.random_cone(normal, 85.0)
		mist.add(out * 0.1, out * randf_range(0.4, 1.0) + Vector3.UP * 0.4, Vector3.ONE * randf_range(0.1, 0.16),
				randf_range(0.35, 0.5), 0.05 + k * 0.04)
	return cling


func _process(delta: float) -> void:
	_time += delta
	if _time >= LIFE:
		queue_free()
		return
	if is_instance_valid(_target) and _target.is_inside_tree():
		global_position = _target.global_position + _offset
