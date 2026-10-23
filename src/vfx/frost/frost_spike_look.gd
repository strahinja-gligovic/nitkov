class_name FrostSpikeLook
extends Node3D
## The Ice Spike in flight: one heavy faceted crystal spinning slowly around
## its line of flight, with a white-hot core glowing through the ice, a cold
## glint on its point, a frost-mist streak, and cold vapour and glitter shed
## along the way. The Projectile places this root every frame (-Z is the
## flight direction); everything here animates inside it. finish() hides the
## crystal and lets what it left behind fade before the look frees itself.

## Spin around the flight axis (rad/s).
const SPIN := 4.2
## Where the streak leaves the crystal, in the root's space.
const TAIL := Vector3(0.0, 0.0, 0.34)
## Metres of flight between shed vapour puffs, and between glitter specks.
const PUFF_EVERY := 0.95
const GLITTER_EVERY := 0.32
## Seconds the streak, vapour and glitter outlive the spike.
const LINGER := 0.6

var _crystal: MeshInstance3D
var _glint: MeshInstance3D
var _halo: MeshInstance3D
var _light: OmniLight3D
var _trail: FrostTrail
var _vapour: FrostBits
var _glitter: FrostBits
var _age := 0.0
var _travelled := 0.0
var _puff_debt := 0.0
var _glitter_debt := 0.0
var _last_tail := Vector3.ZERO
var _started := false
var _finished := false
var _linger := 0.0


func _init() -> void:
	name = "IceSpike"
	_crystal = MeshInstance3D.new()
	_crystal.mesh = FrostKit.spike_mesh()
	_crystal.material_override = FrostKit.spike_material()
	_crystal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_crystal.rotation.z = randf() * TAU
	add_child(_crystal)

	_glint = MeshInstance3D.new()
	_glint.mesh = FrostKit.quad_mesh()
	_glint.material_override = FrostKit.glint_material(true)
	_glint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glint.position = Vector3(0.0, 0.0, FrostKit.SPIKE_TIP + 0.02)
	add_child(_glint)

	# lights the tail for the caster's over-the-shoulder view (see the shader)
	_halo = MeshInstance3D.new()
	_halo.mesh = FrostKit.quad_mesh()
	_halo.material_override = FrostKit.halo_material()
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_halo.position = Vector3(0.0, 0.0, 0.3)
	_halo.scale = Vector3.ONE * 0.5
	add_child(_halo)

	_light = OmniLight3D.new()
	_light.light_color = FrostKit.COLOR
	_light.light_energy = 0.9
	_light.omni_range = 3.0
	_light.shadow_enabled = false
	_light.position = Vector3(0.0, 0.0, -0.1)
	add_child(_light)

	_trail = FrostTrail.new()
	add_child(_trail)

	_vapour = FrostBits.make(FrostBits.Kind.PUFF, 28)
	_vapour.pooled = true
	_vapour.top_level = true
	_vapour.drag = 2.0
	_vapour.gravity = 0.3
	_vapour.swell = 2.0
	add_child(_vapour)

	_glitter = FrostBits.make(FrostBits.Kind.SPARKLE, 48)
	_glitter.pooled = true
	_glitter.top_level = true
	_glitter.gravity = 0.6
	_glitter.drag = 1.8
	add_child(_glitter)


## The projectile is gone: stop drawing the crystal and fade what it left.
func finish() -> void:
	_finished = true
	_crystal.visible = false
	_glint.visible = false
	_halo.visible = false


func _process(delta: float) -> void:
	_age += delta
	if _finished:
		_linger += delta
		_light.light_energy = maxf(_light.light_energy - delta * 12.0, 0.0)
		if _linger >= LINGER:
			queue_free()
		return
	_crystal.rotation.z += SPIN * delta
	# it forms out of the release flash: swells into shape, white-hot for a beat
	var pop := clampf(_age / 0.05, 0.0, 1.0)
	_crystal.scale = Vector3.ONE * lerpf(0.5, 1.0, 1.0 - (1.0 - pop) * (1.0 - pop))
	_crystal.set_instance_shader_parameter(&"flash", (1.0 - pop) * 0.7)
	var twinkle := 0.8 + 0.2 * sin(_age * 47.0)
	_glint.scale = Vector3.ONE * 0.38 * twinkle * pop
	_glint.set_instance_shader_parameter(&"roll", _age * 2.5)
	_glint.set_instance_shader_parameter(&"brightness", 0.65)
	_halo.set_instance_shader_parameter(&"brightness", pop * (0.85 + 0.15 * sin(_age * 31.0)))
	var tail := global_transform * TAIL
	if _started:
		_shed(_last_tail, tail)
	_started = true
	_last_tail = tail
	_trail.add_point(tail, _travelled)


## Cold vapour and glitter falling off the crystal along this frame's stretch
## of flight, spaced by distance so the wake looks the same at any frame rate.
func _shed(from: Vector3, to: Vector3) -> void:
	var step := from.distance_to(to)
	_travelled += step
	if step <= 0.0001:
		return
	_puff_debt += step
	while _puff_debt >= PUFF_EVERY:
		_puff_debt -= PUFF_EVERY
		var at := to.lerp(from, _puff_debt / step) + FrostKit.random_direction() * 0.05
		var drift := FrostKit.random_direction() * randf_range(0.2, 0.5)
		_vapour.add(at, drift, Vector3.ONE * randf_range(0.13, 0.2), randf_range(0.2, 0.3))
	_glitter_debt += step
	while _glitter_debt >= GLITTER_EVERY:
		_glitter_debt -= GLITTER_EVERY
		var at := to.lerp(from, _glitter_debt / step) + FrostKit.random_direction() * randf_range(0.05, 0.18)
		var drift := FrostKit.random_direction() * randf_range(0.2, 0.8) + Vector3.DOWN * 0.3
		_glitter.add(at, drift, Vector3.ONE * randf_range(0.07, 0.12), randf_range(0.3, 0.55))
