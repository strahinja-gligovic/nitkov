class_name HitResult
extends RefCounted
## What happened when a melee swing or spell met a fighter.

enum Outcome { HIT, BLOCKED, PARRIED, GUARD_BREAK, IGNORED }

var outcome := Outcome.HIT
## Health actually removed from the defender (including chip damage).
var damage := 0.0
## Combo reaction this hit triggered (e.g. &"shatter"), or &"" for none.
var reaction := &""
var killed := false
## Id of the attack or spell that caused it.
var source := &""
var element := SpellData.Element.NONE
## Repeating area damage (e.g. Flame Wall ticks).
var periodic := false
