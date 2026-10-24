class_name FrostFx
extends RefCounted
## How Frost looks: the Ice Spike, Frost Nova, the Shatter combo, and frost's
## charge-up, release and impacts. Crystalline: faceted cel-shaded ice,
## glitter, cold mist and shattering. Cosmetic only (see SpellFx): nothing
## here writes gameplay state, and every effect frees itself.

const COLOR := FrostKit.COLOR
const PALE := FrostKit.PALE
## The Nova's wave reaches the full radius this many seconds after the slam.
const NOVA_WAVE := 0.2
## When the Nova's crystals start crumbling.
const NOVA_CRUMBLE := 0.6


## The Ice Spike's body (see FrostSpikeLook).
static func ice_spike(_spell: ProjectileSpell) -> Node3D:
	return FrostSpikeLook.new()


## Ice crystals forming around the fist and cold mist spiralling in.
static func charge(hand: Node3D, seconds: float, signature: bool) -> void:
	if not is_instance_valid(hand) or not hand.is_inside_tree():
		return
	FrostCharge.attach(hand, seconds, signature)


## The spell leaving the fist: an icy burst toward `direction` (the Ice
## Spike), or the fist slamming into the ground (Frost Nova).
static func release(world: Node, at: Vector3, direction: Vector3, signature: bool) -> void:
	if not _usable(world):
		return
	var forward := direction.normalized() if direction.length() > 0.01 else Vector3.FORWARD
	if signature:
		_release_slam(world, at)
		return
	var muzzle := at + forward * 0.12
	FrostKit.flash(world, muzzle, 0.7, 0.07)
	FrostKit.light(world, muzzle, PALE, 2.0, 3.5, 0.1)
	# needles of ice snapping out around the fist like a snowflake, then gone
	var petals := FrostCrystals.world_burst(world, 6, true)
	var across := FrostKit.basis_facing(forward)
	for k in 6:
		var angle := TAU * k / 6.0 + randf_range(-0.15, 0.15)
		var out := ((across.x * cos(angle) + across.z * sin(angle)) * 0.85 + forward * 0.55).normalized()
		petals.add(FrostCrystals.root_at(muzzle + out * 0.04, out, randf_range(0.15, 0.24), randf_range(0.02, 0.03)),
				0.0, 0.035, 0.06, 0.1)
	var shards := FrostBits.world_burst(world, FrostBits.Kind.CHUNK, 10)
	shards.gravity = 9.0
	shards.drag = 1.5
	shards.spin = 14.0
	for k in 10:
		var out := FrostKit.random_cone(forward, 35.0 if k < 6 else 80.0)
		var size := randf_range(0.022, 0.045)
		shards.add(muzzle, out * randf_range(3.5, 8.0), Vector3(size, size * randf_range(1.5, 2.4), size), randf_range(0.2, 0.34))
	_mist(world, muzzle, forward, 5, Vector2(0.14, 0.24), Vector2(0.28, 0.42), 1.6)
	_glitter(world, muzzle, 8, 2.5, 0.45)


## Frost Nova: the fist hits the ground, a wave of ice spikes bursts out of
## it to the exact radius with a shock ring and rolling cold mist, the
## spikes crumble, and frost stays on the ground for a few seconds.
static func nova(world: Node, at: Vector3, radius: float) -> void:
	if not _usable(world):
		return
	FrostKit.flash(world, at + Vector3.UP * 0.9, 1.9, 0.1)
	FrostKit.light(world, at + Vector3.UP * 1.2, PALE, 3.2, radius * 2.0, 0.22)
	FrostKit.ring(world, at + Vector3.UP * 0.06, Vector3.UP, radius, NOVA_WAVE, 0.45, 0.5, 40.0, 0.0, 0.08)
	FrostKit.patch(world, at, Vector3.UP, radius, NOVA_WAVE, 3.0, 1.0)
	_nova_spikes(world, at, radius)
	_nova_mist(world, at, radius)
	var sparkles := FrostBits.world_burst(world, FrostBits.Kind.SPARKLE, 30)
	sparkles.drag = 1.5
	sparkles.gravity = -0.8
	for k in 30:
		var out := FrostKit.random_cone(Vector3.UP, 70.0)
		sparkles.add(at + Vector3.UP * 0.3 + out * 0.3, out * randf_range(1.5, 5.0), Vector3.ONE * randf_range(0.09, 0.17),
				randf_range(0.5, 0.95), randf() * 0.15)


