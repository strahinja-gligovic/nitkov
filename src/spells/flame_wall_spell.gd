class_name FlameWallSpell
extends SpellData
## Raises a line of burning ground across the aim point.

@export_group("Wall")
@export var length := 8.0
@export var width := 1.2
@export var height := 2.2
@export var duration := 4.0
@export var damage_per_second := 8.0
@export var tick_interval := 0.25
## How far from the caster the wall can be placed.
@export var max_range := 16.0
@export var min_range := 2.5


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
	var wall := FlameWall.new()
	wall.setup(caster, self, centre, direction)
	caster.get_parent().add_child(wall)
