class_name LightningBoltLook
extends Node3D
## The Lightning Bolt in flight (LightningFx.bolt). At 80 m/s it crosses the
## arena in a few frames, so its path is the visual: a white-hot head with a
## crackling corona and forks just behind it, and the whole travelled path
## as a jagged, inked channel that flickers out LINGER seconds after the
## head passes. When the bolt lands, finish() lights the whole channel once
## more (a return stroke, like real lightning) and lets it die out; a fizzle
## only fades. Its Projectile places it every frame (-Z along the flight).

## Seconds a stretch of channel stays lit after the head has passed it.
const LINGER := 0.2
## Metres between the channel's points.
const SPACING := 0.42
## How far the channel wanders off the flight line.
const WANDER := 0.3
## Seconds between re-randomizations: every 2 frames at 60 fps.
const REFRESH := 1.0 / 30.0
## Half-widths of the channel: fresh at the head, and old.
const HEAD_WIDTH := 0.065
const OLD_WIDTH := 0.03

var spell: ProjectileSpell

var _channel: LightningArc
var _forks: LightningArc
var _flare: LightningFlare
var _light: OmniLight3D
var _spine := PackedVector3Array()
## When (in this look's age) the head passed each spine point.
var _passed := PackedFloat32Array()
var _wander := PackedVector3Array()
var _walk := Vector3.ZERO
var _travel := Vector3.FORWARD
var _age := 0.0
var _next := 0.0
var _done := false
var _done_at := 0.0
var _stroke_at := -1.0
var _created_frame := -1
# reused per redraw
var _points := PackedVector3Array()
var _widths := PackedFloat32Array()
var _brights := PackedFloat32Array()


static func make(data: ProjectileSpell) -> LightningBoltLook:
	var look := LightningBoltLook.new()
	look.name = "LightningBolt"
	look.spell = data
	look._created_frame = Engine.get_physics_frames()
	return look


func _ready() -> void:
	_channel = LightningArc.new()
	_channel.style(true, LightningFx.COLOR)
	add_child(_channel)
	_forks = LightningArc.new()
	_forks.style(false, LightningFx.COLOR)
	add_child(_forks)
	_flare = LightningFlare.attach(self, 1.1)
	_light = LightningFx.lamp(LightningFx.COLOR, 2.6, 4.5)
	add_child(_light)


func _process(delta: float) -> void:
	_age += delta
	if _done:
		if _age - _done_at > LINGER + 0.12:
			queue_free()
			return
	else:
		_follow_head()
	_next -= delta
	if _next <= 0.0:
		_next = REFRESH
		_redraw()
	_shine()


## The projectile is gone: reach the exact spot it ended, light the whole
## channel once more unless it fizzled, and fade (SpellFx.release_look).
func finish() -> void:
	if _done:
		return
	if _spine.is_empty():
		_begin(global_position)
	var ending := LightningFx.claim_impact()
	var end := global_position
	if not ending.is_empty():
		end = ending["at"]
		if not ending["fizzled"]:
			_stroke_at = _age
	_extend_to(end)
	_push(end, _age, true)
	_done = true
	_done_at = _age
	if is_instance_valid(_flare):
		_flare.queue_free()
	_light.global_position = end
	_next = 0.0


func _follow_head() -> void:
	var forward := -global_basis.z
	if forward.length() > 0.01:
		_travel = forward.normalized()
	if _spine.is_empty():
		_begin(global_position)
	_extend_to(global_position)


## The channel starts at the casting hand when the release flash was drawn
## this same tick, else where the bolt appeared.
func _begin(head: Vector3) -> void:
	var start := LightningFx.claim_release(head, _created_frame)
	_walk = Vector3.ZERO
	_push(start, _age, true)


func _extend_to(head: Vector3) -> void:
	var last := _spine[_spine.size() - 1]
	var gap := head - last
	var distance := gap.length()
	var steps := int(distance / SPACING)
	if steps <= 0:
		return
	var dir := gap / distance
	var speed := maxf(spell.speed if spell else 80.0, 1.0)
	for k in steps:
		var along := float(k + 1) * SPACING
		_push(last + dir * along, _age - (distance - along) / speed)


func _push(point: Vector3, passed: float, pinned := false) -> void:
	var side := _travel.cross(Vector3.UP)
	side = side.normalized() if side.length() > 0.01 else Vector3.RIGHT
	var up := side.cross(_travel)
	# a random walk pulled back toward the flight line: wanders, never strays
	_walk = _walk * 0.6 + (side * randf_range(-1.0, 1.0) + up * randf_range(-0.8, 0.8)) * WANDER
	_spine.append(point)
	_passed.append(passed)
	_wander.append(Vector3.ZERO if pinned else _walk)


## How lit a point is, `age` seconds after the head passed it.
static func _level(age: float) -> float:
	if age < 0.03:
		return 1.0
	if age >= LINGER:
		return 0.0
	return pow(1.0 - (age - 0.03) / (LINGER - 0.03), 1.3)


