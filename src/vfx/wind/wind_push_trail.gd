class_name WindPushTrail
extends Node3D
## Speed lines streaming off a fighter that a wind burst has blown away, with
## dust kicked up where they skid, so the shove reads at a glance. It follows
## `body` (the fighter's visual pivot, read only) while it's moving fast,
## then lets the lines fade and frees itself. Cosmetic only.

const LINE_SHADER := preload("res://src/vfx/wind/wind_line.gdshader")
const FOLLOW := 0.6
## Where the lines leave the body: sideways offset and height (metres).
const ANCHORS: Array[Vector2] = [Vector2(-0.3, 1.45), Vector2(0.32, 1.1), Vector2(-0.18, 0.55), Vector2(0.2, 1.75)]

static var _material: ShaderMaterial

var _body: Node3D
var _ribbons: Array[WindRibbon] = []
var _dust: WindParticles
var _floor_y := -INF
var _age := 0.0
var _last := Vector3.ZERO
var _next_dust := 0.0


## Starts trailing `body` (a fighter's visual pivot, origin at the feet).
static func follow(world: Node, body: Node3D, floor_y: float) -> void:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = LINE_SHADER
		_material.set_shader_parameter(&"energy", 1.3)
		_material.set_shader_parameter(&"dash_fill", 0.75)
		_material.set_shader_parameter(&"head_fade", 0.05)
		_material.set_shader_parameter(&"tail_fade", 0.5)
	var trail := WindPushTrail.new()
	trail._body = body
	trail._floor_y = floor_y
	trail._last = body.global_position
	world.add_child(trail)


func _ready() -> void:
	for anchor in ANCHORS:
		var ribbon := WindRibbon.spawn(self, _material, 0.22, randf_range(0.035, 0.06))
		ribbon.dash_length = randf_range(0.7, 1.2)
		_ribbons.append(ribbon)
	_dust = WindParticles.spawn(get_parent(), 16)
	_dust.floor_y = _floor_y
	_dust.hold = FOLLOW


func _process(delta: float) -> void:
	_age += delta
	if _age < FOLLOW and is_instance_valid(_body) and delta > 0.0:
		var at := _body.global_position
		var velocity := (at - _last) / delta
		_last = at
		var flat := Vector3(velocity.x, 0.0, velocity.z)
		if flat.length() > 2.0:
			var side := flat.normalized().cross(Vector3.UP)
			for i in ANCHORS.size():
				_ribbons[i].add(at + side * ANCHORS[i].x + Vector3.UP * ANCHORS[i].y)
			_next_dust -= delta
			if _next_dust <= 0.0 and at.y < _floor_y + 0.4:
				_next_dust = 0.05
				_kick_dust(at, flat)
	if _age > FOLLOW + 0.3:
		queue_free()


## Dust spraying up off the floor as the fighter skids along it.
func _kick_dust(at: Vector3, flat: Vector3) -> void:
	if not is_instance_valid(_dust):
		return
	for i in 2:
		var spread := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * 1.5
		_dust.emit(WindParticles.Kind.DUST, at + Vector3.UP * 0.15 + spread * 0.1,
				-flat * 0.15 + spread + Vector3.UP * randf_range(0.5, 1.5), randf_range(0.25, 0.4), randf_range(0.45, 0.65), 0.0, 1.2)
