class_name FireMuzzle
extends Node3D
## Fire leaving the fist: a white-hot flash for a few frames, a jet of flame
## punching forward, a ring of fire around the fist, a spray of sparks, a
## light, and a puff of smoke that lingers. The Flame Wall's throw is bigger.

const LIFE := 1.0

var _age := 0.0
var _size := 1.0
var _flash: MeshInstance3D
var _jet: MeshInstance3D
var _ring: MeshInstance3D
var _light: OmniLight3D


static func fire(world: Node, at: Vector3, direction: Vector3, signature: bool) -> void:
	var muzzle := FireMuzzle.new()
	muzzle._size = 1.6 if signature else 1.0
	world.add_child(muzzle)
	var aim := direction.normalized() if direction.length() > 0.01 else Vector3.FORWARD
	# +Z along the aim: the ball shader streams its tail toward +Z
	muzzle.global_transform = Transform3D(Basis.looking_at(-aim, Vector3.UP), at)
	muzzle._build(signature)


func _build(signature: bool) -> void:
	var s := _size
	_flash = FireKit.card(FireKit.quad(), FireKit.flash_material())
	_flash.scale = Vector3.ONE * 0.55 * s
	add_child(_flash)
	_jet = FireKit.ball(0.01, 1.05)
	_jet.set_instance_shader_parameter(&"stretch", 2.6)
	_jet.set_instance_shader_parameter(&"boil", 0.25)
	_jet.set_instance_shader_parameter(&"flow", 3.0)
	add_child(_jet)
	_ring = FireKit.card(FireKit.plane(), FireKit.ring_material())
	# the ring's plane faces along the aim
	_ring.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	_ring.position = Vector3(0.0, 0.0, 0.12 * s)
	_ring.scale = Vector3.ONE * 0.34 * s
	add_child(_ring)
	_light = FireKit.light(4.0 * s, 3.5 * s)
	add_child(_light)

	var sparks := FireKit.particles(FireKit.recipe(&"muzzle_sparks"), FireKit.spark_material(), 18 if signature else 10, 0.35)
	sparks.rotation = Vector3(PI * 0.5, 0.0, 0.0)  # local +Y onto +Z, the aim
	add_child(sparks)
	var smoke := FireKit.particles(FireKit.recipe(&"muzzle_smoke"), FireKit.smoke_thin_material(), 4 if signature else 3, 0.75, true, 0.7)
	smoke.scale = Vector3.ONE * (1.2 if signature else 1.0)
	add_child(smoke)


func _process(delta: float) -> void:
	_age += delta
	var s := _size
	# 3 frames of flash
	_flash.visible = _age < 0.05
	_flash.set_instance_shader_parameter(&"progress", clampf(_age / 0.05, 0.0, 1.0))
	# the jet punches out, then burns away from the middle
	var t := _age
	_jet.visible = t < 0.22
	var punch := 1.0 - pow(1.0 - clampf(t / 0.05, 0.0, 1.0), 3.0)
	_jet.scale = Vector3.ONE * 0.14 * s * (0.4 + 0.6 * punch)
	_jet.position = Vector3(0.0, 0.0, 0.1 * s * punch)
	_jet.set_instance_shader_parameter(&"heat", 1.05 - t * 3.0)
	_jet.set_instance_shader_parameter(&"dissolve", smoothstep(0.03, 0.22, t))
	# burning open: out of the ink outline's sight (no black scraps)
	if t > 0.045 and _jet.material_override != FireKit.ball_soft_material():
		_jet.material_override = FireKit.ball_soft_material()
	# a quick snap of a ring: lingering, it reads as a hoop around the fist
	_ring.visible = t < 0.11
	_ring.set_instance_shader_parameter(&"progress", clampf(t / 0.11, 0.0, 1.0))
	var fade := maxf(0.0, 1.0 - t / 0.16)
	_light.light_energy = 4.0 * s * fade * fade
	if _age >= LIFE:
		queue_free()
