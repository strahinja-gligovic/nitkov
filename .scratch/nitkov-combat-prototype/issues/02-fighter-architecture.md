# 02 — Command/tick architecture and fighter

Status: ready-for-agent
Blocked by: 01

## What
- `InputCommand` produced by `PlayerInput`, consumed by `Fighter` in `_physics_process`.
- `FighterState` (plain data) and the action state machine (IDLE/ATTACK/CAST/DASH/FLINCH/STAGGER/DEAD), with an input buffer.
- Data resources (`CombatTuning`, `WeaponData`, `AttackData`) loaded from `data/`.
- KayKit Knight and Barbarian models with toon materials. AnimationTree: strafe blend space, upper-body layer, two full-body slots driven by state time.

## Acceptance
- The fighter faces the aim direction, the strafe animations match movement, and the GUT suite runs headless.
