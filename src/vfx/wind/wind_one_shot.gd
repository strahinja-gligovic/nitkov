class_name WindOneShot
extends Node3D
## Plays a set of shader-driven parts once, then frees itself. Each part's
## `progress` instance uniform runs 0..1 over its own delay and duration (the
## part is hidden before and after); lights fade out over theirs. Wind's
## bursts, splashes, gusts and flashes are built from these. Cosmetic only.

var _parts: Array[GeometryInstance3D] = []
var _delays := PackedFloat32Array()
var _durations := PackedFloat32Array()
var _starts := PackedVector3Array()
var _travels := PackedVector3Array()
var _lights: Array[OmniLight3D] = []
var _energies := PackedFloat32Array()
var _light_lives := PackedFloat32Array()
var _age := 0.0
var _life := 0.0


## An empty one-shot in `world` at `at`, facing along `basis`.
static func spawn(world: Node, at: Vector3, basis := Basis.IDENTITY) -> WindOneShot:
	var shot := WindOneShot.new()
	world.add_child(shot)
	shot.global_transform = Transform3D(basis, at)
	return shot


## Adds `part` (placed in this node's space) and plays it from `delay` for
## `duration` seconds.
func add(part: GeometryInstance3D, delay: float, duration: float) -> GeometryInstance3D:
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	part.visible = delay <= 0.0
	part.set_instance_shader_parameter(&"progress", 0.0)
	add_child(part)
	_parts.append(part)
	_delays.append(delay)
	_durations.append(maxf(duration, 0.01))
	_starts.append(part.position)
	_travels.append(Vector3.ZERO)
	_life = maxf(_life, delay + duration)
	return part


## Like add(), but the part also glides `travel` (in this node's space) over
## its life with an ease-out, so a gust ring is blown away from where it
## started instead of hanging there.
func add_moving(part: GeometryInstance3D, delay: float, duration: float, travel: Vector3) -> GeometryInstance3D:
	add(part, delay, duration)
	_travels[_travels.size() - 1] = travel
	return part


## A light at `offset` that fades from `energy` to nothing over `duration`.
func add_light(color: Color, energy: float, reach: float, duration: float, offset := Vector3.ZERO) -> void:
	var lamp := OmniLight3D.new()
	lamp.light_color = color
	lamp.light_energy = energy
	lamp.omni_range = reach
	lamp.shadow_enabled = false
	lamp.position = offset
	add_child(lamp)
	_lights.append(lamp)
	_energies.append(energy)
	_light_lives.append(maxf(duration, 0.01))
	_life = maxf(_life, duration)


func _process(delta: float) -> void:
	_age += delta
	for i in _parts.size():
		var t := (_age - _delays[i]) / _durations[i]
		var part := _parts[i]
		part.visible = t >= 0.0 and t <= 1.0
		if part.visible:
			part.set_instance_shader_parameter(&"progress", t)
			if _travels[i] != Vector3.ZERO:
				part.position = _starts[i] + _travels[i] * (1.0 - pow(1.0 - t, 2.0))
	for i in _lights.size():
		var left := 1.0 - clampf(_age / _light_lives[i], 0.0, 1.0)
		_lights[i].light_energy = _energies[i] * left * left
	if _age > _life:
		queue_free()
