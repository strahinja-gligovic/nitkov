class_name FrostTrail
extends MeshInstance3D
## A frost-mist ribbon left behind a moving point (the Ice Spike's tail). Its
## owner adds a point every frame; each one stays where it was dropped,
## widens and fades out over `lifetime`. The strip turns to face the camera
## in the shader, so this script never needs a camera (headless-safe).

## Seconds a point stays visible.
var lifetime := 0.22
## Half width when new and when about to vanish.
var width_new := 0.07
var width_old := 0.22

var _points := PackedVector3Array()
var _ages := PackedFloat32Array()
var _path := PackedFloat32Array()
var _immediate := ImmediateMesh.new()


func _ready() -> void:
	top_level = true
	mesh = _immediate
	material_override = FrostKit.trail_material()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 2.0
	global_transform = Transform3D.IDENTITY


## Drops a point at `at` (global), `distance` metres along the path.
func add_point(at: Vector3, distance: float) -> void:
	_points.append(at)
	_ages.append(0.0)
	_path.append(distance)


## True while anything is still visible.
func is_visible_trail() -> bool:
	return not _points.is_empty()


func _process(delta: float) -> void:
	var drop := 0
	for i in _ages.size():
		_ages[i] += delta
		if _ages[i] >= lifetime:
			drop = i + 1
	if drop > 0:
		_points = _points.slice(drop)
		_ages = _ages.slice(drop)
		_path = _path.slice(drop)
	_rebuild()


func _rebuild() -> void:
	_immediate.clear_surfaces()
	var count := _points.size()
	if count < 2:
		return
	_immediate.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in count:
		var along := _points[mini(i + 1, count - 1)] - _points[maxi(i - 1, 0)]
		var direction := along.normalized() if along.length() > 0.0001 else Vector3.FORWARD
		var age := clampf(_ages[i] / lifetime, 0.0, 1.0)
		var eased := 1.0 - (1.0 - age) * (1.0 - age)
		var half := lerpf(width_new, width_old, eased)
		# the newest point tapers to nothing at the spike's tail
		if i == count - 1:
			half *= 0.35
		for side in 2:
			_immediate.surface_set_normal(direction)
			_immediate.surface_set_uv(Vector2(age, float(side)))
			_immediate.surface_set_uv2(Vector2(half, _path[i]))
			_immediate.surface_add_vertex(_points[i])
	_immediate.surface_end()
