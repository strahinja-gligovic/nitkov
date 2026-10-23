class_name LightningStrikeSpell
extends SpellData
## Calls lightning down on the aim point: the ground there is marked, and
## after `delay` a bolt strikes from the sky, hurting and stunning everyone
## still inside. It comes from above, so guards don't stop it; the warning is
## your chance to get out.

@export_group("Strike")
@export var radius := 2.5
## Seconds between the mark appearing and the bolt landing.
@export var delay := 0.9
@export var damage := 24.0
## Stun on everyone it hits.
@export var stagger := 1.0
@export var launch := 2.5
## How far from the caster the mark can be placed.
@export var max_range := 18.0
@export var min_range := 3.0


func release(caster: Fighter, target: Vector3) -> void:
	var flat := target - caster.global_position
	flat.y = 0.0
	var direction := flat.normalized() if flat.length() > 0.1 else caster.forward()
	var centre := caster.global_position + direction * clampf(flat.length(), min_range, max_range)
	# settle onto whatever ground is there (the arena floor or the ledge)
	var down := PhysicsRayQueryParameters3D.create(centre + Vector3.UP * 4.0, centre + Vector3.DOWN * 10.0, 1)
	var ground := caster.get_world_3d().direct_space_state.intersect_ray(down)
	if ground:
		centre.y = ground.position.y
	var strike := LightningStrike.new()
	strike.setup(caster, self, centre)
	caster.get_parent().add_child(strike)
