class_name TtkTracker
extends Node
## Measures time-to-kill for every life, in game time. Two numbers per kill:
##   wall clock - first damage since spawning at full health -> death
##                (includes retreats and orb runs)
##   under fire - only the stretches where damage kept coming, each gap
##                capped at 1s: the spec's "4-6s of sustained hits"

signal kill_measured(victim: Node, killer: Node, wall_clock: float, under_fire: float)

var time := 0.0
var wall_clock: Array[float] = []
var under_fire: Array[float] = []

var _engaged := {}
var _fire := {}
var _last := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	CombatEvents.hit_resolved.connect(func(_a: Node, d: Node, r: HitResult, _p: Vector3) -> void:
		if r.damage > 0.0:
			_note_damage(d))
	CombatEvents.status_damage.connect(func(f: Node, _amount: float, _e: int) -> void: _note_damage(f))
	CombatEvents.fighter_died.connect(_on_died)
	CombatEvents.fighter_respawned.connect(_forget)


func _physics_process(delta: float) -> void:
	time += delta


## Seconds the fighter's current life has been under attack (0 if untouched).
func engaged_for(fighter: Node) -> float:
	return time - float(_engaged[fighter]) if _engaged.has(fighter) else 0.0


func _note_damage(fighter: Node) -> void:
	if not _engaged.has(fighter):
		_engaged[fighter] = time
		_fire[fighter] = 0.0
	else:
		_fire[fighter] += minf(time - float(_last[fighter]), 1.0)
	_last[fighter] = time


func _on_died(fighter: Node, killer: Node) -> void:
	if _engaged.has(fighter):
		var clock := time - float(_engaged[fighter])
		var fire := float(_fire[fighter])
		wall_clock.append(clock)
		under_fire.append(fire)
		kill_measured.emit(fighter, killer, clock, fire)
	_forget(fighter)


func _forget(fighter: Node) -> void:
	_engaged.erase(fighter)
	_fire.erase(fighter)
	_last.erase(fighter)


static func summary(label: String, values: Array[float]) -> String:
	if values.is_empty():
		return "%s: no kills yet" % label
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for value in sorted:
		total += value
	return "%s: avg %.1fs, median %.1fs, min %.1fs, max %.1fs over %d kills" % [
			label, total / sorted.size(), sorted[sorted.size() / 2], sorted[0], sorted[-1], sorted.size()]
