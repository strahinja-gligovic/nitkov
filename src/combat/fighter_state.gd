class_name FighterState
extends RefCounted
## Everything the combat simulation knows about one fighter, as plain data.
## No nodes and no physics: CombatRules and the unit tests work on this
## directly, and it's what a network snapshot of a fighter will contain.

enum Action { IDLE, ATTACK, CAST, DASH, FLINCH, STAGGER, DEAD }

var team := 0
var hp := 100.0
var max_hp := 100.0
var stamina := 100.0
var max_stamina := 100.0
## Seconds until stamina regen resumes.
var regen_delay := 0.0
## Seconds of exhaustion left (see CombatTuning.exhausted_duration).
var exhausted := 0.0

var action := Action.IDLE
## Seconds since the current action began.
var action_time := 0.0

var blocking := false
var facing_yaw := 0.0
var on_floor := true


func reset(tuning: CombatTuning) -> void:
	max_hp = tuning.max_hp
	hp = max_hp
	max_stamina = tuning.max_stamina
	stamina = max_stamina
	regen_delay = 0.0
	exhausted = 0.0
	action = Action.IDLE
	action_time = 0.0
	blocking = false


func is_dead() -> bool:
	return action == Action.DEAD


## Stamina actions may start whenever there's any stamina left (it floors at 0).
func can_spend() -> bool:
	return stamina > 0.0 and exhausted <= 0.0


func spend_stamina(amount: float, tuning: CombatTuning) -> void:
	stamina = maxf(stamina - amount, 0.0)
	regen_delay = tuning.stamina_regen_delay


## Advances timers that run regardless of action.
func tick(delta: float, tuning: CombatTuning) -> void:
	if exhausted > 0.0:
		exhausted = maxf(exhausted - delta, 0.0)
	elif regen_delay > 0.0:
		regen_delay = maxf(regen_delay - delta, 0.0)
	elif stamina < max_stamina:
		var rate := tuning.stamina_regen * (tuning.block_regen_mult if blocking else 1.0)
		stamina = minf(stamina + rate * delta, max_stamina)
