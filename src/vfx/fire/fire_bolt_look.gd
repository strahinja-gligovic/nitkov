class_name FireBoltLook
extends Node3D
## The Firebolt in flight: a roiling fireball (a white-hot face over an
## orange-red shell that streams back into flame licks), a tapered flame
## trail laid along its path that cools into a smoke wisp, shed embers and
## smoke, and a flickering light. -Z is the flight direction; the Projectile
## places this node every frame. After impact, finish() lets the trail cool
## and the embers burn out, then frees it.

## Seconds of flight path the flame trail covers (about 3 m at 38 m/s).
const TRAIL_TIME := 0.085
## Seconds the trail, embers and smoke take to die out after impact.
const LINGER := 0.6
const EMBERS_PER_SECOND := 75.0
const SMOKE_PER_SECOND := 22.0

var _radius := 0.28
var _seed := 0.0
var _shell: MeshInstance3D
var _licks: MeshInstance3D
var _light: OmniLight3D
var _trail: MeshInstance3D
var _trail_mesh := ImmediateMesh.new()
var _embers: FireMotes
var _smoke: FireMotes
## The recent path, newest first: positions, times and distances flown.
var _path := PackedVector3Array()
var _path_time := PackedFloat32Array()
var _path_dist := PackedFloat32Array()
var _time := 0.0
var _finished_at := -1.0
var _flown := 0.0
var _ember_debt := 0.0
var _smoke_debt := 0.0


static func create(radius: float) -> FireBoltLook:
	var look := FireBoltLook.new()
	look._build(radius)
	return look


func _build(radius: float) -> void:
	_radius = radius
	_seed = randf() * 100.0
	# a touch bigger than the hit radius, so it reads at range; not too hot,
	# so seen head-on (incoming) it is a white heart in yellow and orange
	# flame, not a featureless white disc
	_shell = FireKit.ball(radius * 1.15, 0.76, _seed)
	_shell.set_instance_shader_parameter(&"stretch", 1.5)
	_shell.set_instance_shader_parameter(&"boil", 0.16)
	_shell.set_instance_shader_parameter(&"flow", 2.0)
	add_child(_shell)
	# ragged outer licks streaming back off the ball
	_licks = FireKit.ball(radius * 1.7, 0.7, _seed + 17.0)
	_licks.set_instance_shader_parameter(&"stretch", 2.4)
	_licks.set_instance_shader_parameter(&"boil", 0.32)
	_licks.set_instance_shader_parameter(&"flow", 2.8)
	_licks.set_instance_shader_parameter(&"dissolve", 0.56)
	# no ink-dark fringe on the licks: a crown of dark thorns reads as a burr
	_licks.set_instance_shader_parameter(&"burnout", 0.3)
	# always torn into scraps: drawn out of the ink outline's sight, or each
	# scrap gets its own black outline
	_licks.material_override = FireKit.ball_soft_material()
	add_child(_licks)

	_light = FireKit.light(2.2, 4.5)
	add_child(_light)

	_trail = MeshInstance3D.new()
	_trail.top_level = true
	_trail.mesh = _trail_mesh
	_trail.material_override = FireKit.trail_material()
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trail.extra_cull_margin = 1.0
	_trail.set_instance_shader_parameter(&"seed", _seed)
	_trail.set_instance_shader_parameter(&"fade", 1.0)
	add_child(_trail)

	_embers = FireMotes.create(48, FireKit.ember_material())
	_embers.gravity = Vector3(0.0, 1.2, 0.0)
	_embers.drag = 3.0
	add_child(_embers)
	_smoke = FireMotes.create(24, FireKit.smoke_thin_material())
	_smoke.gravity = Vector3(0.0, 0.8, 0.0)
	_smoke.drag = 3.5
	_smoke.grow = 1.6
	add_child(_smoke)


## The bolt hit something or ran out: stop the ball, let the rest die out.
func finish() -> void:
	if _finished_at >= 0.0:
		return
	_finished_at = _time
	_shell.visible = false
	_licks.visible = false


func _process(delta: float) -> void:
	_time += delta
	if _finished_at < 0.0:
		_fly(delta)
	else:
		var after := _time - _finished_at
		_trail.set_instance_shader_parameter(&"fade", clampf(1.0 - after / 0.28, 0.0, 1.0))
		_light.light_energy = 2.2 * maxf(0.0, 1.0 - after / 0.1)
		if (after >= LINGER and _embers.alive() == 0 and _smoke.alive() == 0) or after >= LINGER * 2.0:
			queue_free()
			return
	_build_trail()


