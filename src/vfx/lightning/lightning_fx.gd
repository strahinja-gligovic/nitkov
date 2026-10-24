class_name LightningFx
extends RefCounted
## How Lightning looks (see SpellFx): jagged, violent electricity, with
## white-hot cores, branching arcs that re-randomize every couple of frames,
## strobing flashes and scorch. The pieces live next to this file:
##   LightningArc, LightningCrackle   jagged camera-facing ribbons
##   LightningFlare                   electric flashes
##   LightningSparks                  spark streaks that bounce
##   LightningPuffs, LightningDebris  dust, smoke and thrown chunks
##   LightningScorch                  burns with glowing Lichtenberg cracks
##   LightningBoltLook                the Lightning Bolt in flight
##   LightningChargeFx                the charge in the casting hand
##   LightningWarningFx, LightningCloud   the strike's telegraph
##   LightningStrikeFx                the bolt from the sky
##   LightningShockFx                 arcs over a stunned body
## Cosmetic only: nothing here reads or writes gameplay state.

const COLOR := Color(1.0, 0.9, 0.3)
const WHITE := Color(1.0, 0.98, 0.85)
## A deeper, hotter yellow for sparks and rims.
const HOT := Color(1.0, 0.76, 0.2)

## Release flashes drawn this tick ([physics frame, position]), so a bolt
## fired on the same tick can start its channel at the hand.
static var _releases: Array = []
## Where the last projectile ended ({frame, at, fizzled}), for its look's
## finish() a moment later in the same tick.
static var _impact := {}


## The Lightning Bolt's body (-Z is the direction of flight).
static func bolt(spell: ProjectileSpell) -> Node3D:
	return LightningBoltLook.make(spell)


static func impact(world: Node, at: Vector3, normal: Vector3, struck: bool, fizzled: bool, spell: ProjectileSpell) -> void:
	_impact = {"frame": Engine.get_physics_frames(), "at": at, "fizzled": fizzled}
	var n := normal.normalized() if normal.length() > 0.01 else Vector3.UP
	if fizzled:
		_fizzle(world, at)
		return
	LightningFlare.spawn(world, at + n * 0.1, 1.8 if struck else 1.4, 0.07)
	light_flash(world, at + n * 0.5, 5.0, 4.5, 0.14)
	var sparks := LightningSparks.spawn(world, HOT, floor_below(world, at))
	if struck:
		var reach := Fighter.RADIUS + (spell.radius if spell else 0.2)
		_body_burst(world, at, n, reach)
		sparks.emit(at, 18, n, 1.3, Vector2(3.0, 7.5), Vector2(0.3, 0.65))
	else:
		_surface_burst(world, at, n)
		sparks.emit(at + n * 0.05, 26, n, 1.25, Vector2(3.0, 9.0), Vector2(0.35, 0.8))
		LightningScorch.spawn(world, at, n, 1.4, 2.8, 1.0, 4.0)
		_smoke(world, at + n * 0.12)


## Where a projectile ended, for its look (see LightningBoltLook.finish).
## Empty unless it ended this very tick.
static func claim_impact() -> Dictionary:
	if _impact.is_empty() or _impact["frame"] != Engine.get_physics_frames():
		return {}
	var found := _impact
	_impact = {}
	return found


## The casting hand of a bolt that appeared at `head` on physics frame
## `frame`, if its release flash was drawn then; otherwise `head`.
static func claim_release(head: Vector3, frame: int) -> Vector3:
	var best := -1
	var best_distance := 2.5
	for i in _releases.size():
		var entry: Array = _releases[i]
		var distance := head.distance_to(entry[1])
		if entry[0] == frame and distance < best_distance:
			best = i
			best_distance = distance
	if best < 0:
		return head
	var at: Vector3 = _releases[best][1]
	_releases.remove_at(best)
	return at


## Lightning gathering in the hand for the wind-up (see LightningChargeFx).
static func charge(hand: Node3D, seconds: float, signature: bool) -> void:
	if is_instance_valid(hand):
		LightningChargeFx.attach(hand, seconds, signature)
	# draw a scorch texture now rather than on the frame the bolt lands
	LightningScorch.prepare()


