extends Node
## Event bus for combat (autoload "CombatEvents"). The simulation emits;
## HUD, VFX, camera shake and the combat log listen. Nothing listening here
## may change simulation state.

## A melee or spell hit was resolved. `result` is a CombatRules.HitResult.
signal hit_resolved(attacker: Node, defender: Node, result: RefCounted, at: Vector3)
## Damage from a status effect (burn) ticked.
signal status_damage(fighter: Node, amount: float, element: int)
signal fighter_died(fighter: Node, killer: Node)
signal fighter_respawned(fighter: Node)
signal spell_cast(fighter: Node, spell: Resource)
## A spell landed at `at`, hit or not: a projectile struck something or
## burst, a Lightning Strike came down, a Frost Nova or Flame Wall went off.
## (Projectiles that fizzle out of range don't count.)
signal spell_impact(caster: Node, spell: Resource, at: Vector3)
signal orb_taken(fighter: Node)
## A leap came down.
signal landed(fighter: Node)
