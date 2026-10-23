class_name Projectile
extends Node3D
## A spell projectile. It moves in the physics tick and sweeps its path every
## tick: walls stop it (raycast), and fighters are hit with an analytic
## segment-vs-capsule test, so fast bolts never tunnel through anyone. Its
## look comes from SpellFx and is drawn between ticks (TickSmoother).

var caster: Fighter
var spell: ProjectileSpell
var team := 0
var velocity := Vector3.ZERO

var _origin := Vector3.ZERO
var _travelled := 0.0
var _tuning: CombatTuning
var _visual: Node3D
var _smoother: TickSmoother


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
	_face_travel()
	_visual = SpellFx.projectile(spell)
	_visual.top_level = true
	add_child(_visual)
	_smoother = TickSmoother.new(self)
	_process(0.0)


func _physics_process(delta: float) -> void:
	var from := global_position
	var to := from + velocity * delta
	var step := from.distance_to(to)
	var hit_t := INF
	var victim: Fighter = null
	var normal := -velocity.normalized()
	var wall := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1))
	if wall:
		hit_t = from.distance_to(wall.position) / maxf(step, 0.0001)
		normal = wall.normal
	for node in get_tree().get_nodes_in_group(&"fighters"):
		var fighter := node as Fighter
		if fighter.team == team or fighter.state.is_dead():
			continue
		var t := CombatRules.segment_hits_capsule(from, to, fighter.global_position + Vector3.UP * 0.35,
				fighter.global_position + Vector3.UP * 1.45, Fighter.RADIUS + spell.radius)
		if t >= 0.0 and t < hit_t:
			hit_t = t
			victim = fighter
			normal = -velocity.normalized()
	if hit_t <= 1.0:
		_impact(from.lerp(to, hit_t), normal, victim)
		return
	global_position = to
	_smoother.tick()
	_travelled += step
	if _travelled >= spell.max_range:
		_impact(global_position, -velocity.normalized(), null, true)


## Blown off course (a wind burst): same speed, new heading.
func deflect(direction: Vector3) -> void:
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length() < 0.01:
		return
	velocity = flat.normalized() * velocity.length()
	_face_travel()


func _impact(at: Vector3, normal: Vector3, victim: Fighter, spent := false) -> void:
	var travel := velocity.normalized()
	if victim:
		_apply(victim, spell.make_hit(true, travel), victim.global_position - travel, at)
	if spell.splash_radius > 0.0 and not spent:
		for node in get_tree().get_nodes_in_group(&"fighters"):
			var fighter := node as Fighter
			if fighter == victim or fighter.team == team or fighter.state.is_dead():
				continue
			if fighter.chest_position().distance_to(at) <= spell.splash_radius + Fighter.RADIUS:
				_apply(fighter, spell.make_hit(false, travel), at, fighter.chest_position())
	if spell.burst_radius > 0.0:
		WindBurst.blast(caster, spell, at, victim)
	var fizzled := spent and spell.burst_radius <= 0.0
	if not fizzled:
		CombatEvents.spell_impact.emit(caster, spell, at)
	SpellFx.impact(spell, get_parent(), at, normal, victim != null, fizzled)
	SpellFx.release_look(_visual, get_parent())
	queue_free()


func _apply(target: Fighter, hit: SpellHit, source: Vector3, contact: Vector3) -> void:
	var from_front := CombatRules.is_in_front(target.state.facing_yaw, target.global_position, source, _tuning.block_arc)
	var result := CombatRules.resolve_spell(target.state, hit, from_front, _tuning)
	Fighter.report_hit(caster, target, result, contact)


func _process(_delta: float) -> void:
	if is_instance_valid(_visual) and _visual.get_parent() == self:
		_visual.global_transform = Transform3D(global_basis, _smoother.position())


func _face_travel() -> void:
	if velocity.length() > 0.01:
		look_at(global_position + velocity, Vector3.UP if absf(velocity.normalized().y) < 0.99 else Vector3.RIGHT)
