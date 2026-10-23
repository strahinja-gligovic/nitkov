class_name WeaponTrail
extends MeshInstance3D
## A ribbon that trails a blade while `emitting` is on. It samples the
## sword's world transform every frame and, between samples, interpolates
## the whole transform (rotation included), so even a strike that crosses
## the screen in two frames sweeps a curved arc instead of a straight chord.
## Purely cosmetic: lives in world space (top_level) and reads its target.

const TRAIL_SHADER := preload("res://src/vfx/trail.gdshader")

## The node whose transform the blade follows (the sword), unless the owner
## pushes samples itself with push() (e.g. from the skeleton's final pose).
var target: Node3D
## Hilt and tip in the target's local space.
var hilt_local := Vector3.ZERO
var tip_local := Vector3(0.0, 1.0, 0.0)
## Seconds a sample stays visible.
var lifetime := 0.14
## In-between transforms generated per frame gap (smooths fast strikes).
var subdivisions := 6
var emitting := false

var _samples: Array = []  # [age: float, transform: Transform3D]
var _pushed := false
var _immediate := ImmediateMesh.new()
var _material := ShaderMaterial.new()


func setup(follow: Node3D, hilt: Vector3, tip: Vector3) -> void:
	target = follow
	hilt_local = hilt
	tip_local = tip


func set_colors(core: Color, edge: Color, energy := 2.2) -> void:
	_material.set_shader_parameter(&"core_color", core)
	_material.set_shader_parameter(&"edge_color", edge)
	_material.set_shader_parameter(&"energy", energy)


func _ready() -> void:
	top_level = true
	mesh = _immediate
	_material.shader = TRAIL_SHADER
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384.0
	global_transform = Transform3D.IDENTITY


func _process(delta: float) -> void:
	for sample: Array in _samples:
		sample[0] += delta
	while not _samples.is_empty() and _samples[0][0] > lifetime:
		_samples.pop_front()
	if emitting and not _pushed and is_instance_valid(target) and target.is_inside_tree():
		_samples.append([0.0, target.global_transform])
	_rebuild()


## Adds the blade's world transform for this frame, for owners that know the
## final pose only later in the frame; the trail then stops reading `target`.
func push(blade: Transform3D) -> void:
	_pushed = true
	if emitting:
		_samples.append([0.0, blade])
		_rebuild()


## Drop everything (e.g. after a teleport) so no ribbon stretches across the map.
func clear() -> void:
	_samples.clear()
	_immediate.clear_surfaces()


func _rebuild() -> void:
	_immediate.clear_surfaces()
	if _samples.size() < 2:
		return
	_immediate.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in _samples.size() - 1:
		var a: Array = _samples[i]
		var b: Array = _samples[i + 1]
		var steps := subdivisions if i < _samples.size() - 2 else subdivisions + 1
		for step in steps:
			var t := float(step) / subdivisions
			var xform: Transform3D = (a[1] as Transform3D).interpolate_with(b[1], t)
			var age := lerpf(a[0], b[0], t) / lifetime
			_emit_pair(xform, age)
	_immediate.surface_end()


func _emit_pair(xform: Transform3D, age: float) -> void:
	_immediate.surface_set_uv(Vector2(age, 0.0))
	_immediate.surface_add_vertex(xform * hilt_local)
	_immediate.surface_set_uv(Vector2(age, 1.0))
	_immediate.surface_add_vertex(xform * tip_local)
