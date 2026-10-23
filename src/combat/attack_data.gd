class_name AttackData
extends Resource
## One melee swing. It runs windup -> active -> recovery; the blade only hits
## during active. The animation is time-warped so the clip's strike frame
## (strike_time) lands on the first active frame, whatever the timings.

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
## Forward speed during wind-up and active frames (m/s).
@export var lunge_speed := 2.5
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
@export var animation := &"1H_Melee_Attack_Slice_Diagonal"
## Second in the clip where the blade connects.
@export var strike_time := 0.38


func duration() -> float:
	return windup + active + recovery


func is_active_at(time: float) -> bool:
	return time >= windup and time < windup + active
