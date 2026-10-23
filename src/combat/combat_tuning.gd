class_name CombatTuning
extends Resource
## Global combat numbers. Defaults here are the spec's starting values; the
## F1 tuning panel edits the shared instance live and can save it to data/.

@export_group("Health & stamina")
@export var max_hp := 100.0
@export var max_stamina := 100.0
## Stamina per second once regen resumes.
@export var stamina_regen := 35.0
## Seconds after the last stamina spend before regen resumes.
@export var stamina_regen_delay := 0.6
@export var block_regen_mult := 0.5
## No regen, dash, sprint, cast, block or rune for this long after an empty-stamina guard break.
@export var exhausted_duration := 1.5

@export_group("Movement")
@export var walk_speed := 5.0
@export var sprint_speed := 7.5
@export var sprint_stamina_per_sec := 10.0
@export var block_move_mult := 0.5
@export var cast_move_mult := 0.6
@export var ground_accel := 45.0
@export var air_accel := 9.0
@export var gravity := 22.0
## Degrees per second the body turns toward the aim when free to act.
@export var turn_rate := 900.0

@export_group("Block & parry")
## Total degrees in front of the defender that block and parry cover.
@export var block_arc := 180.0
@export var parry_window := 0.15
## Seconds between parry attempts; holding block still blocks meanwhile.
@export var parry_cooldown := 0.6
@export var melee_block_chip := 0.0
@export var spell_block_stamina := 8.0
@export var spell_block_chip := 0.4
@export var guard_break_stagger := 0.8
## Fraction of a heavy's damage that still lands when it breaks a block.
@export var heavy_guard_break_damage := 0.5

@export_group("Dash")
@export var dash_distance := 4.0
@export var dash_duration := 0.25
@export var dash_iframes := 0.15
@export var dash_stamina := 20.0

@export_group("Melee feel")
## Enemies within this many degrees of the swing direction pull the swing toward them.
@export var magnet_angle := 30.0
@export var magnet_range := 4.5
## The lunge stops this far from a magnet target.
@export var magnet_stop_distance := 1.3
@export var knockback_speed := 3.0
## Seconds a button press is remembered while you can't act yet.
@export var input_buffer := 0.18
## Seconds after an attack before the light chain starts over.
@export var combo_reset := 0.5

@export_group("Statuses")
@export var burn_dps := 3.0
@export var burn_duration := 3.0
@export var burn_tick := 0.5
@export var chill_max_stacks := 3
@export var chill_duration := 4.0
## Slow fraction while Chill is at max stacks.
@export var chill_slow := 0.3
@export var shatter_damage := 25.0
@export var shatter_stagger := 1.2

@export_group("Healing & respawn")
@export var orb_heal_fraction := 0.5
@export var orb_heal_duration := 1.0
@export var orb_respawn := 30.0
@export var respawn_time := 3.0

@export_group("Aim assist (controller only)")
## Look speed multiplier while the crosshair is near an enemy.
@export var assist_slowdown := 0.45
@export var assist_angle := 6.0
## Spells bend toward an enemy this close to the crosshair (degrees).
@export var assist_magnet_angle := 3.0