## Where an Ice Spike ended: it shatters into faceted shards with a frost
## puff, leaving a crystal cluster and frost on walls and floors, or a frost
## burst clinging to the fighter it struck. Out of range, it just breaks
## apart into mist.
static func impact(world: Node, at: Vector3, normal: Vector3, struck: bool, fizzled: bool, _spell: ProjectileSpell) -> void:
	if not _usable(world):
		return
	var facing := normal.normalized() if normal.length() > 0.01 else Vector3.UP
	if fizzled:
		_fizzle(world, at, -facing)
		return
	FrostKit.flash(world, at + facing * 0.12, 1.2 if struck else 1.05, 0.08)
	FrostKit.light(world, at + facing * 0.35, PALE, 1.8, 3.0, 0.14)
	var floor_y := at.y if facing.y > 0.7 else FrostKit.floor_below(world, at, at.y - 1.3)
	var shards := FrostBits.world_burst(world, FrostBits.Kind.CHUNK, 16)
	shards.gravity = 14.0
	shards.drag = 0.6
	shards.floor_y = floor_y
	shards.spin = 12.0
	for k in 16:
		var out := FrostKit.random_cone(facing, 75.0)
		var size := randf_range(0.045, 0.1) if k < 6 else randf_range(0.02, 0.045)
		shards.add(at + facing * 0.05, out * randf_range(2.5, 7.0) + Vector3.UP * 1.0,
				Vector3(size, size * randf_range(1.4, 2.6), size), randf_range(0.45, 0.85))
	if struck:
		_mist(world, at + facing * 0.25, facing, 4, Vector2(0.16, 0.24), Vector2(0.3, 0.45), 1.8)
	else:
		_mist(world, at + facing * 0.15, facing, 7, Vector2(0.2, 0.34), Vector2(0.45, 0.7), 1.2)
	_glitter(world, at + facing * 0.1, 12, 3.0, 0.7)
	if struck:
		# a bright crack and a star of ice bursting off the body, so a spike
		# hit lands as hard as the other primaries
		FrostKit.flash(world, at + facing * 0.2, 1.7, 0.07)
		FrostKit.light(world, at + facing * 0.4, PALE, 3.6, 4.0, 0.12)
		var star := FrostCrystals.world_burst(world, 7)
		for k in 7:
			var out := (FrostKit.random_cone(facing, 85.0) * 0.6
					+ Vector3(randf_range(-1.0, 1.0), randf_range(0.2, 1.0), randf_range(-1.0, 1.0)).normalized()).normalized()
			star.add(FrostCrystals.root_at(at + out * 0.25, out, randf_range(0.6, 0.9), randf_range(0.08, 0.12)), 0.0, 0.04, 0.14, 0.2)
		_pierce(world, at, -facing, floor_y)
		var target := _struck_fighter(world, at)
		var anchor := at
		if target:
			# onto the body: the hit point is on the swept capsule, a hand's width out
			var axis := Vector3(target.global_position.x, at.y, target.global_position.z)
			var out := at - axis
			anchor = axis + (out.normalized() * 0.22 if out.length() > 0.01 else Vector3.ZERO)
		var visual := target.get_node_or_null(^"Visual") as Node3D if target else null
		FrostCling.attach(world, visual if visual else target, anchor, facing)
		return
	FrostKit.ring(world, at + facing * 0.03, facing, 0.95, 0.13, 0.22, 0.16, 12.0)
	_cluster(world, at, facing)
	FrostKit.patch(world, at, facing, 0.95, 0.12, 3.0)


