class_name WindRibbon
extends MeshInstance3D
## A trail left in world space behind something moving (a wingtip, a spear's
## wake): push a point each frame with add(); each one fades out over
## `lifetime` and the ribbon draws through them with wind_line.gdshader,
## facing the camera. Dashes stay put in the world, so the air looks left
## behind rather than dragged along. Cosmetic only.

var lifetime := 0.2
var width := 0.08
## Metres per dash (see wind_line.gdshader's UV2.y).
var dash_length := 0.6
## How much a point's width grows by the time it fades (a spreading wake).
var spread := 0.0

var _points := PackedVector3Array()
var _ages := PackedFloat32Array()
var _widths := PackedFloat32Array()
var _dash := PackedFloat32Array()
var _travelled := 0.0
var _mesh := ImmediateMesh.new()


## A ribbon under `parent` drawn with `material` (a wind_line.gdshader).
static func spawn(parent: Node, material: Material, life: float, ribbon_width: float) -> WindRibbon:
	var ribbon := WindRibbon.new()
	ribbon.material_override = material
	ribbon.lifetime = life
	ribbon.width = ribbon_width
	parent.add_child(ribbon)
	return ribbon


func _ready() -> void:
	top_level = true
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 1.0
	global_transform = Transform3D.IDENTITY


## Leaves a point at `at` (world), `scale` times the ribbon's width.
func add(at: Vector3, scale := 1.0) -> void:
	if not _points.is_empty():
		_travelled += at.distance_to(_points[_points.size() - 1])
	_points.append(at)
	_ages.append(0.0)
	_widths.append(width * scale)
	_dash.append(_travelled / dash_length)


func is_empty() -> bool:
	return _points.is_empty()


func _process(delta: float) -> void:
	var expired := 0
	for i in _ages.size():
		_ages[i] += delta
		if _ages[i] >= lifetime:
			expired = i + 1
	if expired > 0:
		_points = _points.slice(expired)
		_ages = _ages.slice(expired)
		_widths = _widths.slice(expired)
		_dash = _dash.slice(expired)
	_rebuild()


func _rebuild() -> void:
	_mesh.clear_surfaces()
	var count := _points.size()
	if count < 2:
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	# newest point first: UV.x runs head (0) to tail (1)
	for k in count:
		var i := count - 1 - k
		var ahead := _points[mini(i + 1, count - 1)]
		var behind := _points[maxi(i - 1, 0)]
		var direction := ahead - behind
		if direction.length_squared() < 0.000001:
			direction = Vector3.FORWARD
		var age := clampf(_ages[i] / lifetime, 0.0, 1.0)
		var w := _widths[i] * (1.0 + spread * age)
		var along := float(k) / float(count - 1)
		for side in 2:
			_mesh.surface_set_normal(direction.normalized())
			_mesh.surface_set_color(Color(1.0, 1.0, 1.0, 1.0 - age))
			_mesh.surface_set_uv(Vector2(along, float(side)))
			_mesh.surface_set_uv2(Vector2(w, _dash[i]))
			_mesh.surface_add_vertex(_points[i])
	_mesh.surface_end()
