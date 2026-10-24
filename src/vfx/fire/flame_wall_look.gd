class_name FlameWallLook
extends Node3D
## The Flame Wall's fire, exactly the size of its burning area (local X along
## the wall, -Z the way it faces, Y up from the ground). It erupts from the
## centre out to both ends, then roars: flame tongues in toon heat bands over
## a bed of glowing embers, embers and sparks rising, smoke rolling off the
## top, two flickering lights. The flames stay partly see-through so a fighter
## behind them still reads. As it dies down it leaves a scorched strip with
## dying embers and smoke in the world. The wall drives set_intensity() every
## tick (0 out, 1 full blaze).

## Seconds the eruption takes to run from the centre to the ends.
const ERUPT_TIME := 0.2

var _length := 8.0
var _width := 1.2
var _height := 2.2
var _tongues: MultiMeshInstance3D
var _bed: MeshInstance3D
var _embers: GPUParticles3D
var _sparks: GPUParticles3D
var _smoke: GPUParticles3D
var _lamps: Array[OmniLight3D] = []
var _age := 0.0
var _intensity := 0.0
var _peak := 0.0
var _dying := false


func build(spell: FlameWallSpell) -> void:
	_length = spell.length
	_width = spell.width
	_height = spell.height
	_tongues = _build_tongues()
	add_child(_tongues)

	_bed = MeshInstance3D.new()
	var bed_mesh := PlaneMesh.new()
	bed_mesh.size = Vector2(_length, _width)
	_bed.mesh = bed_mesh
	_bed.material_override = FireKit.bed_material(Vector2(_length, _width))
	_bed.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bed.position = Vector3(0.0, 0.03, 0.0)
	_bed.set_instance_shader_parameter(&"intensity", 0.0)
	_bed.set_instance_shader_parameter(&"sweep", 0.0)
	add_child(_bed)

	var half := Vector3(_length * 0.5, 0.0, _width * 0.5)
	var ground := Vector3(half.x - 0.15, 0.1, half.z - 0.1)
	_embers = FireKit.box_particles(&"wall_embers", ground, FireKit.ember_material(), 64, 1.4)
	_embers.position = Vector3(0.0, 0.25, 0.0)
	_sparks = FireKit.box_particles(&"wall_sparks", ground, FireKit.spark_material(), 22, 0.6)
	_sparks.position = Vector3(0.0, 0.3, 0.0)
	_smoke = FireKit.box_particles(&"wall_smoke", Vector3(half.x - 0.6, 0.15, half.z - 0.2), FireKit.smoke_thin_material(), 10, 1.15)
	_smoke.position = Vector3(0.0, _height * 0.85, 0.0)
	var erupt := FireKit.box_particles(&"wall_erupt", ground, FireKit.spark_material(), 56, 0.75, true, 0.85)
	for system: GPUParticles3D in [_embers, _sparks, _smoke, erupt]:
		system.visibility_aabb = AABB(Vector3(-half.x - 1.5, -1.0, -half.z - 2.0), Vector3(_length + 3.0, _height + 4.0, _width + 4.0))
		add_child(system)

	for i in 2:
		var lamp := FireKit.light(0.0, 6.0)
		lamp.position = Vector3((i - 0.5) * _length * 0.5, 1.1, 0.0)
		_lamps.append(lamp)
		add_child(lamp)


