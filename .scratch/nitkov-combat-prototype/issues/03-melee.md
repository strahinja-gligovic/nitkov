# 03 — Melee: light chain and heavy

Status: ready-for-agent
Blocked by: 02

## What
- 3-hit light chain and a heavy (glowing tell, hyperarmor). Arc hit queries during the active frames, one hit per target per swing.
- Soft magnet (rotation and lunge assist), flinch, knockback, hit-stop, camera shake.
- Animations time-warped so the strike frame lands on the active frame.

## Acceptance
- Unit tests: a light hit flinches, a heavy wind-up ignores light flinch, dead/invulnerable targets are ignored.
