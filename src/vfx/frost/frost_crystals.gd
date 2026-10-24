class_name FrostCrystals
extends MultiMeshInstance3D
## Ice crystals bursting out of a surface: an impact's cluster, the Frost
## Nova's ring of spikes, the Shatter's star. Each one shoots out of its root
## after a delay (overshooting a little and flashing white), holds, then
## crumbles away and sinks, shedding a few falling chunks if `debris` is set.
## One MultiMesh in this node's space (world space for world_burst()); frees
## itself after the last crystal has crumbled.

const HIDDEN_BASIS := Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)

var violet := 0.0
## Falling chunks shed by each crystal as it crumbles (world-space only).
var debris := 0
## Where shed chunks land.
var debris_floor := -1.0e9

var _roots: Array[Transform3D] = []
var _delay := PackedFloat32Array()
var _grow := PackedFloat32Array()
var _crumble_at := PackedFloat32Array()
var _crumble := PackedFloat32Array()
var _seed := PackedFloat32Array()
var _shed := PackedByteArray()
var _time := 0.0
var _debris_bits: FrostBits


static func make(capacity: int, glass := false) -> FrostCrystals:
	var crystals := FrostCrystals.new()
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.use_custom_data = true
	instances.mesh = FrostKit.growth_mesh()
	instances.instance_count = capacity
	instances.visible_instance_count = 0
	crystals.multimesh = instances
	crystals.material_override = FrostKit.growth_material(glass)
	crystals.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return crystals


## Crystals in world space, added to `world` (roots are global).
static func world_burst(world: Node, capacity: int, glass := false) -> FrostCrystals:
	var crystals := make(capacity, glass)
	crystals.top_level = true
	world.add_child(crystals)
	crystals.global_transform = Transform3D.IDENTITY
	return crystals


## A crystal standing at `root`, whose basis carries its full size (x and z
## the radius, y the height along its growth). It erupts after `delay`
## over `grow` seconds and crumbles from `crumble_at` over `crumble` seconds
## (both counted from now).
func add(root: Transform3D, delay: float, grow: float, crumble_at: float, crumble: float) -> void:
	var i := _roots.size()
	if i >= multimesh.instance_count:
		return
	_roots.append(root)
	_delay.append(delay)
	_grow.append(maxf(grow, 0.01))
	_crumble_at.append(maxf(crumble_at, delay + grow))
	_crumble.append(maxf(crumble, 0.01))
	_seed.append(randf())
	_shed.append(0)
	multimesh.visible_instance_count = i + 1
	multimesh.set_instance_transform(i, Transform3D(HIDDEN_BASIS, root.origin))


## A crystal rooted at `at`, growing along `up`, `height` tall and `radius`
## wide, turned randomly around its axis.
static func root_at(at: Vector3, up: Vector3, height: float, radius: float) -> Transform3D:
	var basis := FrostKit.basis_facing(up).rotated(up.normalized(), randf() * TAU)
	return Transform3D(basis * Basis.from_scale(Vector3(radius, height, radius)), at)


func _process(delta: float) -> void:
	_time += delta
	var alive := 0
	var instances := multimesh
	for i in _roots.size():
		var root := _roots[i]
		var t := _time - _delay[i]
		if t < 0.0:
			alive += 1
			continue
		var crumble := (_time - _crumble_at[i]) / _crumble[i]
		if crumble >= 1.0:
			instances.set_instance_transform(i, Transform3D(HIDDEN_BASIS, root.origin))
			continue
		alive += 1
		crumble = maxf(crumble, 0.0)
		var g := clampf(t / _grow[i], 0.0, 1.0)
		var girth := lerpf(0.35, 1.0, minf(g * 1.6, 1.0)) * (1.0 - 0.2 * crumble)
		var height := _ease_out_back(g) * (1.0 - 0.3 * crumble)
		var basis := root.basis * Basis.from_scale(Vector3(girth, height, girth))
		var origin := root.origin - root.basis.y * 0.15 * crumble
		instances.set_instance_transform(i, Transform3D(basis, origin))
		instances.set_instance_custom_data(i, Color(crumble * 1.05, clampf(1.0 - t / 0.1, 0.0, 1.0), violet, _seed[i]))
		if crumble > 0.0 and _shed[i] == 0:
			_shed[i] = 1
			_shed_debris(root)
	if alive == 0:
		queue_free()


func _shed_debris(root: Transform3D) -> void:
	if debris <= 0 or not top_level:
		return
	if _debris_bits == null or not is_instance_valid(_debris_bits):
		_debris_bits = FrostBits.world_burst(get_parent(), FrostBits.Kind.CHUNK, mini(debris * _roots.size(), 160))
		_debris_bits.gravity = 13.0
		_debris_bits.floor_y = debris_floor
		_debris_bits.bounce = 0.25
		_debris_bits.spin = 9.0
	var height := root.basis.y.length()
	var width := root.basis.x.length()
	var up := root.basis.y.normalized()
	for k in debris:
		var at := root.origin + up * height * randf_range(0.15, 0.85)
		var out := (FrostKit.random_direction() * 0.7 + up * 0.5).normalized()
		var size := clampf(width * randf_range(0.35, 0.6), 0.025, 0.12)
		_debris_bits.add(at, out * randf_range(0.6, 2.2), Vector3(size, size * randf_range(1.2, 1.9), size),
				randf_range(0.35, 0.6), 0.0, violet)


## 0 -> 1 with a small overshoot past 1 near the end.
static func _ease_out_back(x: float) -> float:
	var c1 := 1.4
	var c3 := c1 + 1.0
	var u := x - 1.0
	return 1.0 + c3 * u * u * u + c1 * u * u
