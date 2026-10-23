class_name AttackData
extends Resource
## One melee swing. It runs windup -> active -> recovery; the blade only hits
## during active. Its look is a move in the MoveSet, time-remapped so the
## blade connects on the first active frame, whatever the timings.

const LUNGE_STEP := 1.0 / 60.0

@export var id := &"light_1"
@export var damage := 8.0
@export var stamina_cost := 10.0

@export_group("Timing")
@export var windup := 0.15
@export var active := 0.08
@export var recovery := 0.3
## Seconds into recovery after which the next attack can cancel it.
@export var chain_after := 0.13
## Seconds into recovery after which a dash or rune can cancel it.
@export var dodge_cancel_after := 0.1

@export_group("Reach")
## Hit distance from the attacker's centre to the target's surface.
@export var reach := 2.3
## Total degrees of the swing arc, centred on the facing direction.
@export var arc := 110.0
## Metres stepped forward since the attack began, sampled every
## LUNGE_STEP seconds. Baked from the animation's own footwork (with its time
## remap), so the body travels exactly as the feet step: no sliding.
@export var lunge_profile := PackedFloat32Array()
## Scales the whole lunge (1 = the animation's footwork).
@export var lunge_scale := 1.0
## Degrees per second the attacker can still turn during wind-up.
@export var windup_turn_rate := 360.0

@export_group("On hit")
@export var flinch := 0.25
@export var hitstop := 0.06
@export var knockback := 2.0
## Stamina the defender pays to block this swing.
@export var block_stamina_cost := 10.0
## How long the attacker is staggered if this swing gets parried.
@export var parry_stagger := 1.0
@export var hyperarmor := false
@export var breaks_block := false

@export_group("Animation")
## Move id in the MoveSet.
@export var animation := &"light_1"


func duration() -> float:
	return windup + active + recovery


func is_active_at(time: float) -> bool:
	return time >= windup and time < windup + active


## Metres stepped forward `time` seconds into the attack.
func lunge_at(time: float) -> float:
	var count := lunge_profile.size()
	if count == 0:
		return 0.0
	var at := clampf(time / LUNGE_STEP, 0.0, count - 1.0)
	var i := mini(int(at), count - 2) if count > 1 else 0
	if count == 1:
		return lunge_profile[0] * lunge_scale
	return lerpf(lunge_profile[i], lunge_profile[i + 1], at - i) * lunge_scale


## Forward speed (m/s) of the lunge over the tick starting at `time`.
func lunge_speed_at(time: float, delta: float) -> float:
	if delta <= 0.0:
		return 0.0
	return (lunge_at(time + delta) - lunge_at(time)) / delta


func total_lunge() -> float:
	return lunge_at(duration())