static func release(world: Node, at: Vector3, direction: Vector3, signature: bool) -> void:
	var frame := Engine.get_physics_frames()
	_releases = _releases.filter(func(entry: Array) -> bool: return entry[0] == frame)
	_releases.append([frame, at])
	var forward := direction.normalized() if direction.length() > 0.01 else Vector3.FORWARD
	LightningFlare.spawn(world, at, 1.15 if signature else 0.75, 0.05)
	light_flash(world, at, 4.0, 3.5, 0.08)
	var sparks := LightningSparks.spawn(world, HOT, floor_below(world, at))
	if signature:
		sparks.emit(at, 24, Vector3.UP, 0.9, Vector2(3.0, 8.0), Vector2(0.25, 0.55), 0.04)
		_sky_bolt(world, at, forward)
		return
	sparks.emit(at, 12, forward, 0.65, Vector2(4.0, 9.0), Vector2(0.15, 0.35), 0.03)
	var muzzle := LightningCrackle.spawn(world, func(arc: LightningArc, _t: float) -> void:
		for i in 4:
			var out := LightningArc.scatter(forward, 0.9)
			arc.add(LightningArc.jagged(at, at + out * randf_range(0.35, 0.8), 3, 0.3), 0.016, 1.0, 0.85, 0.5)
	, 0.1)
	muzzle.hold = 0.4


## Lightning Strike's telegraph under `parent` (the strike, at ground
## level): see LightningWarningFx. The strike frees it when the bolt lands.
static func strike_warning(parent: Node3D, radius: float, delay: float) -> Node3D:
	return LightningWarningFx.build(parent, radius, delay)


## The bolt from the sky landing at `at` (ground centre): see
## LightningStrikeFx. It takes over the warning's storm cloud and leader, so
## the bolt comes down the path the leader was stepping along.
static func strike(world: Node, at: Vector3, radius: float) -> void:
	var cloud: LightningCloud = null
	var leader := PackedVector3Array()
	for node in world.get_tree().get_nodes_in_group(LightningWarningFx.GROUP):
		var warning := node as LightningWarningFx
		if warning == null:
			continue
		if Vector2(warning.global_position.x - at.x, warning.global_position.z - at.z).length() > 0.3:
			continue
		leader = warning.leader
		if is_instance_valid(warning.cloud):
			cloud = warning.cloud
			cloud.reparent(world)
			warning.cloud = null
		warning.remove_from_group(LightningWarningFx.GROUP)
		break
	LightningStrikeFx.spawn(world, at, radius, cloud, leader)


## Arcs crackling over a stunned fighter for `seconds` (see LightningShockFx).
static func shock(body: Node3D, seconds: float) -> void:
	if is_instance_valid(body) and seconds > 0.0:
		LightningShockFx.attach(body, seconds)


# --- shared pieces ------------------------------------------------------------

## The root of `node`'s 3D world (its ancestor right under the viewport: the
## arena, or the menu showcase's own world), where an effect riding a body
## leaves its last sparks. Not current_scene: in the menu that's the menu's
## Control, outside the showcase's world.
static func world_of(node: Node) -> Node:
	var at := node
	while at and at.get_parent() and not (at.get_parent() is Viewport):
		at = at.get_parent()
	return at


## An OmniLight with no shadows.
static func lamp(color: Color, energy: float, reach: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = reach
	light.shadow_enabled = false
	return light


## A light that blinks on at `at` and dies out over `duration`.
static func light_flash(world: Node, at: Vector3, energy: float, reach: float, duration: float, color := COLOR) -> void:
	var light := lamp(color, energy, reach)
	world.add_child(light)
	light.global_position = at
	var tween := light.create_tween()
	tween.tween_property(light, ^"light_energy", 0.0, duration).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(light.queue_free)


## The height of the ground under `at` (where sparks bounce), or a guess
## `drop` metres below it when there's nothing there to find.
static func floor_below(world: Node, at: Vector3, drop := 1.3) -> float:
	var node := world as Node3D
	if node == null or not node.is_inside_tree():
		return at.y - drop
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.1, at + Vector3.DOWN * 8.0, 1)
	var hit := node.get_world_3d().direct_space_state.intersect_ray(query)
	return (hit["position"] as Vector3).y if hit else at.y - drop


## Arcs raking out along a wall or the floor from `at`, re-randomized every
## couple of frames, with their forks.
static func _surface_burst(world: Node, at: Vector3, n: Vector3) -> void:
	var base := at + n * 0.03
	var arms: Array[Vector3] = []
	for i in 6:
		arms.append(LightningArc.along_surface(n))
	var crackle := LightningCrackle.spawn(world, func(arc: LightningArc, t: float) -> void:
		for dir in arms:
			var reach := randf_range(0.55, 1.35) * (1.0 - 0.35 * t)
			var path := LightningArc.jagged(base, base + dir * reach, 4, 0.2, n)
			arc.add(path, 0.024, 1.0, 0.85, 0.55)
			if randf() < 0.6:
				arc.add(LightningArc.fork(path, reach * 0.55, 0.9, 3, 0.25, n), 0.014, 0.8, 0.9, 0.6)
	, 0.34)
	crackle.hold = 0.3
	crackle.flicker = 0.45


