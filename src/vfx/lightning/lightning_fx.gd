class_name LightningFx
extends RefCounted
## How Lightning looks: the Lightning Bolt, Lightning Strike's warning mark
## and its bolt from the sky, and lightning's charge-up, release flash and
## impacts. Cosmetic only (see SpellFx).

const COLOR := Color(1.0, 0.9, 0.3)
const WHITE := Color(1.0, 0.98, 0.85)


## The Lightning Bolt's body: a white-hot streak (-Z is the direction of
## flight).
static func bolt(spell: ProjectileSpell) -> Node3D:
	var root := ElementFxKit.orb(COLOR, spell.radius)
	var streak := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = spell.radius * 0.5
	capsule.height = 2.0
	streak.mesh = capsule
	streak.rotation.x = PI * 0.5
	streak.position.z = 1.0  # trailing behind
	streak.material_override = ToonMaterials.make_vfx(WHITE, 4.0)
	streak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(streak)
	return root


static func impact(world: Node, at: Vector3, _normal: Vector3, struck: bool, fizzled: bool, _spell: ProjectileSpell) -> void:
	ElementFxKit.flash(world, at, WHITE, 0.5 if fizzled else (1.2 if struck else 0.9), 0.14)
	if fizzled:
		return
	for i in 3:
		var direction := Vector3(randf_range(-1.0, 1.0), randf_range(-0.3, 1.0), randf_range(-1.0, 1.0)).normalized()
		_arc(world, at, at + direction * randf_range(0.6, 1.1), 0.03, 0.12)


static func charge(hand: Node3D, seconds: float, signature: bool) -> void:
	ElementFxKit.hand_glow(hand, COLOR, seconds, 0.2 if signature else 0.12)


static func release(world: Node, at: Vector3, direction: Vector3, signature: bool) -> void:
	ElementFxKit.flash(world, at, WHITE, 0.8 if signature else 0.45, 0.1)
	if signature:
		_arc(world, at, at + Vector3.UP * 6.0, 0.06, 0.15)
	else:
		_arc(world, at, at + direction * 1.2, 0.04, 0.08)


## The mark where a Lightning Strike will land, under `parent` (the strike,
## at ground level): a ring at the edge and a disc that fills in until the
## bolt lands, `delay` seconds from now. The strike frees it when it lands.
static func strike_warning(parent: Node3D, radius: float, delay: float) -> Node3D:
	var root := Node3D.new()
	parent.add_child(root)
	var edge := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.92
	torus.outer_radius = 1.0
	torus.rings = 48
	edge.mesh = torus
	edge.scale = Vector3(radius, 0.4, radius)
	edge.position.y = 0.06
	edge.material_override = ToonMaterials.make_vfx(COLOR, 2.5)
	edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(edge)
	var fill := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.02
	fill.mesh = disc
	fill.position.y = 0.05
	var fill_material := ToonMaterials.make_vfx(COLOR, 1.5)
	fill_material.albedo_color.a = 0.35
	fill.material_override = fill_material
	fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fill.scale = Vector3(0.05, 1.0, 0.05)
	root.add_child(fill)
	var tween := fill.create_tween()
	tween.tween_property(fill, ^"scale", Vector3(radius, 1.0, radius), maxf(delay, 0.05)) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	return root


## The bolt landing at `at` (on the ground): a jagged bolt from the sky, a
## blinding flash and a shock ring as wide as the strike.
static func strike(world: Node, at: Vector3, radius: float) -> void:
	var sky := at + Vector3(randf_range(-1.5, 1.5), 22.0, randf_range(-1.5, 1.5))
	_arc(world, sky, at, 0.22, 0.25, WHITE)
	_arc(world, sky, at, 0.1, 0.35, COLOR)
	ElementFxKit.flash(world, at + Vector3.UP * 0.5, WHITE, radius * 1.2, 0.25)
	Vfx.ring(world, at, COLOR, radius, 0.35)
	for i in 5:
		var angle := TAU * i / 5.0 + randf() * 0.5
		var out := Vector3(cos(angle), 0.0, sin(angle)) * radius * randf_range(0.7, 1.0)
		_arc(world, at + Vector3.UP * 0.2, at + out + Vector3.UP * 0.1, 0.05, 0.2, COLOR)


## Arcs crackling over a stunned fighter for `seconds` (Lightning Strike's
## stun). `body` is the fighter's visual pivot (origin at the feet); the
## effect rides on it and frees itself.
static func shock(body: Node3D, seconds: float) -> void:
	if not is_instance_valid(body) or seconds <= 0.0:
		return
	var holder := Node3D.new()
	body.add_child(holder)
	var tween := holder.create_tween().set_loops(maxi(1, int(seconds / 0.12)))
	tween.tween_callback(func() -> void:
		var low := holder.global_position + Vector3(randf_range(-0.3, 0.3), randf_range(0.3, 1.0), randf_range(-0.3, 0.3))
		var high := holder.global_position + Vector3(randf_range(-0.4, 0.4), randf_range(1.0, 1.8), randf_range(-0.4, 0.4))
		_arc(holder, low, high, 0.025, 0.1))
	tween.tween_interval(0.12)
	holder.create_tween().tween_callback(holder.queue_free).set_delay(seconds)


## A jagged line of light from `from` to `to` that fades over `duration`.
static func _arc(world: Node, from: Vector3, to: Vector3, width: float, duration: float, color := WHITE) -> void:
	var length := from.distance_to(to)
	var points := _jagged(from, to, maxi(3, int(length / 0.5)), length * 0.06)
	var root := Node3D.new()
	world.add_child(root)
	var material := ToonMaterials.make_vfx(color, 5.0)
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var segment := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(width, width, a.distance_to(b) + width)
		segment.mesh = box
		segment.material_override = material
		segment.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(segment)
		segment.global_position = (a + b) * 0.5
		var along := (b - a).normalized()
		segment.look_at(b, Vector3.UP if absf(along.y) < 0.99 else Vector3.RIGHT)
	var tween := root.create_tween()
	tween.tween_property(material, ^"albedo_color:a", 0.0, duration)
	tween.tween_callback(root.queue_free)


## Points from `from` to `to`, each inner one knocked sideways by up to
## `jitter`.
static func _jagged(from: Vector3, to: Vector3, segments: int, jitter: float) -> PackedVector3Array:
	var points := PackedVector3Array([from])
	var along := to - from
	var side := along.cross(Vector3.UP)
	side = side.normalized() if side.length() > 0.001 else Vector3.RIGHT
	var other := along.cross(side).normalized()
	for i in range(1, segments):
		var t := float(i) / segments
		points.append(from + along * t + side * randf_range(-jitter, jitter) + other * randf_range(-jitter, jitter))
	points.append(to)
	return points
