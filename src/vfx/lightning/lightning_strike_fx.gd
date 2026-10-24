class_name LightningStrikeFx
extends Node3D
## Lightning Strike landing (LightningFx.strike), the most dramatic moment of
## all the spells: a thick, branching, inked bolt from the storm cloud to the
## ground that strobes on-off-on (with side bolts hitting inside the circle),
## a white flash filling the circle, a shockwave running out to the rim with
## a ring of electricity on its front, dust and chunks of floor thrown up,
## sparks, arcs crawling over the ground, and a scorch whose Lichtenberg
## cracks glow and cool over a few seconds. The cloud flashes and tears
## apart. Placed at the ground centre; frees itself.

const CLOUD_HEIGHT := LightningWarningFx.CLOUD_HEIGHT
const WAVE_TIME := 0.24
const LIFE := 0.9
const FLASH_ENERGY := 4.0

var radius := 2.5

var _wave: MeshInstance3D
var _flash_light: OmniLight3D
var _glow_light: OmniLight3D
var _age := 0.0


## `cloud` and `leader` come from the warning, if it was still there.
static func spawn(world: Node, at: Vector3, strike_radius: float, cloud: LightningCloud,
		leader: PackedVector3Array) -> LightningStrikeFx:
	var fx := LightningStrikeFx.new()
	fx.name = "LightningStrike"
	fx.radius = strike_radius
	world.add_child(fx)
	fx.global_position = at
	fx._begin(world, at, cloud, leader)
	return fx


static var _wave_material: ShaderMaterial


func _begin(world: Node, at: Vector3, cloud: LightningCloud, leader: PackedVector3Array) -> void:
	if cloud and is_instance_valid(cloud):
		cloud.burst()
	var top := at + Vector3.UP * (CLOUD_HEIGHT - 0.6)
	var channel := leader if leader.size() >= 2 else LightningArc.jagged(top, at, 6, 0.07)
	_bolt(world, at, channel)
	# the flash: a burst of light at the foot of the bolt, and the circle lit white
	# (kept short and a little lifted: the struck fighter must stay visible)
	LightningFlare.spawn(world, at + Vector3.UP * 1.2, radius * 1.4, 0.06, LightningFx.COLOR, 1.0)
	LightningFlare.spawn(world, at + Vector3.UP * 3.5, radius * 0.8, 0.035, LightningFx.WHITE, 0.55)
	_splash(world, at)
	_flash_light = LightningFx.lamp(LightningFx.WHITE, FLASH_ENERGY, radius * 4.0)
	_flash_light.omni_attenuation = 2.0
	_flash_light.position = Vector3.UP * 2.5
	add_child(_flash_light)
	_glow_light = LightningFx.lamp(LightningFx.HOT, 0.0, radius * 2.2)
	_glow_light.position = Vector3.UP * 0.6
	add_child(_glow_light)
	if _wave_material == null:
		_wave_material = ShaderMaterial.new()
		_wave_material.shader = preload("res://src/vfx/lightning/lightning_wave.gdshader")
	_wave = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	var extent := radius + 0.6
	plane.size = Vector2.ONE * extent * 2.0
	_wave.mesh = plane
	_wave.material_override = _wave_material
	_wave.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wave.position.y = 0.05
	_wave.set_instance_shader_parameter(&"extent", extent)
	_wave.set_instance_shader_parameter(&"limit", radius)
	add_child(_wave)
	_ring(world, at)
	_ground_arcs(world, at)
	var floor_y := at.y
	var sparks := LightningSparks.spawn(world, LightningFx.HOT, floor_y)
	sparks.emit(at + Vector3.UP * 0.2, 46, Vector3.UP, 1.25, Vector2(4.0, 11.0), Vector2(0.45, 1.0), 0.04)
	var debris := LightningDebris.spawn(world, floor_y)
	# (small: a chunk flying past the struck fighter's camera must not blot it out)
	debris.throw(at, 12, radius * 0.5, Vector2(4.0, 8.0), Vector2(0.08, 0.18))
	var dust := LightningPuffs.spawn(world, &"dust")
	dust.drag = 4.0
	dust.fade_from = 0.0
	dust.squash = 0.5
	dust.rise = 0.6
	# a low ring of small, flat puffs racing out with the shockwave (small,
	# so none fills the screen when the struck fighter is the viewer)...
	for i in 16:
		var out := LightningArc.along_surface(Vector3.UP)
		dust.emit(at + out * randf_range(0.4, 0.9) + Vector3.UP * 0.12, out * randf_range(7.0, 12.0) + Vector3.UP * randf_range(0.2, 0.9),
				randf_range(0.2, 0.34), randf_range(0.3, 0.5), randf_range(0.2, 0.6))
	# ...and dark smoke climbing off the scorch, from a ring round the centre
	# so it never covers whoever was struck
	var smoke := LightningPuffs.spawn(world, &"smoke")
	smoke.rise = 2.0
	smoke.drag = 2.0
	smoke.fade_from = 0.1
	smoke.squash = 0.8
	for i in 7:
		var out := LightningArc.along_surface(Vector3.UP)
		var drift := out * randf_range(0.6, 1.4) + Vector3.UP * randf_range(1.2, 2.6)
		smoke.emit(at + out * radius * randf_range(0.35, 0.6) + Vector3.UP * 0.25, drift,
				randf_range(0.4, 0.65), randf_range(0.65, 0.95))
	LightningScorch.spawn(world, at + Vector3.UP * 0.02, Vector3.UP, radius * 2.0, 3.8, 1.6, 5.0)
	_update()


