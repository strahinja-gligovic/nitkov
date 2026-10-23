class_name ProjectileSpell
extends SpellData
## Fires one or more projectiles toward the aim point (Firebolt, Shard Volley).

@export_group("Projectile")
@export var damage := 12.0
@export var speed := 38.0
@export var radius := 0.28
@export var count := 1
## Degrees between neighbouring projectiles when count > 1.
@export var spread := 0.0
@export var max_range := 60.0

@export_group("Impact")
@export var splash_radius := 0.0
@export var splash_damage := 0.0
@export var applies_burn := false
@export var chill_stacks := 0


func release(caster: Fighter, target: Vector3) -> void:
	var origin := caster.cast_origin()
	var aim := target - origin
	aim = aim.normalized() if aim.length() > 0.5 else caster.forward()
	for i in count:
		var offset := (float(i) - (count - 1) * 0.5) * deg_to_rad(spread)
		var projectile := Projectile.new()
		projectile.setup(caster, self, origin, aim.rotated(Vector3.UP, offset) * speed)
		caster.get_parent().add_child(projectile)


func make_hit(direct: bool) -> SpellHit:
	var hit := SpellHit.new()
	hit.element = element
	hit.source = id
	hit.damage = damage if direct else splash_damage
	hit.applies_burn = applies_burn
	hit.chill_stacks = chill_stacks
	return hit
