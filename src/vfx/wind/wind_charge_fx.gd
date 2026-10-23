class_name WindChargeFx
extends Node3D
## Wind gathering in the casting hand during a windup: streak spirals that
## wind in and tighten, motes sucked into the fist and, for the Wind Spear, a
## second counter-turning spiral and a javelin of air condensing along the
## throw. It hangs off the hand (the gauntlet core) but keeps its own size
## and faces along the caster's forward, and it frees itself when the windup
## is over (or would have been, if the cast was cut short). Cosmetic only.

const LINE_SHADER := preload("res://src/vfx/wind/wind_line.gdshader")
const VORTEX_SHADER := preload("res://src/vfx/wind/wind_vortex.gdshader")

static var _meshes := {}
static var _materials := {}

var seconds := 0.2
var signature := false

var _age := 0.0
var _fighter: Fighter
var _spirals: Array[MeshInstance3D] = []
var _spear: MeshInstance3D
var _bits: MultiMeshInstance3D
var _seeds := PackedFloat32Array()
var _spin := 0.0


static func attach(hand: Node3D, windup: float, is_signature: bool) -> void:
	if not is_instance_valid(hand):
		return
	var fx := WindChargeFx.new()
	fx.seconds = maxf(windup, 0.05)
	fx.signature = is_signature
	hand.add_child(fx)


func _ready() -> void:
	_build_shared()
	var node := get_parent()
	while node and not (node is Fighter):
		node = node.get_parent()
	_fighter = node as Fighter
	var spiral := MeshInstance3D.new()
	spiral.mesh = _meshes[&"spiral_big" if signature else &"spiral"]
	spiral.material_override = _materials[&"spiral"]
	spiral.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(spiral)
	_spirals.append(spiral)
	if signature:
		var outer := MeshInstance3D.new()
		outer.mesh = _meshes[&"spiral_big"]
		outer.material_override = _materials[&"spiral_faint"]
		outer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		outer.scale = Vector3(-1.45, 1.45, 1.45)  # mirrored: it turns the other way
		add_child(outer)
		_spirals.append(outer)
		_spear = MeshInstance3D.new()
		_spear.mesh = _meshes[&"javelin"]
		_spear.material_override = _materials[&"javelin"]
		_spear.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_spear.scale = Vector3(1.0, 1.0, 0.05)
		add_child(_spear)
	var count := 14 if signature else 8
	_bits = MultiMeshInstance3D.new()
	_bits.multimesh = WindParticles.make_multimesh(count)
	_bits.material_override = WindParticles.shared_material()
	_bits.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bits.extra_cull_margin = 1.0
	add_child(_bits)
	for i in count:
		_seeds.append(randf())
	_update(0.0)


func _process(delta: float) -> void:
	_age += delta
	if _age >= seconds + 0.02:
		queue_free()
		return
	_update(delta)


func _update(delta: float) -> void:
	var t := clampf(_age / seconds, 0.0, 1.0)
	var forward := -(get_parent() as Node3D).global_basis.z
	if is_instance_valid(_fighter):
		forward = _fighter.forward()
	if forward.length() < 0.01:
		forward = Vector3.FORWARD
	# own size and facing, whatever the hand's bone is doing
	global_basis = Basis.looking_at(forward.normalized(), Vector3.UP)
	var fade := minf(t * 5.0, 1.0)
	var tighten := lerpf(1.0, 0.3, t * t)
	_spin += delta * TAU * lerpf(1.5, 4.0, t)
	for i in _spirals.size():
		var spiral := _spirals[i]
		var mirror := -1.0 if i == 1 else 1.0
		var size := tighten * (1.45 if i == 1 else 1.0)
		spiral.scale = Vector3(size * mirror, size, size)
		spiral.rotation.z = _spin * mirror * (0.7 if i == 1 else 1.0)
		spiral.set_instance_shader_parameter(&"anim_time", _age)
		spiral.set_instance_shader_parameter(&"fade", fade * (0.6 + 0.4 * t))
	if _spear:
		# the javelin condenses along the throw as the arm draws back
		var grow := smoothstep(0.15, 0.9, t)
		_spear.scale = Vector3(lerpf(0.4, 1.0, grow), lerpf(0.4, 1.0, grow), maxf(grow, 0.05))
		_spear.set_instance_shader_parameter(&"anim_time", _age)
		_spear.set_instance_shader_parameter(&"fade", grow)
	_place_bits(t)