## The bolt itself: the main channel strobes on-off-on, re-lit along the
## same path with new branches each stroke, plus side bolts that hit the
## ground inside the circle.
func _bolt(world: Node, at: Vector3, channel: PackedVector3Array) -> void:
	var r := radius
	var side_hits: Array[PackedVector3Array] = []
	for i in 2:
		var from_t := randf_range(0.35, 0.6)
		var start := channel[int(from_t * (channel.size() - 1))]
		var spot := at + LightningArc.along_surface(Vector3.UP) * r * randf_range(0.55, 0.9)
		side_hits.append(LightningArc.jagged(start, spot, 5, 0.12))
	var bolt := LightningCrackle.spawn(world, func(arc: LightningArc, _t: float) -> void:
		var live := PackedVector3Array()
		for point in channel:
			live.append(point + Vector3(randf_range(-0.06, 0.06), 0.0, randf_range(-0.06, 0.06)))
		# thick all the way down: the foot is what players look at
		arc.add(live, 0.2, 1.0, 0.15, 0.0)
		for hit in side_hits:
			arc.add(hit, 0.06, 0.85, 0.5, 0.1)
		for i in 6:
			arc.add(LightningArc.fork(live, randf_range(1.2, 3.2), 0.8, 4, 0.22, Vector3.ZERO, Vector2(0.05, 0.8)),
					0.045, 0.8, 0.85, 0.5)
	, LIFE * 0.45, LightningFx.COLOR, true)
	bolt.refresh = 0.05
	bolt.flicker = 0.1
	bolt.envelope = func(age: float) -> float:
		if age < 0.05:
			return 1.25
		if age < 0.085:
			return 0.0
		if age < 0.16:
			return 1.1
		if age < 0.2:
			return 0.35
		if age < 0.24:
			return 0.7
		return maxf(0.0, 0.5 * (1.0 - (age - 0.24) / 0.14))


## A crown of arcs splashing up and out from the foot of the bolt, taller
## than a fighter: the part of the impact that still shows over low walls
## and from far away, when the ground itself is hidden.
func _splash(world: Node, at: Vector3) -> void:
	var r := radius
	var crown := LightningCrackle.spawn(world, func(arc: LightningArc, t: float) -> void:
		var count := int(lerpf(9.0, 4.0, t))
		for i in count:
			var out := LightningArc.along_surface(Vector3.UP)
			var foot := at + out * r * randf_range(0.05, 0.35) + Vector3.UP * 0.05
			var tip := foot + out * r * randf_range(0.35, 0.8) \
					+ Vector3.UP * randf_range(1.2, 2.8) * (1.0 - 0.4 * t)
			var path := LightningArc.jagged(foot, tip, 4, 0.18)
			arc.add(path, 0.05, 1.0, 0.8, 0.4)
			if randf() < 0.5:
				arc.add(LightningArc.fork(path, randf_range(0.4, 0.9), 0.9, 3, 0.25, Vector3.ZERO, Vector2(0.3, 0.8)),
						0.022, 0.8, 0.85, 0.6)
	, 0.34, LightningFx.COLOR, true)
	crown.refresh = 1.0 / 30.0
	crown.hold = 0.25
	crown.flicker = 0.3
	crown.envelope = func(age: float) -> float:
		if age >= 0.05 and age < 0.085:
			return 0.1
		return 1.0 if age < 0.12 else maxf(0.0, 1.0 - (age - 0.12) / 0.22)