## Fire hitting a Chilled target: the ice on it explodes. A cold white-violet
## flash, a star of crystals bursting out of the victim, big chunky shards
## tumbling away, crossed shock rings, glitter, mist and frost underfoot.
static func shatter(world: Node, at: Vector3) -> void:
	if not _usable(world):
		return
	var violet := FrostKit.WHITE_VIOLET
	FrostKit.flash(world, at, 3.4, 0.13, violet, 3.6)
	FrostKit.light(world, at, violet, 4.5, 8.0, 0.2)
	var floor_y := FrostKit.floor_below(world, at, at.y - 1.2)
	var star := FrostCrystals.world_burst(world, 14)
	star.violet = 0.55
	for k in 14:
		var y := 1.0 - 2.0 * (k + 0.5) / 14.0
		var ring := sqrt(maxf(1.0 - y * y, 0.0))
		var out := Vector3(cos(k * 2.39996) * ring, y, sin(k * 2.39996) * ring)
		star.add(FrostCrystals.root_at(at + out * 0.08, out, randf_range(0.85, 1.4), randf_range(0.1, 0.15)),
				0.0, 0.04, 0.07, 0.16)
	var chunks := FrostBits.world_burst(world, FrostBits.Kind.CHUNK, 18)
	chunks.gravity = 16.0
	chunks.drag = 0.4
	chunks.floor_y = floor_y
	chunks.bounce = 0.35
	chunks.spin = 15.0
	for k in 18:
		var out := (FrostKit.random_direction() + Vector3.UP * 0.4).normalized()
		var size := randf_range(0.13, 0.25)
		chunks.add(at + out * 0.15, out * randf_range(4.5, 9.5), Vector3(size, size * randf_range(1.2, 2.0), size),
				randf_range(0.85, 1.25), 0.0, 0.6 if k % 3 == 0 else 0.15)
	var bits := FrostBits.world_burst(world, FrostBits.Kind.CHUNK, 26)
	bits.gravity = 14.0
	bits.drag = 0.8
	bits.floor_y = floor_y
	bits.spin = 20.0
	for k in 26:
		var out := FrostKit.random_direction()
		var size := randf_range(0.03, 0.06)
		bits.add(at + out * 0.1, out * randf_range(7.0, 14.0), Vector3(size, size * 2.0, size), randf_range(0.4, 0.7), 0.0, 0.4)
	FrostKit.ring(world, at, Vector3.UP, 2.1, 0.16, 0.18, 0.22, 10.0, 0.7, 0.1)
	FrostKit.ring(world, Vector3(at.x, floor_y + 0.05, at.z), Vector3.UP, 2.4, 0.24, 0.35, 0.3, 18.0, 0.5, 0.1)
	FrostKit.patch(world, Vector3(at.x, floor_y, at.z), Vector3.UP, 1.9, 0.18, 3.0, 0.0, 0.5)
	_glitter(world, at, 40, 6.0, 1.1, 0.6)
	var mist := FrostBits.world_burst(world, FrostBits.Kind.PUFF, 10)
	mist.drag = 3.0
	mist.swell = 2.4
	mist.gravity = -0.5
	for k in 10:
		var out := FrostKit.random_direction()
		mist.add(at + out * 0.2, out * randf_range(2.0, 4.5), Vector3.ONE * randf_range(0.4, 0.62), randf_range(0.75, 1.0),
				randf() * 0.05, 0.7)


# --- pieces ------------------------------------------------------------------

## The spike driving into a fighter: ice sprays out of the far side along
## its flight, and a shock ring snaps out around the hit, so the weight of
## the blow reads from the caster's camera, which mostly sees the hit side-on
## or from behind.
static func _pierce(world: Node, at: Vector3, travel: Vector3, floor_y: float) -> void:
	FrostKit.ring(world, at, -travel, 0.6, 0.06, 0.08, 0.1, 10.0, 0.0, 0.25)
	var spray := FrostBits.world_burst(world, FrostBits.Kind.CHUNK, 12)
	spray.gravity = 12.0
	spray.drag = 0.8
	spray.floor_y = floor_y
	spray.spin = 16.0
	for k in 12:
		var out := FrostKit.random_cone(travel, 28.0 if k < 7 else 55.0)
		var size := randf_range(0.05, 0.1) if k < 4 else randf_range(0.025, 0.05)
		spray.add(at + travel * 0.25, out * randf_range(6.0, 11.0), Vector3(size, size * randf_range(1.8, 2.8), size),
				randf_range(0.35, 0.6))
	_glitter(world, at + travel * 0.4, 10, 5.0, 0.5)

