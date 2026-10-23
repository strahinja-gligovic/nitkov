class_name LightningWarningFx
extends Node3D
## Lightning Strike's telegraph (LightningFx.strike_warning), built under the
## strike at the ground centre. For `delay` seconds it shows exactly where the
## bolt will land and when:
##   - a circle of exactly `radius` on the ground: the storm's shadow, a
##     crackling rim with light running round it, and a countdown fill that
##     reaches the rim as the bolt lands (lightning_mark.gdshader);
##   - arcs racing round the rim and streamers reaching up from it, taller
##     and denser as time runs out, so the circle reads over low walls and
##     at grazing angles;
##   - static sparks rising from inside, more and more;
##   - a storm cloud gathering overhead, flickering with lightning;
##   - in the last moments, a faint leader stepping down from the cloud.
## The strike frees it as the bolt lands; LightningFx.strike() first takes
## over its cloud and the leader's path.

const GROUP := &"lightning_warnings"
const CLOUD_HEIGHT := 8.0
const REFRESH := 1.0 / 30.0
## Seconds before the strike that the leader starts down.
const LEAD := 0.2

var radius := 2.5
var delay := 0.9
var cloud: LightningCloud
## The leader's whole path, cloud to ground (world space), planned up front.
var leader := PackedVector3Array()

var _mark: MeshInstance3D
var _rim: LightningArc
var _sparks: LightningSparks
var _light: OmniLight3D
var _age := 0.0
var _next := 0.0
var _spark_debt := 0.0
var _run_angle := 0.0


static func build(parent: Node3D, strike_radius: float, strike_delay: float) -> LightningWarningFx:
	var fx := LightningWarningFx.new()
	fx.name = "LightningWarning"
	fx.radius = strike_radius
	fx.delay = maxf(strike_delay, 0.05)
	parent.add_child(fx)
	return fx


func _ready() -> void:
	add_to_group(GROUP)
	LightningScorch.prepare()
	_run_angle = randf() * TAU
	var extent := radius + 0.35
	_mark = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * extent * 2.0
	_mark.mesh = plane
	_mark.material_override = _mark_material()
	_mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mark.position.y = 0.03
	_mark.set_instance_shader_parameter(&"radius", radius)
	_mark.set_instance_shader_parameter(&"extent", extent)
	_mark.set_instance_shader_parameter(&"seed", randf())
	add_child(_mark)
	_rim = LightningArc.new()
	_rim.style(false, LightningFx.COLOR)
	add_child(_rim)
	_sparks = LightningSparks.spawn(self, LightningFx.HOT, global_position.y)
	_sparks.gravity = -2.5
	_sparks.drag = 0.8
	_sparks.hold = true
	_light = LightningFx.lamp(LightningFx.COLOR, 0.5, radius * 2.4)
	_light.position = Vector3.UP * 1.4
	add_child(_light)
	cloud = LightningCloud.make(radius, delay)
	add_child(cloud)
	cloud.position = Vector3.UP * CLOUD_HEIGHT
	var top := global_position + Vector3.UP * (CLOUD_HEIGHT - 0.6) + Vector3(randf_range(-0.6, 0.6), 0.0, randf_range(-0.6, 0.6))
	leader = LightningArc.jagged(top, global_position, 6, 0.07)
	_update(0.0)


static var _material: ShaderMaterial


static func _mark_material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = preload("res://src/vfx/lightning/lightning_mark.gdshader")
	return _material


func _process(delta: float) -> void:
	_age += delta
	_update(delta)


func _update(delta: float) -> void:
	var p := clampf(_age / delay, 0.0, 1.0)
	_mark.set_instance_shader_parameter(&"progress", p)
	_mark.set_instance_shader_parameter(&"age", _age)
	_mark.set_instance_shader_parameter(&"energy", randf_range(0.85, 1.15) * (0.75 + 0.5 * p))
	_light.light_energy = (0.5 + 2.6 * p * p) * randf_range(0.6, 1.0)
	# static sparks rising from inside the circle, faster and faster
	_spark_debt += delta * lerpf(14.0, 120.0, p * p)
	while _spark_debt >= 1.0:
		_spark_debt -= 1.0
		var spot := LightningArc.along_surface(Vector3.UP) * radius * sqrt(randf())
		_sparks.add(global_position + spot + Vector3.UP * 0.05,
				Vector3(randf_range(-0.3, 0.3), randf_range(2.0, 4.0 + 3.0 * p), randf_range(-0.3, 0.3)),
				randf_range(0.35, 0.7), 0.05)
	_next -= delta
	if _next <= 0.0:
		_next = REFRESH
		_redraw(p)


func _redraw(p: float) -> void:
	var centre := global_position
	_rim.clear()
	# arcs racing round the rim, hugging the ground
	_run_angle += lerpf(0.35, 0.9, p)
	var runners := 3 + int(p * 2.0)
	for r in runners:
		var start := _run_angle + TAU * r / runners + randf_range(-0.2, 0.2)
		var span := randf_range(0.5, 1.0)
		var path := PackedVector3Array()
		var steps := 9
		for k in steps + 1:
			var angle := start + span * k / steps
			path.append(centre + Vector3(cos(angle), 0.0, sin(angle)) * (radius + randf_range(-0.08, 0.06))
					+ Vector3.UP * randf_range(0.03, 0.12 + 0.2 * p))
		_rim.add(path, 0.02 + 0.012 * p, 0.8 + 0.4 * p, 0.3, 0.3)
	# streamers reaching up from the rim, taller as the strike nears
	var streamers := 7 + int(p * 12.0)
	var height := 0.7 + 1.9 * pow(p, 1.2)
	for s in streamers:
		var angle := randf() * TAU
		var foot := centre + Vector3(cos(angle), 0.0, sin(angle)) * radius
		var tip := foot + Vector3(randf_range(-0.2, 0.2), height * randf_range(0.5, 1.0), randf_range(-0.2, 0.2))
		_rim.add(LightningArc.jagged(foot, tip, 3, 0.25), 0.024 + 0.016 * p, randf_range(0.7, 1.2), 0.85, 0.6)
	# a few arcs creeping in across the ground toward the centre
	if p > 0.35:
		for i in int(p * 3.0):
			var angle := randf() * TAU
			var foot := centre + Vector3(cos(angle), 0.0, sin(angle)) * radius
			var to := centre + Vector3(cos(angle), 0.0, sin(angle)) * radius * randf_range(0.3, 0.7)
			_rim.add(LightningArc.jagged(foot + Vector3.UP * 0.04, to + Vector3.UP * 0.04, 3, 0.2, Vector3.UP),
					0.012, 0.7, 0.8, 0.6)
	# the leader stepping down from the cloud in the last moments
	var since := _age - (delay - LEAD)
	if since > 0.0 and leader.size() >= 2:
		var steps := clampi(int(ceil(since / REFRESH)), 1, 6)
		var count := int(leader.size() * (0.25 + 0.75 * steps / 6.0) * 0.85)
		var part := leader.slice(0, maxi(count, 2))
		_rim.add(part, 0.035, 0.55, 0.4, 0.3)
		var tip_t := Vector2(0.6, 0.98)
		for f in 2:
			_rim.add(LightningArc.fork(part, randf_range(0.8, 2.0), 0.8, 3, 0.25, Vector3.ZERO, tip_t), 0.016, 0.45, 0.8, 0.6)
	_rim.commit()