## A ring of electricity riding the shockwave's front out to the rim.
func _ring(world: Node, at: Vector3) -> void:
	var r := radius
	var ring := LightningCrackle.spawn(world, func(arc: LightningArc, _t: float) -> void:
		var reach := r * _wave_reach(_age)
		if reach < 0.2:
			return
		var path := PackedVector3Array()
		var steps := 40
		var turn := randf() * TAU
		for k in steps + 1:
			var angle := turn + TAU * k / steps
			path.append(at + Vector3(cos(angle), 0.0, sin(angle)) * (reach + randf_range(-0.12, 0.12))
					+ Vector3.UP * randf_range(0.05, 0.35))
		arc.add(path, 0.035, 1.0)
	, WAVE_TIME + 0.12)
	ring.hold = 0.6
	ring.flicker = 0.25


## Arcs crawling over the ground inside the circle for a while after.
func _ground_arcs(world: Node, at: Vector3) -> void:
	var r := radius
	var crawl := LightningCrackle.spawn(world, func(arc: LightningArc, t: float) -> void:
		for i in int(lerpf(7.0, 2.0, t)):
			var out := LightningArc.along_surface(Vector3.UP)
			var from := at + out * r * randf_range(0.0, 0.5) + Vector3.UP * 0.04
			var to := at + out.rotated(Vector3.UP, randf_range(-0.6, 0.6)) * r * randf_range(0.6, 1.0) + Vector3.UP * 0.04
			var path := LightningArc.jagged(from, to, 4, 0.2, Vector3.UP)
			arc.add(path, 0.022, randf_range(0.6, 1.0), 0.7, 0.5)
			if randf() < 0.5:
				arc.add(LightningArc.fork(path, r * 0.3, 0.9, 3, 0.25, Vector3.UP), 0.012, 0.7, 0.8, 0.6)
	, LIFE)
	crawl.hold = 0.15
	crawl.flicker = 0.6
	crawl.refresh = 1.0 / 20.0


static func _wave_reach(age: float) -> float:
	var t := clampf(age / WAVE_TIME, 0.0, 1.0)
	return 1.0 - pow(1.0 - t, 3.0)


func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFE:
		queue_free()
		return
	_update()


func _update() -> void:
	var strobe := 1.0
	if _age >= 0.05 and _age < 0.085:
		strobe = 0.15
	elif _age >= 0.16:
		strobe = maxf(0.0, 1.0 - (_age - 0.16) / 0.25) * randf_range(0.4, 1.0)
	_flash_light.light_energy = FLASH_ENERGY * strobe
	_glow_light.light_energy = 3.0 * maxf(0.0, 1.0 - _age / LIFE) * randf_range(0.3, 1.0) if _age > 0.1 else 0.0
	_wave.set_instance_shader_parameter(&"reach", radius * _wave_reach(_age))
	_wave.set_instance_shader_parameter(&"thickness", lerpf(0.25, 0.9, _wave_reach(_age)))
	_wave.set_instance_shader_parameter(&"energy", clampf(1.0 - (_age - WAVE_TIME * 0.6) / 0.25, 0.0, 1.0))
	# the circle flashes white for one frame per stroke: a pop, not a white-out
	_wave.set_instance_shader_parameter(&"flash", (0.7 if _age < 0.018 else (0.3 if _age >= 0.085 and _age < 0.103 else 0.0)))
