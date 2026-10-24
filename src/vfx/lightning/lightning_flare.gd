class_name LightningFlare
extends MeshInstance3D
## An electric flash facing the camera (lightning_flare.gdshader): a
## white-hot core in a jagged star. spawn() makes a one-shot that pops out
## and burns down over its life, then frees itself; attach() makes a held
## glow that an owner drives (the bolt's head, a charging hand). Parented to
## a moving node, it rides along.

const SHADER := preload("res://src/vfx/lightning/lightning_flare.gdshader")

static var _quad: QuadMesh
static var _material: ShaderMaterial

var life := 0.06
var _age := 0.0


static func spawn(parent: Node, at: Vector3, size: float, life_seconds := 0.06, tint := LightningFx.COLOR,
		strength := 1.0) -> LightningFlare:
	var flare := _make(size, tint, strength)
	flare.life = maxf(life_seconds, 0.001)
	parent.add_child(flare)
	flare.global_position = at
	flare.scale = Vector3.ONE * size
	return flare


## A held flare at `parent`'s origin that never burns down on its own: set
## its look with show_state() and free it yourself.
static func attach(parent: Node3D, size: float, tint := LightningFx.COLOR, strength := 1.0) -> LightningFlare:
	var flare := _make(size, tint, strength)
	flare.life = INF
	flare.set_instance_shader_parameter(&"progress", 0.15)
	parent.add_child(flare)
	flare.scale = Vector3.ONE * size
	return flare


static func _make(size: float, tint: Color, strength: float) -> LightningFlare:
	if _material == null:
		_quad = QuadMesh.new()
		_material = ShaderMaterial.new()
		_material.shader = SHADER
	var flare := LightningFlare.new()
	flare.mesh = _quad
	flare.material_override = _material
	flare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flare.extra_cull_margin = size
	flare.set_instance_shader_parameter(&"tint", tint)
	flare.set_instance_shader_parameter(&"strength", strength)
	flare.set_instance_shader_parameter(&"seed", randf())
	flare.set_instance_shader_parameter(&"progress", 0.0)
	return flare


## For a held flare: how far it has burnt (0 fresh .. 1 gone), how bright,
## and a new spike pattern if `reshape`.
func show_state(progress: float, strength: float, reshape := false) -> void:
	set_instance_shader_parameter(&"progress", progress)
	set_instance_shader_parameter(&"strength", strength)
	if reshape:
		set_instance_shader_parameter(&"seed", randf())


func _process(delta: float) -> void:
	if life == INF:
		return
	_age += delta
	if _age >= life:
		queue_free()
		return
	set_instance_shader_parameter(&"progress", _age / life)