func _fly(delta: float) -> void:
	var head := global_position
	var forward := -global_basis.z.normalized()
	if not _path.is_empty():
		var last := _path[0]
		var step := head.distance_to(last)
		if step < 0.001:
			return
		_flown += step
		_shed(last, head, forward, delta)
	_path.insert(0, head)
	_path_time.insert(0, _time)
	_path_dist.insert(0, _flown)
	# keep one sample older than the trail, so its end can be cut exactly
	while _path.size() > 2 and _time - _path_time[_path.size() - 2] > TRAIL_TIME:
		_path.resize(_path.size() - 1)
		_path_time.resize(_path_time.size() - 1)
		_path_dist.resize(_path_dist.size() - 1)
	# flicker: the ball breathes and rolls about its flight line; it forms out
	# of the muzzle flash, so it starts small
	var launch := 0.45 + 0.55 * smoothstep(0.0, 0.08, _time)
	var breathe := 1.0 + 0.09 * sin(_time * 47.0) + 0.05 * randf()
	_shell.scale = Vector3.ONE * _radius * 1.15 * breathe * launch
	_licks.scale = Vector3.ONE * _radius * 1.7 * (2.0 - breathe) * launch
	_shell.rotate_object_local(Vector3.FORWARD, delta * 6.0)
	_licks.rotate_object_local(Vector3.FORWARD, -delta * 9.0)
	_light.light_energy = 2.2 * (0.82 + 0.3 * randf())


## Embers and smoke left behind along the stretch flown this frame.
func _shed(from: Vector3, to: Vector3, forward: Vector3, delta: float) -> void:
	_ember_debt += EMBERS_PER_SECOND * delta
	while _ember_debt >= 1.0:
		_ember_debt -= 1.0
		var at := from.lerp(to, randf()) + FireKit.random_unit() * _radius * 0.6
		var drift := FireKit.random_unit() * randf_range(0.8, 2.6) + forward * randf_range(1.0, 4.0)
		_embers.spawn(at, drift, randf_range(0.25, 0.6), randf_range(0.022, 0.045))
	_smoke_debt += SMOKE_PER_SECOND * delta
	while _smoke_debt >= 1.0:
		_smoke_debt -= 1.0
		var at := from.lerp(to, randf()) + FireKit.random_unit() * _radius * 0.4
		_smoke.spawn(at, FireKit.random_unit() * 0.4 + forward * 1.5, randf_range(0.3, 0.55), randf_range(0.09, 0.15))


## The flame trail: a ribbon along the recorded path, widest at the ball and
## tapering to a point, cut exactly TRAIL_TIME behind the head.
func _build_trail() -> void:
	_trail_mesh.clear_surfaces()
	var count := _path.size()
	if count < 2:
		return
	var now := _time if _finished_at < 0.0 else _finished_at
	_trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var direction := (_path[0] - _path[1]).normalized()
	for k in count:
		var point := _path[k]
		var distance := _path_dist[k]
		var age := (now - _path_time[k]) / TRAIL_TIME
		if k > 0 and age > 1.0:
			var newer_age := (now - _path_time[k - 1]) / TRAIL_TIME
			var cut := clampf((1.0 - newer_age) / maxf(age - newer_age, 0.0001), 0.0, 1.0)
			point = _path[k - 1].lerp(point, cut)
			distance = lerpf(_path_dist[k - 1], distance, cut)
			age = 1.0
		if k + 1 < count:
			var span := _path[k] - _path[k + 1]
			if span.length() > 0.0001:
				direction = span.normalized()
		var half_width := _radius * 1.05 * pow(clampf(1.0 - age, 0.0, 1.0), 0.75) + 0.015
		for side: float in [-1.0, 1.0]:
			_trail_mesh.surface_set_normal(direction)
			_trail_mesh.surface_set_uv(Vector2(distance, side))
			_trail_mesh.surface_set_uv2(Vector2(age, half_width))
			_trail_mesh.surface_add_vertex(point)
		if age >= 1.0:
			break
	_trail_mesh.surface_end()