## The fist slamming the ground for Frost Nova: ice kicked up around it.
static func _release_slam(world: Node, at: Vector3) -> void:
	var floor_y := FrostKit.floor_below(world, at + Vector3.UP * 0.3, at.y - 0.3)
	var ground := Vector3(at.x, maxf(floor_y, at.y - 0.6), at.z)
	FrostKit.flash(world, ground + Vector3.UP * 0.25, 1.2, 0.09)
	var shards := FrostBits.world_burst(world, FrostBits.Kind.CHUNK, 14)
	shards.gravity = 15.0
	shards.floor_y = floor_y
	shards.spin = 12.0
	for k in 14:
		var out := FrostKit.random_cone(Vector3.UP, 55.0)
		var size := randf_range(0.035, 0.08)
		shards.add(ground + Vector3.UP * 0.1, out * randf_range(3.5, 8.0), Vector3(size, size * randf_range(1.5, 2.4), size),
				randf_range(0.4, 0.65))
	_mist(world, ground + Vector3.UP * 0.2, Vector3.UP, 6, Vector2(0.22, 0.36), Vector2(0.4, 0.6), 1.5)


## The Nova's ice spikes: rows that erupt as the wave passes them, the outer
## row standing on the edge of the blast, leaning out.
static func _nova_spikes(world: Node, at: Vector3, radius: float) -> void:
	var camera: Camera3D = world.get_viewport().get_camera_3d() if world.get_viewport() else null
	# [fraction of the radius, count, height range, width range]
	var rows := [
		[0.97, 30, Vector2(0.85, 1.35), Vector2(0.13, 0.19)],
		[0.66, 18, Vector2(0.55, 0.9), Vector2(0.1, 0.15)],
		[0.36, 10, Vector2(0.35, 0.55), Vector2(0.08, 0.11)],
	]
	var crystals := FrostCrystals.world_burst(world, 58)
	crystals.debris = 1
	crystals.debris_floor = at.y
	for row: Array in rows:
		var count: int = row[1]
		var heights: Vector2 = row[2]
		var widths: Vector2 = row[3]
		for k in count:
			var angle := TAU * (k + randf_range(-0.3, 0.3)) / count
			var out := Vector3(cos(angle), 0.0, sin(angle))
			var distance: float = radius * row[0] * randf_range(0.96, 1.0)
			var base := at + out * distance
			var tilt := deg_to_rad(randf_range(16.0, 36.0))
			var up := (Vector3.UP * cos(tilt) + out * sin(tilt)).normalized()
			var height := randf_range(heights.x, heights.y)
			# never plant a spike in the camera's face
			if camera and camera.global_position.distance_to(base + up * height * 0.6) < 2.2:
				height *= 0.35
			var delay := NOVA_WAVE * (1.0 - pow(1.0 - distance / radius, 1.0 / 3.0))
			crystals.add(FrostCrystals.root_at(base - up * 0.05, up, height, randf_range(widths.x, widths.y)),
					delay, 0.06, NOVA_CRUMBLE + randf() * 0.12, 0.26)


## Low cold mist rolling out with the Nova's wave.
static func _nova_mist(world: Node, at: Vector3, radius: float) -> void:
	var mist := FrostBits.world_burst(world, FrostBits.Kind.PUFF, 28)
	mist.drag = 3.2
	mist.swell = 1.8
	mist.gravity = -0.5
	for k in 28:
		var angle := TAU * (k + randf_range(-0.4, 0.4)) / 28.0
		var out := Vector3(cos(angle), 0.0, sin(angle))
		mist.add(at + out * radius * 0.2 + Vector3.UP * randf_range(0.2, 0.4), out * randf_range(9.0, 14.0),
				Vector3.ONE * randf_range(0.55, 0.85), randf_range(0.6, 0.9))