func _redraw() -> void:
	_channel.clear()
	_forks.clear()
	var count := _spine.size()
	if count == 0:
		_channel.commit()
		_forks.commit()
		return
	var head := global_position if not _done else _spine[count - 1]
	var start := _spine[0]
	var stroke := _stroke_at >= 0.0
	var stroke_age := _age - _stroke_at
	_points.clear()
	_widths.clear()
	_brights.clear()
	var chunk_level := 1.0
	for i in count:
		if i % 5 == 0:
			# whole stretches flicker together, some nearly out
			chunk_level = 0.08 if randf() < 0.12 else randf_range(0.55, 1.0)
		var age := _age - _passed[i]
		if stroke:
			age = minf(age, stroke_age)
		var level := _level(age)
		if level <= 0.02:
			_flush()
			continue
		var point := _spine[i]
		# converge on the hand and on the head; wander and crackle between.
		# Near the hand it stays tight: from over the shoulder, perspective
		# blows a wide zigzag up into a scribble right in front of the camera
		var settle := clampf(point.distance_to(head) / 1.2, 0.0, 1.0) 				* clampf(0.15 + point.distance_to(start) / 4.0, 0.0, 1.0) * clampf(point.distance_to(start) / 0.6, 0.0, 1.0)
		var crackle := 0.05 + 0.07 * level
		point += (_wander[i] + Vector3(randf_range(-crackle, crackle), randf_range(-crackle, crackle),
				randf_range(-crackle, crackle))) * settle
		var lit := level * (chunk_level if age > 0.04 else 1.0)
		var width := lerpf(OLD_WIDTH, HEAD_WIDTH, level)
		if stroke and stroke_age < 0.05:
			width *= 1.4
			lit = 1.0
		_emit(point, width, lit, settle)
	if not _done:
		_emit(head, HEAD_WIDTH * 1.1, 1.0, 0.0)
	_flush()
	if not _done:
		_draw_head_forks(head)
	elif stroke and stroke_age < LINGER * 0.6:
		_draw_stroke_forks(1.0 - stroke_age / (LINGER * 0.6))
	_channel.commit()
	_forks.commit()


## Adds a channel point, with a kinked midpoint before it for a finer
## zigzag (`kink` scales the kink: none where the channel settles).
func _emit(point: Vector3, width: float, lit: float, kink: float) -> void:
	var count := _points.size()
	if count > 0:
		var previous := _points[count - 1]
		var gap := previous.distance_to(point) * 0.3 * kink
		_points.append((previous + point) * 0.5 + Vector3(randf_range(-gap, gap), randf_range(-gap, gap),
				randf_range(-gap, gap)))
		_widths.append((_widths[count - 1] + width) * 0.5)
		_brights.append((_brights[count - 1] + lit) * 0.5)
	_points.append(point)
	_widths.append(width)
	_brights.append(lit)


func _flush() -> void:
	if _points.size() >= 2:
		_channel.add_shaped(_points, _widths, _brights)
	_points.clear()
	_widths.clear()
	_brights.clear()


## Forks spraying off just behind the head, and a crackling corona round it.
func _draw_head_forks(head: Vector3) -> void:
	var count := _spine.size()
	var recent := PackedVector3Array()
	for i in range(maxi(0, count - 7), count):
		recent.append(_spine[i])
	recent.append(head)
	if recent.size() >= 3:
		for i in 2:
			var reach := randf_range(0.5, 1.3)
			_forks.add(LightningArc.fork(recent, reach, 0.8, 3, 0.28, Vector3.ZERO, Vector2(0.2, 0.9)),
					0.016, 0.85, 0.85, 0.6)
	for i in 3:
		var out := LightningArc.scatter(-_travel, 1.9)
		_forks.add(LightningArc.jagged(head, head + out * randf_range(0.18, 0.45), 2, 0.3), 0.012, 1.0, 0.8, 0.4)


## The return stroke lights side branches along the channel too.
func _draw_stroke_forks(strength: float) -> void:
	var count := _spine.size()
	if count < 4:
		return
	for i in 4:
		var reach := randf_range(0.6, 1.6)
		_forks.add(LightningArc.fork(_spine, reach, 0.9, 3, 0.3, Vector3.ZERO, Vector2(0.1, 0.95)),
				0.016, 0.9 * strength, 0.9, 0.7)


## The head's flare and the light that rides with the bolt.
func _shine() -> void:
	if not _done:
		if is_instance_valid(_flare):
			_flare.show_state(0.12, randf_range(0.85, 1.2), _next == REFRESH)
		_light.light_energy = randf_range(2.2, 3.2)
		return
	var since := _age - _done_at
	if _stroke_at >= 0.0:
		_light.light_energy = 5.0 if since < 0.05 else 4.0 * maxf(0.0, 1.0 - since / LINGER) * randf_range(0.5, 1.0)
	else:
		_light.light_energy = 2.0 * maxf(0.0, 1.0 - since / 0.1)