## Main tongues down the middle, smaller licks along both long edges, all
## kept inside the burning area. Each erupts when the sweep reaches it.
func _build_tongues() -> MultiMeshInstance3D:
	var spots: Array[Transform3D] = []
	var data: Array[Color] = []
	var half_length := _length * 0.5
	# heights swell and dip along the wall, so it roars in surges rather than
	# standing like a picket fence
	var phase := randf() * TAU
	var main := maxi(roundi(_length / 0.5), 2)
	for i in main:
		var width := randf_range(0.95, 1.25)
		# a tongue's flame spans 85% of its quad at the base, whichever way the
		# quad turns: keep it inside the burning area
		var reach := half_length - width * 0.43
		var x := clampf(lerpf(-reach, reach, float(i) / (main - 1)) + randf_range(-0.12, 0.12), -reach, reach)
		var z := randf_range(-1.0, 1.0) * maxf(_width * 0.5 - width * 0.43, 0.0)
		var surge := 0.76 + 0.14 * sin(x * 1.15 + phase) + 0.08 * sin(x * 2.7 + phase * 2.0)
		# a tongue's flame fills about 80% of its quad's height: the tallest
		# tips lick up to the top of the 2.2 m burning area
		var size := Vector3(width, _height * clampf(surge + randf_range(-0.1, 0.1), 0.5, 1.0) * 1.2 * _end_taper(x), 1.0)
		spots.append(Transform3D(Basis.from_scale(size), Vector3(x, 0.0, z)))
		data.append(Color(randf(), _delay(x), 0.0, 0.0))
	var licks := maxi(roundi(_length / 0.62), 2)
	for side: float in [-1.0, 1.0]:
		for i in licks:
			var width := randf_range(0.7, 0.95)
			var reach := half_length - width * 0.43
			var x := clampf(lerpf(-reach, reach, (i + 0.25 + 0.5 * (side + 1.0) * 0.5) / licks) + randf_range(-0.12, 0.12), -reach, reach)
			var z := side * maxf(_width * 0.5 - width * 0.43, 0.0)
			var size := Vector3(width, _height * randf_range(0.5, 0.8) * _end_taper(x), 1.0)
			spots.append(Transform3D(Basis.from_scale(size), Vector3(x, 0.0, z)))
			data.append(Color(randf(), _delay(x), 0.0, 1.0))
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_custom_data = true
	multi.mesh = FireKit.standing_quad()
	multi.instance_count = spots.size()
	for i in spots.size():
		multi.set_instance_transform(i, spots[i])
		multi.set_instance_custom_data(i, data[i])
	var tongues := MultiMeshInstance3D.new()
	tongues.multimesh = multi
	tongues.material_override = FireKit.tongue_material()
	tongues.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# the quads turn to face the camera, so they reach past their resting box
	tongues.extra_cull_margin = 1.0
	tongues.set_instance_shader_parameter(&"intensity", 0.0)
	tongues.set_instance_shader_parameter(&"age", 0.0)
	return tongues


## Tongues dip toward the wall's ends, so seen along its length the wall
## ends in a ragged slope of flame instead of a sheer slab of stacked flames.
func _end_taper(x: float) -> float:
	var from_end := _length * 0.5 - absf(x)
	return lerpf(0.55, 1.0, smoothstep(0.3, 1.6, from_end))


## When the eruption reaches `x` along the wall.
func _delay(x: float) -> float:
	return absf(x) / (_length * 0.5) * ERUPT_TIME


func set_intensity(value: float) -> void:
	if not _dying and _peak >= 0.999 and value < _peak - 0.001:
		_dying = true
		_die_down()
	_peak = maxf(_peak, value)
	_intensity = value
	_tongues.set_instance_shader_parameter(&"intensity", value)
	_bed.set_instance_shader_parameter(&"intensity", value)


func _process(delta: float) -> void:
	_age += delta
	_tongues.set_instance_shader_parameter(&"age", _age)
	_bed.set_instance_shader_parameter(&"sweep", clampf(_age / ERUPT_TIME, 0.0, 1.0))
	for i in _lamps.size():
		var flicker := 0.8 + 0.15 * sin(_age * (17.0 + i * 6.0)) + 0.12 * randf()
		_lamps[i].light_energy = 2.6 * _intensity * flicker


## The last moments: no new embers or smoke from the wall itself; the
## scorched strip, its dying embers and its smoke carry on in the world after
## the wall is gone.
func _die_down() -> void:
	_embers.emitting = false
	_sparks.emitting = false
	_smoke.emitting = false
	var wall := get_parent()
	var world := wall.get_parent() if wall else null
	if world == null:
		return
	var where := global_transform
	FireScorch.strip(world, where, _length, _width)
	var ashes := Node3D.new()
	world.add_child(ashes)
	ashes.global_transform = where
	var ground := Vector3(_length * 0.5 - 0.3, 0.05, _width * 0.5 - 0.15)
	var embers := FireKit.box_particles(&"ash_embers", ground, FireKit.ember_material(), 40, 1.6, true, 0.6)
	var smoke := FireKit.box_particles(&"ash_smoke", ground, FireKit.smoke_ash_material(), 9, 1.4, true, 0.5)
	smoke.position = Vector3(0.0, 0.4, 0.0)
	for system: GPUParticles3D in [embers, smoke]:
		system.visibility_aabb = AABB(Vector3(-_length * 0.5 - 1.0, -0.5, -_width * 0.5 - 1.0), Vector3(_length + 2.0, 4.0, _width + 2.0))
		ashes.add_child(system)
	FireKit.free_after(ashes, 2.4)
