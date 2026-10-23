class_name FrostCharge
extends Node3D
## Frost's charge-up in the casting fist (under the gauntlet core): ice
## crystals form around it, pointing outward and slowly turning, while cold
## mist spirals in and a glint swells at the centre. They all flash white
## at the very end, as the spell lets go. It can't tell whether the cast is
## cut short, so it simply frees itself after `seconds`.

var seconds := 0.15
var signature := false

var _time := 0.0
var _crystals: MultiMeshInstance3D
var _motes: MultiMeshInstance3D
var _glint: MeshInstance3D
var _roots: Array[Transform3D] = []
var _starts := PackedFloat32Array()
var _seeds := PackedFloat32Array()
var _turn_axis := Vector3.UP
var _mote_angle := PackedFloat32Array()
var _mote_radius := PackedFloat32Array()
var _mote_height := PackedFloat32Array()
var _mote_start := PackedFloat32Array()
var _mote_size := PackedFloat32Array()
var _mote_seed := PackedFloat32Array()


## Starts a charge in `hand` lasting `windup` seconds.
static func attach(hand: Node3D, windup: float, is_signature: bool) -> FrostCharge:
	var charge := FrostCharge.new()
	charge.name = "FrostCharge"
	charge.seconds = maxf(windup, 0.08)
	charge.signature = is_signature
	charge._build()
	hand.add_child(charge)
	charge._keep_size()
	return charge


func _build() -> void:
	var count := 10 if signature else 7
	var reach := Vector2(0.14, 0.25) if signature else Vector2(0.09, 0.15)
	var girth := Vector2(0.024, 0.038) if signature else Vector2(0.016, 0.026)
	var twist := Basis(FrostKit.random_direction(), randf() * TAU)
	_turn_axis = FrostKit.random_direction()
	_crystals = MultiMeshInstance3D.new()
	_crystals.multimesh = _multimesh(FrostKit.growth_mesh(), count)
	_crystals.material_override = FrostKit.growth_material(true)
	_crystals.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_crystals)
	for i in count:
		# spread evenly over a sphere (golden spiral), then turned at random
		var y := 1.0 - 2.0 * (i + 0.5) / count
		var ring := sqrt(maxf(1.0 - y * y, 0.0))
		var angle := i * 2.39996
		var out := twist * Vector3(cos(angle) * ring, y, sin(angle) * ring)
		_roots.append(FrostCrystals.root_at(out * 0.035, out, randf_range(reach.x, reach.y), randf_range(girth.x, girth.y)))
		_starts.append(randf_range(0.0, 0.42) * seconds)
		_seeds.append(randf())

	var motes := 16 if signature else 10
	var spread := Vector2(0.4, 0.62) if signature else Vector2(0.24, 0.36)
	_motes = MultiMeshInstance3D.new()
	_motes.multimesh = _multimesh(FrostKit.quad_mesh(), motes)
	_motes.material_override = FrostKit.puff_material()
	_motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_motes)
	for i in motes:
		_mote_angle.append(TAU * i / motes + randf_range(-0.3, 0.3))
		_mote_radius.append(randf_range(spread.x, spread.y))
		_mote_height.append(randf_range(-0.18, 0.18) * (1.5 if signature else 1.0))
		_mote_start.append(randf_range(0.0, 0.5) * seconds)
		_mote_size.append(randf_range(0.08, 0.13) if signature else randf_range(0.055, 0.09))
		_mote_seed.append(randf())

	_glint = MeshInstance3D.new()
	_glint.mesh = FrostKit.quad_mesh()
	_glint.material_override = FrostKit.glint_material(true)
	_glint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glint.scale = Vector3.ONE * 0.01
	add_child(_glint)


static func _multimesh(mesh: Mesh, count: int) -> MultiMesh:
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.use_custom_data = true
	instances.mesh = mesh
	instances.instance_count = count
	for i in count:
		instances.set_instance_transform(i, Transform3D(FrostCrystals.HIDDEN_BASIS, Vector3.ZERO))
	return instances


func _process(delta: float) -> void:
	_time += delta
	var u := _time / seconds
	if u >= 1.0 or not is_instance_valid(get_parent()):
		queue_free()
		return
	_keep_size()
	_crystals.rotate(_turn_axis, delta * 2.6)
	var release_flash := smoothstep(0.8, 1.0, u)
	var crystals := _crystals.multimesh
	for i in _roots.size():
		var t := _time - _starts[i]
		if t <= 0.0:
			continue
		var g := clampf(t / (seconds * 0.42), 0.0, 1.0)
		var height := FrostCrystals._ease_out_back(g)
		var girth := lerpf(0.4, 1.0, minf(g * 1.5, 1.0))
		crystals.set_instance_transform(i, Transform3D(_roots[i].basis * Basis.from_scale(Vector3(girth, height, girth)), _roots[i].origin))
		var birth := clampf(1.0 - t / 0.06, 0.0, 1.0)
		crystals.set_instance_custom_data(i, Color(0.0, maxf(birth, release_flash), 0.0, _seeds[i]))

	var motes := _motes.multimesh
	for i in _mote_angle.size():
		var t := _time - _mote_start[i]
		if t <= 0.0:
			continue
		# spiral in so every mote reaches the fist just before the release
		var v := clampf(t / maxf(seconds * 0.95 - _mote_start[i], 0.01), 0.0, 1.0)
		var pull := pow(1.0 - v, 1.3)
		var angle := _mote_angle[i] + 5.5 * v
		var at := Vector3(cos(angle) * _mote_radius[i] * pull, _mote_height[i] * pull, sin(angle) * _mote_radius[i] * pull)
		var size := _mote_size[i] * lerpf(1.0, 0.45, v)
		var opacity := clampf(v / 0.15, 0.0, 1.0) * (1.0 - smoothstep(0.85, 1.0, v))
		motes.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * size), at))
		motes.set_instance_custom_data(i, Color(0.12 + 0.5 * v, _mote_seed[i], opacity, 0.0))

	var peak := 0.45 if signature else 0.32
	_glint.scale = Vector3.ONE * peak * u * u * (0.85 + 0.15 * sin(_time * 50.0))
	_glint.set_instance_shader_parameter(&"brightness", 0.4 + 0.6 * u)
	_glint.set_instance_shader_parameter(&"roll", _time * 4.0)


## Keeps a constant size while FighterVisual swells the gauntlet core.
func _keep_size() -> void:
	var parent := get_parent() as Node3D
	if parent == null:
		return
	var parent_scale := parent.global_basis.get_scale().x
	scale = Vector3.ONE / maxf(parent_scale, 0.01)