## Motes (and, for the spear, a few leaves) spiralling into the fist.
func _place_bits(t: float) -> void:
	var multimesh := _bits.multimesh
	var reach := 1.1 if signature else 0.55
	for i in _seeds.size():
		var random := _seeds[i]
		var leaf := signature and i < 3
		var cycle := fposmod(random * 3.1 + _age * (2.2 if signature else 5.5), 1.0)
		var radius := reach * (1.0 - cycle) * lerpf(1.0, 0.6, t)
		var angle := random * TAU + cycle * 4.5
		var at := Vector3(cos(angle) * radius, sin(angle) * radius, (1.0 - cycle) * 0.25)
		var alpha := minf(cycle * 4.0, 1.0) * (1.0 - cycle * cycle) * minf(t * 6.0, 1.0)
		var basis := Basis.IDENTITY.scaled(Vector3.ONE * (0.045 if not leaf else 0.13))
		if leaf:
			basis = Basis(Vector3(random, 1.0, 0.3).normalized(), _age * 14.0 + random * TAU).scaled(Vector3.ONE * 0.13)
		multimesh.set_instance_transform(i, Transform3D(basis, at))
		var kind := WindParticles.Kind.LEAF if leaf else WindParticles.Kind.MOTE
		multimesh.set_instance_custom_data(i, WindParticles.custom(kind, cycle, random, alpha))
	multimesh.visible_instance_count = _seeds.size()


static func _build_shared() -> void:
	if not _meshes.is_empty():
		return
	_meshes[&"spiral"] = _spiral_mesh(3, 0.45, 1.1, 0.04)
	_meshes[&"spiral_big"] = _spiral_mesh(4, 0.8, 1.2, 0.055)
	_meshes[&"javelin"] = WindMeshes.lathe(PackedVector2Array([Vector2(-0.75, 0.0), Vector2(-0.55, 0.05),
			Vector2(-0.3, 0.08), Vector2(0.1, 0.07), Vector2(0.45, 0.04), Vector2(0.7, 0.0)]), 10)
	var spiral := ShaderMaterial.new()
	spiral.shader = LINE_SHADER
	spiral.set_shader_parameter(&"energy", 1.6)
	spiral.set_shader_parameter(&"dash_fill", 0.6)
	spiral.set_shader_parameter(&"scroll", 7.0)
	spiral.set_shader_parameter(&"head_fade", 0.2)
	spiral.set_shader_parameter(&"tail_fade", 0.8)
	_materials[&"spiral"] = spiral
	var faint := spiral.duplicate() as ShaderMaterial
	faint.set_shader_parameter(&"energy", 0.9)
	faint.set_shader_parameter(&"dash_fill", 0.45)
	_materials[&"spiral_faint"] = faint
	var javelin := ShaderMaterial.new()
	javelin.shader = VORTEX_SHADER
	javelin.set_shader_parameter(&"strands", 2.0)
	javelin.set_shader_parameter(&"twist", 3.0)
	javelin.set_shader_parameter(&"speed", 4.0)
	javelin.set_shader_parameter(&"band_fill", 0.45)
	javelin.set_shader_parameter(&"energy", 1.8)
	javelin.set_shader_parameter(&"body_alpha", 0.35)
	javelin.set_shader_parameter(&"front_fade", 0.15)
	javelin.set_shader_parameter(&"back_fade", 0.6)
	_materials[&"javelin"] = javelin


## `arms` streak spirals winding in from `reach` to the centre over `turns`,
## in the XY plane (a shallow funnel toward -Z). Each line runs from its
## outer end (head) to the centre, so dashes scroll inward.
static func _spiral_mesh(arms: int, reach: float, turns: float, width: float) -> ArrayMesh:
	var paths: Array[PackedVector3Array] = []
	var widths := PackedFloat32Array()
	for arm in arms:
		var path := PackedVector3Array()
		for k in 21:
			var u := 1.0 - float(k) / 20.0  # 1 outside .. 0 at the centre
			var angle := arm * TAU / arms + (1.0 - u) * turns * TAU
			var radius := reach * lerpf(0.06, 1.0, pow(u, 0.85))
			path.append(Vector3(cos(angle) * radius, sin(angle) * radius, -0.12 * (1.0 - u)))
		paths.append(path)
		widths.append(width)
	return WindMeshes.lines(paths, widths, 0.18)
