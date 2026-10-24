class_name FireExplosion
extends Node3D
## A Firebolt bursting. A white-hot flash for a couple of frames, then a
## cluster of fireballs that swells to the splash radius with ease-out, rolls
## upward, cools through the bands and burns open from the middle into ragged
## rims; a shock ring races out, sparks and embers fly, a dark-edged smoke
## puff lingers, and a light flashes. On a wall or the floor it leaves a
## scorch mark. A fizzle (out of range) only gutters out in smoke. Local +Y is
## the surface normal (back along the flight for fighter hits and fizzles).

const LIFE := 1.6

var _age := 0.0
var _radius := 1.5
var _fizzle := false
var _struck := false
var _balls: Array[MeshInstance3D] = []
## Per ball: start delay, full radius, starting heat, offset from the centre.
var _ball_delay := PackedFloat32Array()
var _ball_size := PackedFloat32Array()
var _ball_heat := PackedFloat32Array()
var _ball_offset := PackedVector3Array()
var _flash: MeshInstance3D
var _ring: MeshInstance3D
var _light: OmniLight3D
var _up := Vector3.UP
var _smoke_at := 0.06
var _smoke_done := false


## The full explosion at `at`. `radius` is the splash radius; `struck` means
## it went off on a fighter's body (a little smaller, and it burns open sooner
## so the body reads through it; no scorch).
static func burst(world: Node, at: Vector3, normal: Vector3, radius: float, struck: bool) -> void:
	var blast := FireExplosion.new()
	blast._struck = struck
	blast._radius = radius * (0.8 if struck else 1.0)
	# lift it off a surface so the fireball isn't half buried
	var centre := at + normal.normalized() * (0.0 if struck else 0.3)
	world.add_child(blast)
	blast.global_transform = Transform3D(FireKit.basis_from_normal(normal), centre)
	blast._build_burst()
	if not struck:
		FireScorch.mark(world, at, normal, radius * 2.2)


## Out of range in mid-air: the fire gutters out in a puff of smoke.
static func fizzle(world: Node, at: Vector3, direction: Vector3) -> void:
	var puff := FireExplosion.new()
	puff._fizzle = true
	puff._radius = 0.3
	world.add_child(puff)
	puff.global_transform = Transform3D(FireKit.basis_from_normal(-direction), at)
	puff._build_fizzle()


func _build_burst() -> void:
	var r := _radius
	_up = global_basis.inverse() * Vector3.UP
	_add_ball(0.0, r * (0.62 if _struck else 0.56), 0.84, Vector3.ZERO)
	# lumpy satellites, spread around the core, give the blast a billowing
	# cauliflower outline instead of a round disc: out of a surface, or up
	# and to the sides of a body (never toward the shooter, where they'd hide
	# it). They go off a beat after the core, so the blast rolls outward.
	var spin := randf() * TAU
	for i in 6:
		var angle := spin + TAU * i / 6.0 + randf_range(-0.35, 0.35)
		var around := Vector3(cos(angle), 0.0, sin(angle))
		var offset: Vector3
		if _struck:
			# local Y is back toward the shooter: keep them in the body's plane
			offset = Vector3.UP.cross(_up).normalized() * around.x + _up * (around.z + 0.35)
		else:
			offset = around + Vector3.UP * randf_range(0.3, 0.8)
		var reach := randf_range(0.5, 0.68) if _struck else randf_range(0.66, 0.86)
		_add_ball(randf_range(0.015, 0.06), r * randf_range(0.32, 0.5), 0.74, offset.normalized() * r * reach)
	_flash = FireKit.card(FireKit.quad(), FireKit.flash_material())
	_flash.scale = Vector3.ONE * r * 1.6
	add_child(_flash)
	_ring = FireKit.card(FireKit.plane(), FireKit.ring_material())
	# the shock ring races out well past the fireball: hugging it, it framed
	# the blast like a hoop around a sun
	_ring.scale = Vector3.ONE * r * 1.8
	_ring.position = Vector3.UP * (0.0 if _struck else -0.25)
	add_child(_ring)
	if _struck:
		# around a body the ring lies flat, a hoop at the waist that reads from
		# any side; facing the shooter it would frame the blast like a disc
		_ring.global_basis = Basis.IDENTITY
		_ring.scale = Vector3.ONE * r * 1.6
	_light = FireKit.light(4.0, r * 4.0)
	# on a body, light it from the front instead of from inside
	_light.position = Vector3.UP * (0.7 if _struck else 0.2)
	add_child(_light)

	var sparks := FireKit.particles(FireKit.recipe(&"burst_sparks"), FireKit.spark_material(), 26, 0.55)
	add_child(sparks)
	var embers := FireKit.particles(FireKit.recipe(&"burst_embers"), FireKit.ember_material(), 16, 1.2)
	add_child(embers)


