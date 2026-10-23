class_name WindBurst
extends RefCounted
## A burst of wind where a Wind Spear lands: every fighter in reach is shoved
## away from the centre and popped up (enemies also take damage; the caster
## and allies are only blown away, so you can blast yourself clear), and
## enemy projectiles inside it are blown off course. Walls and pillars
## shelter whoever is behind them.


## `spear` is the projectile bursting at `at`; `normal` faces out of the
## surface it hit (or back along its flight); `struck` is whoever it hit.
static func blast(spear: Projectile, at: Vector3, normal: Vector3, struck: Fighter) -> void:
	var spell := spear.spell
	var caster := spear.caster  # null once they've left the match
	var tuning := GameData.tuning
	var space := spear.get_world_3d().direct_space_state
	var eye := at + normal * 0.1  # just off the surface, so sight lines don't start inside it
	for node in spear.get_tree().get_nodes_in_group(&"fighters"):
		var fighter := node as Fighter
		if fighter.state.is_dead():
			continue
		var offset := fighter.global_position + Vector3.UP * 0.9 - at
		var distance := offset.length()
		if distance > spell.burst_radius + Fighter.RADIUS:
			continue
		if fighter != struck and not space.intersect_ray(
				PhysicsRayQueryParameters3D.create(eye, fighter.chest_position(), 1)).is_empty():
			continue
		var away := Vector3(offset.x, 0.0, offset.z)
		if away.length() < 0.05:
			# dead centre: blow them the way the spear was flying
			away = Vector3(spear.velocity.x, 0.0, spear.velocity.z)
		away = away.normalized() if away.length() > 0.001 else -fighter.forward()
		var falloff := lerpf(1.0, 0.5, clampf(distance / spell.burst_radius, 0.0, 1.0))
		var push := away * spell.burst_push * falloff
		var launch := spell.burst_launch * falloff
		if fighter.team != spear.team:
			var hit := SpellHit.new()
			hit.element = spell.element
			hit.source = spell.id
			hit.damage = spell.burst_damage
			hit.push = push
			hit.launch = launch
			hit.hitstop = spell.burst_hitstop
			if fighter == struck:
				hit.damage *= 0.5  # the spear itself already hit them
			var from_front := CombatRules.is_in_front(fighter.state.facing_yaw, fighter.global_position, at, tuning.block_arc)
			var result := CombatRules.resolve_spell(fighter.state, hit, from_front, tuning)
			Fighter.report_hit(caster, fighter, result, fighter.chest_position())
		elif spell.burst_moves_allies:
			CombatRules.apply_push(fighter.state, push, launch)
	if spell.burst_deflects:
		for node in spear.get_tree().get_nodes_in_group(&"projectiles"):
			var projectile := node as Projectile
			if projectile.team != spear.team and projectile.global_position.distance_to(at) <= spell.burst_radius:
				projectile.deflect(projectile.global_position - at, spear)
