class_name FlameWall
extends Node3D
## A line of burning ground. Every tick_interval it burns enemies standing in
## it (unblockable Fire hits that can set off Shatter), then dies out.

var caster: Fighter
var spell: FlameWallSpell
var team := 0

var _centre := Vector3.ZERO
## Unit vector along the wall's length; the wall faces _facing.
var _axis := Vector3.RIGHT
var _facing := Vector3.FORWARD
var _age := 0.0
var _tick := 0.0
var _look: FlameWallLook
var _tuning: CombatTuning


func setup(from: Fighter, data: FlameWallSpell, centre: Vector3, facing: Vector3) -> void:
	caster = from
	spell = data
	team = from.team
	_centre = centre
	_facing = facing
	_axis = facing.cross(Vector3.UP).normalized()
	_tuning = from.tuning


func _ready() -> void:
	add_to_group(&"zones")
	global_position = _centre
	look_at(_centre + _facing, Vector3.UP)
	_look = SpellFx.flame_wall(spell)
	add_child(_look)


## The short way out of the fire for someone standing at `point`.
func exit_direction(point: Vector3) -> Vector3:
	return _facing if (point - _centre).dot(_facing) >= 0.0 else -_facing


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= spell.duration:
		queue_free()
		return
	_tick += delta
	while _tick >= spell.tick_interval:
		_tick -= spell.tick_interval
		_burn_occupants()
	var intensity := clampf(_age / 0.2, 0.0, 1.0) * clampf((spell.duration - _age) / 0.4, 0.0, 1.0)
	_look.set_intensity(intensity)


func contains(point: Vector3, margin := 0.0) -> bool:
	var local := point - _centre
	return absf(local.dot(_axis)) <= spell.length * 0.5 + margin \
			and absf(local.dot(_facing)) <= spell.width * 0.5 + margin \
			and local.y > -1.0 and local.y < spell.height


func _burn_occupants() -> void:
	for node in get_tree().get_nodes_in_group(&"fighters"):
		var fighter := node as Fighter
		if fighter.team == team or fighter.state.is_dead() or not contains(fighter.global_position, Fighter.RADIUS):
			continue
		var hit := SpellHit.new()
		hit.element = SpellData.Element.FIRE
		hit.source = spell.id
		hit.damage = spell.damage_per_second * spell.tick_interval
		hit.blockable = false
		hit.periodic = true
		var result := CombatRules.resolve_spell(fighter.state, hit, false, _tuning)
		Fighter.report_hit(caster, fighter, result, fighter.chest_position())

