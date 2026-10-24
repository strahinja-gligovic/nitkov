class_name FireScorch
extends Decal
## A scorch mark burnt into a wall or the floor: ragged char whose cracks
## glow like embers and cool first, then the char itself fades away.

const LIFE := 3.2

var _age := 0.0
var _glow := 2.5


## A round scorch `size` metres across at `at`, on the surface facing `normal`.
static func mark(world: Node, at: Vector3, normal: Vector3, size: float) -> void:
	var scorch := FireScorch.new()
	scorch.texture_albedo = FireKit.scorch_albedo()
	scorch.texture_emission = FireKit.scorch_glow()
	scorch.size = Vector3(size, 0.7, size)
	world.add_child(scorch)
	scorch.global_transform = Transform3D(FireKit.basis_from_normal(normal), at)


## The burnt strip a Flame Wall leaves: `where` is the wall's ground centre
## (X along the wall, Y up).
static func strip(world: Node, where: Transform3D, length: float, width: float) -> void:
	var scorch := FireScorch.new()
	scorch.texture_albedo = FireKit.strip_albedo()
	scorch.texture_emission = FireKit.strip_glow()
	scorch.size = Vector3(length + 0.3, 1.0, width + 0.5)
	scorch._glow = 3.0
	world.add_child(scorch)
	scorch.global_transform = Transform3D(where.basis.orthonormalized(), where.origin)


func _init() -> void:
	normal_fade = 0.35
	upper_fade = 0.25
	lower_fade = 0.25
	emission_energy = 0.0


func _process(delta: float) -> void:
	_age += delta
	var cool := maxf(0.0, 1.0 - _age / 1.4)
	emission_energy = _glow * cool * cool
	modulate.a = 1.0 - smoothstep(1.3, LIFE, _age)
	if _age >= LIFE:
		queue_free()