## A bolt that struck a fighter: arcs wrap round the body behind the hit and
## spit back out toward the shooter. `reach` is how far the hit point is
## from the body's axis.
static func _body_burst(world: Node, at: Vector3, n: Vector3, reach: float) -> void:
	var front := Vector3(n.x, 0.0, n.z)
	front = front.normalized() if front.length() > 0.01 else Vector3.FORWARD
	var axis := at - front * reach
	var crackle := LightningCrackle.spawn(world, func(arc: LightningArc, _t: float) -> void:
		for i in 3:
			var turn := randf_range(1.2, 2.6) * (1.0 if i % 2 == 0 else -1.0)
			arc.add(_wrap(axis, front, turn, 0.34, randf_range(-0.6, 0.45)), 0.018, 1.0, 0.7, 0.5)
		for i in 3:
			var out := LightningArc.scatter(n, 1.1)
			var from := axis + front * 0.3
			arc.add(LightningArc.jagged(from, from + out * randf_range(0.45, 1.0), 3, 0.28), 0.02, 1.0, 0.9, 0.5)
	, 0.3)
	crackle.flicker = 0.45


## A path that runs round a vertical axis: from `front` (a flat direction)
## through `turn` radians at `radius`, rising `rise` metres on the way.
static func _wrap(axis: Vector3, front: Vector3, turn: float, radius: float, rise: float) -> PackedVector3Array:
	var points := PackedVector3Array()
	var steps := 8
	for k in steps + 1:
		var t := float(k) / steps
		var out := front.rotated(Vector3.UP, turn * t) * (radius + randf_range(-0.03, 0.07))
		points.append(axis + out + Vector3.UP * (rise * t + randf_range(-0.06, 0.06)))
	return points


## Out of range: the bolt sputters out in a few weak crackles, no flash.
static func _fizzle(world: Node, at: Vector3) -> void:
	var crackle := LightningCrackle.spawn(world, func(arc: LightningArc, t: float) -> void:
		for i in 3:
			var out := LightningArc.scatter(Vector3.UP, PI)
			arc.add(LightningArc.jagged(at, at + out * randf_range(0.15, 0.45) * (1.0 - t * 0.5), 3, 0.3), 0.012, 0.7, 0.8, 0.5)
	, 0.18)
	crackle.peak = 0.7
	LightningFlare.spawn(world, at, 0.5, 0.06, COLOR, 0.5)
	var sparks := LightningSparks.spawn(world, HOT, floor_below(world, at))
	sparks.emit(at, 6, Vector3.DOWN, PI, Vector2(0.8, 2.5), Vector2(0.2, 0.4), 0.025)


## A thin curl of dark smoke off a fresh scorch.
static func _smoke(world: Node, at: Vector3) -> void:
	var smoke := LightningPuffs.spawn(world, &"smoke")
	smoke.rise = 1.8
	smoke.drag = 1.5
	smoke.fade_from = 0.0
	for i in 3:
		var drift := Vector3(randf_range(-0.3, 0.3), randf_range(0.4, 0.9), randf_range(-0.3, 0.3))
		smoke.emit(at + drift * 0.25, drift, randf_range(0.22, 0.36), randf_range(0.45, 0.7))


## Lightning Strike's release: a bolt leaping from the raised hand up into
## the sky (leaning a little toward where the caster faces).
static func _sky_bolt(world: Node, at: Vector3, forward: Vector3) -> void:
	var top := at + (Vector3.UP + forward * 0.22).normalized() * 30.0
	var path := LightningArc.jagged(at, top, 6, 0.06)
	var crackle := LightningCrackle.spawn(world, func(arc: LightningArc, _t: float) -> void:
		var live := PackedVector3Array()
		for point in path:
			live.append(point + Vector3(randf_range(-0.05, 0.05), 0.0, randf_range(-0.05, 0.05)))
		arc.add(live, 0.07, 1.0, 0.5, 0.2)
		for i in 3:
			arc.add(LightningArc.fork(live, randf_range(1.0, 3.0), 0.7, 3, 0.2, Vector3.ZERO, Vector2(0.15, 0.7)),
					0.03, 0.85, 0.85, 0.5)
	, 0.24, COLOR, true)
	crackle.envelope = func(age: float) -> float:
		if age < 0.05:
			return 1.0
		if age < 0.08:
			return 0.08
		if age < 0.14:
			return 0.95
		return maxf(0.0, 1.0 - (age - 0.14) / 0.1)
	crackle.flicker = 0.15
