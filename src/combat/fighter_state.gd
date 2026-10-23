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
## Fixed length of FLINCH, STAGGER and DASH actions.
var action_duration := 0.0
## Increments on every new action, so viewers can tell two identical swings apart.
var action_serial := 0
## Why the fighter is staggered (&"parried", &"guard_break", &"shatter"); display only.
var stagger_kind := &""
var attack: AttackData
## Index into the weapon's light chain of the current (or last) light attack.
var combo_index := -1
## Seconds since the last attack ended; the chain restarts after CombatTuning.combo_reset.
var since_attack := 99.0
## Instance ids of fighters the current swing already hit.
var swing_hits: Array[int] = []
var spell: SpellData
var spell_released := false
var dash_dir := Vector3.ZERO

var blocking := false
var parry_window := 0.0
var parry_cooldown := 0.0
var invulnerable := 0.0
## While > 0 the fighter is frozen mid-swing by a melee impact.
var hitstop := 0.0
var knockback := Vector3.ZERO

var facing_yaw := 0.0
var on_floor := true
var leaping := false

## Buffered button presses: InputCommand bit -> seconds left.
var buffer := {}

var burn_time := 0.0
var burn_tick := 0.0
var chill_stacks := 0
var chill_time := 0.0
var slow_time := 0.0
var slow_amount := 0.0
var heal_time := 0.0
var heal_rate := 0.0

var signature_cd := 0.0
var rune_cd := 0.0
var dead_time := 0.0


func reset(tuning: CombatTuning) -> void:
	max_hp = tuning.max_hp
	hp = max_hp
	max_stamina = tuning.max_stamina
	stamina = max_stamina
	regen_delay = 0.0
	exhausted = 0.0
	_clear_action()
	action_serial += 1
	combo_index = -1
	since_attack = 99.0
	blocking = false
	parry_window = 0.0
	parry_cooldown = 0.0
	invulnerable = 0.0
	hitstop = 0.0
	knockback = Vector3.ZERO
	leaping = false
	buffer.clear()
	clear_statuses()
	signature_cd = 0.0
	rune_cd = 0.0
	dead_time = 0.0


func clear_statuses() -> void:
	burn_time = 0.0
	burn_tick = 0.0
	chill_stacks = 0
	chill_time = 0.0
	slow_time = 0.0
	slow_amount = 0.0
	heal_time = 0.0
	heal_rate = 0.0


func is_dead() -> bool:
	return action == Action.DEAD


## Free to start a new action this tick.
func is_actionable() -> bool:
	return action == Action.IDLE and hitstop <= 0.0


## Stamina actions may start whenever there's any stamina left (it floors at 0).
func can_spend() -> bool:
	return stamina > 0.0 and exhausted <= 0.0


func spend_stamina(amount: float, tuning: CombatTuning) -> void:
	stamina = maxf(stamina - amount, 0.0)
	regen_delay = tuning.stamina_regen_delay


func start_action(new_action: Action, duration := 0.0) -> void:
	if action == Action.ATTACK:
		since_attack = 0.0
	_clear_action()
	action = new_action
	action_duration = duration
	action_serial += 1


func end_action() -> void:
	start_action(Action.IDLE)


## Heavy attacks shrug off flinches through their wind-up and active frames.
func has_hyperarmor() -> bool:
	return action == Action.ATTACK and attack != null and attack.hyperarmor \
			and action_time < attack.windup + attack.active


## A short hit reaction. Never shortens a stagger already in progress.
func apply_flinch(duration: float) -> void:
	if is_dead() or duration <= 0.0:
		return
	if action == Action.STAGGER and action_duration - action_time >= duration:
		return
	start_action(Action.FLINCH, duration)


func apply_stagger(duration: float, kind: StringName) -> void:
	if is_dead():
		return
	if action == Action.STAGGER and action_duration - action_time >= duration:
		return
	start_action(Action.STAGGER, duration)
	stagger_kind = kind


## Returns true if this damage killed the fighter.
func take_damage(amount: float) -> bool:
	if is_dead() or amount <= 0.0:
		return false
	hp = maxf(hp - amount, 0.0)
	heal_time = 0.0  # damage interrupts orb healing
	if hp <= 0.0:
		start_action(Action.DEAD)
		clear_statuses()
		dead_time = 0.0
		return true
	return false


func buffer_presses(bits: int, tuning: CombatTuning) -> void:
	var bit := 1
	while bits >= bit:
		if bits & bit:
			buffer[bit] = tuning.input_buffer
		bit <<= 1


func has_buffered(bit: int) -> bool:
	return buffer.get(bit, 0.0) > 0.0


func consume_buffered(bit: int) -> bool:
	if has_buffered(bit):
		buffer.erase(bit)
		return true
	return false


## Advances timers that run regardless of the current action.
func tick(delta: float, tuning: CombatTuning) -> void:
	if exhausted > 0.0:
		exhausted = maxf(exhausted - delta, 0.0)
	elif regen_delay > 0.0:
		regen_delay = maxf(regen_delay - delta, 0.0)
	elif stamina < max_stamina and not is_dead():
		var rate := tuning.stamina_regen * (tuning.block_regen_mult if blocking else 1.0)
		stamina = minf(stamina + rate * delta, max_stamina)
	parry_window = maxf(parry_window - delta, 0.0)
	parry_cooldown = maxf(parry_cooldown - delta, 0.0)
	invulnerable = maxf(invulnerable - delta, 0.0)
	signature_cd = maxf(signature_cd - delta, 0.0)
	rune_cd = maxf(rune_cd - delta, 0.0)
	since_attack += delta
	for bit: int in buffer.keys():
		buffer[bit] -= delta
		if buffer[bit] <= 0.0:
			buffer.erase(bit)
	if is_dead():
		dead_time += delta


func _clear_action() -> void:
	action = Action.IDLE
	action_time = 0.0
	action_duration = 0.0
	stagger_kind = &""
	attack = null
	swing_hits.clear()
	spell = null
	spell_released = false
	blocking = false
