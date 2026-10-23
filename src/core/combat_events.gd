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
signal orb_taken(fighter: Node)
## A leap came down.
signal landed(fighter: Node)
