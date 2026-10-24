class_name LightningStrike
extends Node3D
## A marked spot where lightning is about to land (LightningStrikeSpell). It
## warns for `delay` seconds, then the bolt strikes: unblockable Lightning
## hits that stun everyone inside. Listed in "zones" so bots step out.

var caster: Fighter
var spell: LightningStrikeSpell
var team := 0

var _centre := Vector3.ZERO
var _age := 0.0
var _struck := false
var _tuning: CombatTuning
var _warning: Node3D


func setup(from: Fighter, data: LightningStrikeSpell, centre: Vector3) -> void:
	caster = from
	spell = data
	team = from.team
	_centre = centre
	_tuning = from.tuning


func _ready() -> void:
	add_to_group(&"zones")
	global_position = _centre
	_warning = SpellFx.strike_warning(spell, self)


## Dangerous until the bolt has landed.
func contains(point: Vector3, margin := 0.0) -> bool:
	return not _struck and _inside(point, margin)


## Inside the circle, standing on the ground it marks (or up to 3 m above it,
## mid-jump): someone on the floor beside a ledge isn't under a strike that
## lands on top of it. The slack below allows for the ramp's slope.
func _inside(point: Vector3, margin: float) -> bool:
	var offset := point - _centre
	return Vector2(offset.x, offset.z).length() <= spell.radius + margin and offset.y > -1.2 and offset.y < 3.0


## The short way out for someone standing at `point`.
func exit_direction(point: Vector3) -> Vector3:
	var away := point - _centre
	away.y = 0.0
	return away.normalized() if away.length() > 0.05 else Vector3.RIGHT


func _physics_process(delta: float) -> void:
	_age += delta
	if not _struck and _age >= spell.delay:
		_strike()
	if _age >= spell.delay + 1.0:
		queue_free()


func _strike() -> void:
	_struck = true
	if is_instance_valid(_warning):
		_warning.queue_free()
	if not is_instance_valid(caster):
		caster = null  # they left the match: it still strikes, uncredited
	for node in get_tree().get_nodes_in_group(&"fighters"):
		var fighter := node as Fighter
		if fighter.team == team or fighter.state.is_dead() or not _inside(fighter.global_position, Fighter.RADIUS):
			continue
		var hit := SpellHit.new()
		hit.element = spell.element
		hit.source = spell.id
		hit.damage = spell.damage
		hit.blockable = false
		hit.stagger = spell.stagger
		hit.stagger_kind = &"shock"
		hit.launch = spell.launch
		hit.hitstop = spell.hitstop
		var result := CombatRules.resolve_spell(fighter.state, hit, false, _tuning)
		Fighter.report_hit(caster, fighter, result, fighter.chest_position())
	CombatEvents.spell_impact.emit(caster, spell, _centre)
	SpellFx.strike(spell, get_parent(), _centre)
