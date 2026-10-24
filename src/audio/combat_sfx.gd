class_name CombatSfx
extends Node
## The sounds of melee and movement: sword swings, flesh hits, block clangs,
## parry rings, guard breaks, dashes, landings and deaths. Hits, deaths and
## landings come from CombatEvents; swings and dashes have no event, so their
## start is read off each fighter's state (a new action_serial). Cosmetic
## only: reads state, never writes it. Spell hits are SpellSfx's (here only
## a spell stopped by a guard adds the clang).

## A swing's whoosh peaks this long after it starts (build_sfx.py), so it's
## started that much before the blade's first active frame.
const SWING_PEAK := 0.075
const HEAVY_SWING_PEAK := 0.13

var _swing := SfxPool.Params.new(-4.0, 5.5, 40.0, 0.06, 1)
var _flesh := SfxPool.Params.new(0.0, 7.0, 55.0, 0.06, 2)
var _clang := SfxPool.Params.new(-1.0, 7.0, 55.0, 0.05, 2)
var _parry := SfxPool.Params.new(0.0, 8.0, 60.0, 0.03, 3)
var _break := SfxPool.Params.new(0.0, 8.0, 60.0, 0.03, 3)
var _dash := SfxPool.Params.new(-5.0, 5.0, 35.0, 0.06, 1)
var _land := SfxPool.Params.new(-3.0, 6.0, 45.0, 0.06, 1)
var _death := SfxPool.Params.new(0.0, 8.0, 60.0, 0.03, 3)

## Fighter instance id -> the action_serial already heard.
var _seen := {}
## Swings waiting for their moment: {id, serial, wait, heavy}.
var _pending: Array[Dictionary] = []


func _ready() -> void:
	CombatEvents.hit_resolved.connect(_on_hit_resolved)
	CombatEvents.fighter_died.connect(_on_fighter_died)
	CombatEvents.landed.connect(_on_landed)


func _process(delta: float) -> void:
	for node in get_tree().get_nodes_in_group(&"fighters"):
		var fighter := node as Fighter
		if fighter == null:
			continue
		var s := fighter.state
		var id := fighter.get_instance_id()
		if _seen.get(id, -1) == s.action_serial:
			continue
		_seen[id] = s.action_serial
		if s.action == FighterState.Action.ATTACK and s.attack:
			var peak := HEAVY_SWING_PEAK if s.attack.hyperarmor else SWING_PEAK
			_pending.append({"id": id, "serial": s.action_serial, "heavy": s.attack.hyperarmor,
					"wait": s.attack.windup - peak - s.action_time})
		elif s.action == FighterState.Action.DASH:
			_play(fighter, &"dash", fighter.global_position + Vector3.UP * 0.6, _dash)
	for i in range(_pending.size() - 1, -1, -1):
		var swing := _pending[i]
		swing["wait"] -= delta
		if swing["wait"] > 0.0:
			continue
		_pending.remove_at(i)
		var fighter := instance_from_id(swing["id"]) as Fighter
		# only if that swing is still under way (not interrupted)
		if fighter and fighter.state.action_serial == swing["serial"] \
				and fighter.state.action == FighterState.Action.ATTACK:
			_play(fighter, &"sword_swing_heavy" if swing["heavy"] else &"sword_swing",
					fighter.global_position + Vector3.UP * 1.2, _swing)


func _on_hit_resolved(_attacker: Node, defender: Node, result: HitResult, at: Vector3) -> void:
	if result.periodic or not defender is Node3D:
		return
	match result.outcome:
		HitResult.Outcome.BLOCKED:
			_play(defender, &"block_clang", at, _clang)
		HitResult.Outcome.PARRIED:
			_play(defender, &"parry_ring", at, _parry)
		HitResult.Outcome.GUARD_BREAK:
			_play(defender, &"guard_break", at, _break)
		HitResult.Outcome.HIT:
			if result.element == SpellData.Element.NONE:
				_play(defender, &"flesh_hit", at, _flesh)


func _on_fighter_died(fighter: Node, _killer: Node) -> void:
	if fighter is Node3D:
		_play(fighter, &"death", (fighter as Node3D).global_position + Vector3.UP * 0.5, _death)


func _on_landed(fighter: Node) -> void:
	if fighter is Node3D:
		_play(fighter, &"land", (fighter as Node3D).global_position, _land)


## Plays in `who`'s own world (the arena, or a menu showcase's).
func _play(who: Node, sound: StringName, at: Vector3, params: SfxPool.Params) -> void:
	var pool := SfxPool.of(who)
	if pool:
		pool.play(SfxBank.pick(sound), at, params)