func _build_fizzle() -> void:
	_add_ball(0.0, _radius, 0.7, Vector3.ZERO)
	_balls[0].material_override = FireKit.ball_soft_material()
	_light = FireKit.light(1.5, 3.0)
	add_child(_light)
	var embers := FireKit.particles(FireKit.recipe(&"fizzle_embers"), FireKit.ember_material(), 8, 0.7)
	add_child(embers)
	_smoke_at = 0.0


func _add_ball(delay: float, size: float, heat: float, offset: Vector3) -> void:
	var ball := FireKit.ball(0.01, heat, -1.0, true)
	ball.set_instance_shader_parameter(&"boil", 0.2)
	ball.set_instance_shader_parameter(&"flow", 1.6)
	ball.visible = false
	add_child(ball)
	_balls.append(ball)
	_ball_delay.append(delay)
	_ball_size.append(size)
	_ball_heat.append(heat)
	_ball_offset.append(offset)


func _process(delta: float) -> void:
	_age += delta
	if _fizzle:
		_animate_fizzle()
	else:
		_animate_burst()
	if not _smoke_done and _age >= _smoke_at:
		_smoke_done = true
		_puff()
	if _age >= LIFE:
		queue_free()


func _animate_burst() -> void:
	# on a body it burns open fast, so the target shows through within ~0.15 s
	var open_end := 0.25 if _struck else 0.5
	var soft_at := 0.06 if _struck else 0.1
	for i in _balls.size():
		var ball := _balls[i]
		var t := _age - _ball_delay[i]
		if t < 0.0:
			continue
		if t > open_end:
			ball.visible = false
			continue
		ball.visible = true
		# swell with ease-out, keep rolling outward a little, rise as it burns
		var swell := 1.0 - pow(1.0 - clampf(t / 0.1, 0.0, 1.0), 3.0)
		var size := _ball_size[i] * (0.25 + 0.75 * swell + 0.25 * t)
		ball.scale = Vector3.ONE * size
		ball.position = _ball_offset[i] * (0.35 + 0.65 * swell) + _up * (t * t * 2.0)
		# white-hot for a blink, then it cools fast into yellow and orange with
		# a red rim: an explosion of fire, not a pale ball of popcorn
		var heat := _ball_heat[i] + 0.12 * (1.0 - smoothstep(0.0, 0.05, t)) - 0.22 * smoothstep(0.03, 0.14, t) - 0.7 * t
		ball.set_instance_shader_parameter(&"heat", heat)
		# once it starts to burn open, out of the ink outline's sight: in the
		# opaque pass every torn scrap got its own outline (black confetti)
		if t > soft_at and ball.material_override != FireKit.ball_soft_material():
			ball.material_override = FireKit.ball_soft_material()
		ball.set_instance_shader_parameter(&"dissolve", smoothstep(0.03 if _struck else 0.05, open_end, t))
		# the cool bands burn away as it opens, so no dark shards are left
		ball.set_instance_shader_parameter(&"burnout", smoothstep(0.08, open_end, t))
	_flash.visible = _age < 0.06
	_flash.set_instance_shader_parameter(&"progress", clampf(_age / 0.06, 0.0, 1.0))
	_ring.visible = _age < 0.24
	# front-loaded, so the ring breaks away from the fireball at once
	_ring.set_instance_shader_parameter(&"progress", pow(clampf(_age / 0.24, 0.0, 1.0), 0.7))
	var fade := maxf(0.0, 1.0 - _age / 0.4)
	_light.light_energy = 4.0 * fade * fade


func _animate_fizzle() -> void:
	var ball := _balls[0]
	var t := _age
	ball.visible = t < 0.3
	ball.scale = Vector3.ONE * _radius * maxf(0.05, 1.0 - t / 0.3) * (1.0 + 0.15 * sin(t * 60.0))
	ball.set_instance_shader_parameter(&"heat", 0.6 - t * 1.6)
	ball.set_instance_shader_parameter(&"dissolve", smoothstep(0.0, 0.3, t))
	_light.light_energy = 1.5 * maxf(0.0, 1.0 - t / 0.25)


## The smoke that lingers after the fire: dark-edged puffs that billow and
## rise (above a body, so they don't hang in front of it).
func _puff() -> void:
	var smoke: GPUParticles3D
	if _fizzle:
		smoke = FireKit.particles(FireKit.recipe(&"fizzle_smoke"), FireKit.smoke_material(), 5, 1.0, true, 0.8)
	else:
		smoke = FireKit.particles(FireKit.recipe(&"burst_smoke"), FireKit.smoke_material(), 5 if _struck else 7, 1.1, true, 0.9)
	add_child(smoke)
	smoke.global_position = global_position + Vector3.UP * (1.2 if _struck else 0.25)