## Crystals growing out of a wall or floor where a spike hit, holding for a
## couple of seconds before they crumble.
static func _cluster(world: Node, at: Vector3, facing: Vector3) -> void:
	var crystals := FrostCrystals.world_burst(world, 7)
	crystals.debris = 2
	crystals.debris_floor = at.y if facing.y > 0.7 else FrostKit.floor_below(world, at, at.y - 1.3)
	var across := FrostKit.basis_facing(facing)
	for k in 7:
		var spot := (across.x * randf_range(-1.0, 1.0) + across.z * randf_range(-1.0, 1.0)) * (0.04 if k == 0 else 0.3)
		var up := FrostKit.random_cone(facing, 10.0 if k == 0 else 40.0)
		var height := randf_range(0.55, 0.7) if k == 0 else randf_range(0.22, 0.42)
		crystals.add(FrostCrystals.root_at(at + spot - facing * 0.03, up, height, randf_range(0.06, 0.1) if k == 0 else randf_range(0.045, 0.08)),
				k * 0.012, 0.07, 2.3 + randf() * 0.3, 0.45)


## The spike giving out at the end of its range: a few pieces drift on and
## melt away in a cloud of cold mist.
static func _fizzle(world: Node, at: Vector3, travel: Vector3) -> void:
	var pieces := FrostBits.world_burst(world, FrostBits.Kind.CHUNK, 6)
	pieces.drag = 2.5
	pieces.gravity = 2.0
	pieces.spin = 4.0
	for k in 6:
		var size := randf_range(0.04, 0.08)
		pieces.add(at + FrostKit.random_direction() * 0.12, travel * randf_range(4.0, 9.0) + FrostKit.random_direction(),
				Vector3(size, size * 2.2, size), randf_range(0.3, 0.5))
	_mist(world, at, travel, 8, Vector2(0.22, 0.36), Vector2(0.5, 0.75), 2.0)
	_glitter(world, at, 10, 1.5, 0.6)


## A puff of cold mist blown toward `toward`.
static func _mist(world: Node, at: Vector3, toward: Vector3, count: int, size: Vector2, life: Vector2, speed: float) -> void:
	var mist := FrostBits.world_burst(world, FrostBits.Kind.PUFF, count)
	mist.drag = 3.5
	mist.swell = 2.1
	mist.gravity = -0.4
	for k in count:
		var out := (toward * 0.8 + FrostKit.random_direction()).normalized()
		mist.add(at + FrostKit.random_direction() * 0.08, out * speed * randf_range(0.5, 1.5),
				Vector3.ONE * randf_range(size.x, size.y), randf_range(life.x, life.y), randf() * 0.04)


## Glitter bursting out of `at`.
static func _glitter(world: Node, at: Vector3, count: int, speed: float, life: float, violet := 0.0) -> void:
	var sparkles := FrostBits.world_burst(world, FrostBits.Kind.SPARKLE, count)
	sparkles.drag = 3.0
	sparkles.gravity = 1.2
	for k in count:
		var out := FrostKit.random_direction()
		sparkles.add(at + out * 0.1, out * speed * randf_range(0.3, 1.0), Vector3.ONE * randf_range(0.08, 0.16),
				life * randf_range(0.5, 1.0), randf() * 0.05, violet)


## The fighter an Ice Spike just struck at `at` (the nearest one), if any.
static func _struck_fighter(world: Node, at: Vector3) -> Node3D:
	var best: Node3D = null
	var best_distance := 1.3
	for node in world.get_tree().get_nodes_in_group(&"fighters"):
		var body := node as Node3D
		if body == null:
			continue
		var distance := Vector2(body.global_position.x - at.x, body.global_position.z - at.z).length()
		if distance < best_distance:
			best_distance = distance
			best = body
	return best


static func _usable(world: Node) -> bool:
	return is_instance_valid(world) and world.is_inside_tree()
