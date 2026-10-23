class_name Projectile
extends Node3D
## A spell projectile. It moves in the physics tick and sweeps its path every
## tick: walls stop it (raycast), and fighters are hit with an analytic
## segment-vs-capsule test, so fast bolts never tunnel through anyone.

var caster: Fighter
var spell: ProjectileSpell
var team := 0
var velocity := Vector3.ZERO

var _origin := Vector3.ZERO
var _travelled := 0.0
var _tuning: CombatTuning


func setup(from: Fighter, data: ProjectileSpell, origin: Vector3, initial_velocity: Vector3) -> void:
	caster = from
	spell = data
	team = from.team
	_origin = origin
	velocity = initial_velocity
	_tuning = from.tuning


func _ready() -> void:
	add_to_group(&"projectiles")
	global_position = _origin
	_build_visual()


func _physics_process(delta: float) -> void:
	var from := global_position
	var to := from + velocity * delta
	var step := from.distance_to(to)
	var hit_t := INF
	var victim: Fighter = null
	var wall := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1))
	if wall:
		hit_t = from.distance_to(wall.position) / maxf(step, 0.0001)
	for node in get_tree().get_nodes_in_group(&"fighters"):
		var fighter := node as Fighter
		if fighter.team == team or fighter.state.is_dead():
			continue
		var t := CombatRules.segment_hits_capsule(from, to, fighter.global_position + Vector3.UP * 0.35,
				fighter.global_position + Vector3.UP * 1.45, Fighter.RADIUS + spell.radius)
		if t >= 0.0 and t < hit_t:
			hit_t = t
			victim = fighter
	if hit_t <= 1.0:
		_impact(from.lerp(to, hit_t), victim)
		return
	global_position = to
	_travelled += step
	if _travelled >= spell.max_range:
		Vfx.impact(get_parent(), global_position, SpellData.element_color(spell.element), 0.5, 0.15)
		queue_free()


func _impact(at: Vector3, victim: Fighter) -> void:
	var travel := velocity.normalized()
	if victim:
		_apply(victim, spell.make_hit(true), victim.global_position - travel, at)
	if spell.splash_radius > 0.0:
		for node in get_tree().get_nodes_in_group(&"fighters"):
			var fighter := node as Fighter
			if fighter == victim or fighter.team == team or fighter.state.is_dead():
				continue
			if fighter.chest_position().distance_to(at) <= spell.splash_radius + Fighter.RADIUS:
				_apply(fighter, spell.make_hit(false), at, fighter.chest_position())
	Vfx.impact(get_parent(), at, SpellData.element_color(spell.element), 1.1 + spell.splash_radius * 0.4, 0.25, 6.0)
	if spell.splash_radius > 0.0:
		Vfx.ring(get_parent(), at - Vector3.UP * 0.6, SpellData.element_color(spell.element), spell.splash_radius, 0.3)
	queue_free()


func _apply(target: Fighter, hit: SpellHit, source: Vector3, contact: Vector3) -> void:
	var from_front := CombatRules.is_in_front(target.state.facing_yaw, target.global_position, source, _tuning.block_arc)
	var result := CombatRules.resolve_spell(target.state, hit, from_front, _tuning)
	Fighter.report_hit(caster, target, result, contact)


func _build_visual() -> void:
	var color := SpellData.element_color(spell.element)
	var body := MeshInstance3D.new()
	if spell.element == SpellData.Element.FROST:
		var shard := CylinderMesh.new()
		shard.top_radius = 0.0
		shard.bottom_radius = spell.radius * 0.6
		shard.height = 0.9
		shard.radial_segments = 5
		shard.rings = 1
		body.mesh = shard
		body.rotation_degrees = Vector3(-90.0, 0.0, 0.0)  # point the tip along -Z (travel)
		body.material_override = ToonMaterials.make(color.lightened(0.4), {&"glow_color": color, &"glow_energy": 1.5})
	else:
		var core := SphereMesh.new()
		core.radius = spell.radius
		core.height = spell.radius * 2.0
		body.mesh = core
		body.material_override = ToonMaterials.make_vfx(color.lightened(0.35), 4.0, false)
		var halo := MeshInstance3D.new()
		var halo_mesh := SphereMesh.new()
		halo_mesh.radius = spell.radius * 1.8
		halo_mesh.height = spell.radius * 3.6
		halo.mesh = halo_mesh
		halo.scale = Vector3(1.0, 1.0, 2.2)  # stretched into a comet tail
		halo.position = Vector3(0.0, 0.0, spell.radius * 1.5)
		var halo_material := ToonMaterials.make_vfx(color, 2.0)
		halo_material.albedo_color.a = 0.45
		halo.material_override = halo_material
		add_child(halo)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(body)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 1.6
	light.omni_range = 4.0
	add_child(light)
	if velocity.length() > 0.01:
		look_at(global_position + velocity, Vector3.UP if absf(velocity.normalized().y) < 0.99 else Vector3.RIGHT)
