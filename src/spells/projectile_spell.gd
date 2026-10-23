class_name ProjectileSpell
extends SpellData
## Fires one or more projectiles toward the aim point (Firebolt, Ice Spike,
## Lightning Bolt, Wind Slash, Wind Spear). How each one looks lives in
## SpellFx; this is what it does.

@export_group("Projectile")
@export var damage := 12.0
@export var speed := 38.0
## Hit radius around the flight line (a wide wind crescent is ~1 m).
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
## Seconds the target is interrupted (0 = no flinch).
@export var flinch := 0.0
## Shove along the flight (m/s) and upward pop (m/s) on the target.
@export var push := 0.0
@export var launch := 0.0

@export_group("Burst")
## Bursts where it lands (a wall, the floor, a fighter, or the end of its
## flight): everyone within burst_radius is shoved away from the centre.
@export var burst_radius := 0.0
@export var burst_damage := 0.0
## Shove at the centre (m/s); half that at the edge.
@export var burst_push := 0.0
@export var burst_launch := 0.0
## The caster and allies get shoved too (no damage): blast yourself away.
@export var burst_moves_allies := true
## Enemy projectiles inside the burst are blown away from it.
@export var burst_deflects := true


func release(caster: Fighter, target: Vector3) -> void:
	var origin := caster.cast_origin()
	var aim := target - origin
	aim = aim.normalized() if aim.length() > 0.5 else caster.forward()
	for i in count:
		var offset := (float(i) - (count - 1) * 0.5) * deg_to_rad(spread)
		var projectile := Projectile.new()
		projectile.setup(caster, self, origin, aim.rotated(Vector3.UP, offset) * speed)
		caster.get_parent().add_child(projectile)


func make_hit(direct: bool, travel: Vector3) -> SpellHit:
	var hit := SpellHit.new()
	hit.element = element
	hit.source = id
	hit.damage = damage if direct else splash_damage
	hit.applies_burn = applies_burn
	hit.chill_stacks = chill_stacks
	if direct:
		hit.flinch = flinch
		var flat := Vector3(travel.x, 0.0, travel.z)
		hit.push = flat.normalized() * push if flat.length() > 0.001 else Vector3.ZERO
		hit.launch = launch
	return hit
