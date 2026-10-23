class_name FireCharge
extends Node3D
## Fire gathering in the casting fist over the wind-up: a roiling ball that
## swells and heats up, sparks spiralling in from around the hand, and for a
## signature a crown of flames licking up off the fist and a growing light.
## Parented to the gauntlet core, so it follows the animated hand; it ends on
## its own when the wind-up would, interrupted or not.

var _seconds := 0.15
var _signature := false
var _age := 0.0
var _ball: MeshInstance3D
var _sparks: FireMotes
var _crown: MultiMeshInstance3D
var _light: OmniLight3D
var _spark_debt := 0.0
## Ball radius in metres at full charge (before the gauntlet's own swell).
var _size := 0.1


static func start(hand: Node3D, seconds: float, signature: bool) -> void:
	var charge := FireCharge.new()
	charge._seconds = maxf(seconds, 0.05)
	charge._signature = signature
	charge._size = 0.15 if signature else 0.1
	hand.add_child(charge)
	# work in metres whatever the rig's scale
	var hand_scale := hand.global_basis.get_scale()
	var undo := 1.0 / maxf(hand_scale.x, 0.0001)
	charge.scale = Vector3.ONE * undo
	charge._build()


func _build() -> void:
	_ball = FireKit.ball(0.01, 0.9)
	_ball.set_instance_shader_parameter(&"boil", 0.28)
	_ball.set_instance_shader_parameter(&"flow", 3.0)
	add_child(_ball)
	_sparks = FireMotes.create(24, FireKit.spark_cpu_material())
	_sparks.attractor = self
	_sparks.pull = 140.0
	_sparks.drag = 5.0
	_sparks.gravity = Vector3.ZERO
	_sparks.streak = 0.02
	add_child(_sparks)
	if _signature:
		_crown = _build_crown()
		add_child(_crown)
		_light = FireKit.light(0.0, 3.5)
		add_child(_light)


## Three small flame tongues standing on the fist (the Flame Wall's tongue
## shader, upright in the world whatever the hand does).
func _build_crown() -> MultiMeshInstance3D:
	var crown := MultiMeshInstance3D.new()
	crown.top_level = true
	crown.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_custom_data = true
	multi.mesh = FireKit.standing_quad()
	multi.instance_count = 3
	for i in 3:
		var angle := TAU * i / 3.0
		var spot := Vector3(cos(angle), 0.0, sin(angle)) * 0.07
		multi.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(0.26, 0.42, 1.0)), spot + Vector3.DOWN * 0.05))
		multi.set_instance_custom_data(i, Color(randf(), 0.0, 0.0, 1.0))
	crown.multimesh = multi
	crown.material_override = FireKit.tongue_material()
	crown.extra_cull_margin = 0.5
	crown.set_instance_shader_parameter(&"intensity", 0.0)
	crown.set_instance_shader_parameter(&"age", 10.0)
	return crown


func _process(delta: float) -> void:
	_age += delta
	var k := clampf(_age / _seconds, 0.0, 1.0)
	# swell, quickening toward the release
	var swell := k * k * (3.0 - 2.0 * k)
	var flicker := 1.0 + 0.12 * sin(_age * 55.0) + 0.06 * randf()
	_ball.scale = Vector3.ONE * _size * (0.45 + 0.55 * swell) * flicker
	# heats up but stays fire: a white heart inside yellow and orange bands
	# (any hotter and it blooms into a featureless white blob)
	_ball.set_instance_shader_parameter(&"heat", 0.6 + 0.32 * k)
	var spark_rate := 90.0 if _signature else 70.0
	_spark_debt += spark_rate * delta * (1.0 - k * 0.5)
	var centre := global_position
	while _spark_debt >= 1.0 and k < 0.85:
		_spark_debt -= 1.0
		var out := FireKit.random_unit()
		var reach := randf_range(0.25, 0.45) * (1.3 if _signature else 1.0)
		var swirl := out.cross(Vector3.UP).normalized() * randf_range(2.0, 4.0)
		_sparks.spawn(centre + out * reach, swirl, _seconds, randf_range(0.012, 0.022))
	if _crown:
		_crown.global_transform = Transform3D(Basis.IDENTITY, centre)
		_crown.set_instance_shader_parameter(&"intensity", swell)
		_light.light_energy = 2.5 * swell * flicker
	if _age >= _seconds + 0.03:
		queue_free()
