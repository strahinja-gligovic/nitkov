class_name SpellHit
extends RefCounted
## One spell effect reaching one fighter: a projectile impact, a splash, a
## ground-fire tick or a nova. CombatRules.resolve_spell consumes it.

var element := SpellData.Element.NONE
var damage := 0.0
## Ground fire and other area ticks can't be blocked.
var blockable := true
var applies_burn := false
var chill_stacks := 0
var slow_amount := 0.0
var slow_duration := 0.0
## Whether this hit can set off combo reactions (burn ticks can't).
var triggers_reactions := true
## Seconds of flinch: interrupts what the target is doing (not heavy wind-ups).
var flinch := 0.0
## Seconds of stagger (a stun), and what caused it (for the reaction's look).
var stagger := 0.0
var stagger_kind := &""
## Shove: a horizontal velocity added to the target, and an upward pop (m/s).
var push := Vector3.ZERO
var launch := 0.0
## Seconds the target freezes when this lands (hit-stop).
var hitstop := 0.0
## Repeating area damage (e.g. Flame Wall ticks) gets quieter feedback.
var periodic := false
var source := &""
