class_name NovaSpell
extends SpellData
## A blast around the caster (Frost Nova). Blockable by guards facing the
## caster; needs line of sight.

@export_group("Blast")
@export var radius := 5.0
@export var damage := 10.0
@export var chill_stacks := 3
@export var slow_amount := 0.4
@export var slow_duration := 2.0


func release(caster: Fighter, _target: Vector3) -> void:
	var space := caster.get_world_3d().direct_space_state
	for foe in caster.enemies():
		var offset := foe.global_position - caster.global_position
		if absf(offset.y) > 2.5 or Vector2(offset.x, offset.z).length() > radius + Fighter.RADIUS:
			continue
		var sight := PhysicsRayQueryParameters3D.create(caster.chest_position(), foe.chest_position(), 1)
		if not space.intersect_ray(sight).is_empty():
			continue
		var hit := SpellHit.new()
		hit.element = element
		hit.source = id
		hit.damage = damage
		hit.chill_stacks = chill_stacks
		hit.slow_amount = slow_amount
		hit.slow_duration = slow_duration
		var from_front := CombatRules.is_in_front(foe.state.facing_yaw, foe.global_position,
				caster.global_position, caster.tuning.block_arc)
		var result := CombatRules.resolve_spell(foe.state, hit, from_front, caster.tuning)
		Fighter.report_hit(caster, foe, result, foe.chest_position())
	CombatEvents.spell_impact.emit(caster, self, caster.global_position)
	SpellFx.nova(self, caster.get_parent(), caster.global_position)
