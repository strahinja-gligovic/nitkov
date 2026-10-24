# 0004: Animation is data, timed to the simulation and never read by it

## Context

The clips (Quaternius UAL 1 and 2, Mesh2Motion) have their own timing, but the simulation's timing is tuned data: wind-up, active and recovery per swing, wind-up per cast. Ticket 14 required the blade to be at the target line on the frame the hit registers, and no foot sliding. The simulation must also stay deterministic and runnable headless, with no skeleton.

## Decision

- Moves are data. `data/moves/humanoid.tres` is a `MoveSet` of `AnimMove`s (clip window, key poses, `strike`, `hold`, `settle_fraction`, `mirror`, chained clips), and `AttackData.animation` and `SpellData.animation` name moves in it. `tools/moveset/build_moveset.py` writes it from measurements of the clips (`tools/moveset/data/`).
- `TimeRemap` pins each key pose to its simulation beat at runtime: contact lands when the wind-up ends, and the motion between keys keeps the clip's own spacing.
- The simulation never reads animation. A swing's forward step comes from `AttackData.lunge_profile`, baked offline by the same script from the clip's root motion through the same remap. Projectiles spawn at the fixed `Fighter.cast_origin()`.
- `AnimLibrary` converts every clip for each character's rest pose at load, and bakes mirrored and spliced copies. `AnimDirector` drives the rig and never writes state.

## Consequences

- Gameplay timing can be tuned freely without touching clips, and a cast's contact key is where its spell visibly leaves the hand.
- The remap runs live, so contact stays on time after any timing change. The baked lunge does not: after changing a swing's `windup`, `active` or `recovery`, re-run `build_moveset.py` (the command is in `CLAUDE.md`), or the feet slide.
- `humanoid.tres` is rewritten whole, so moves are edited in `build_moveset.py` and `tools/moveset/moves_react.py`.
- What the regenerate writes and strips, the Python mirror of `TimeRemap.swing_keys`, and the procedures (adding a cast move, mirroring, reactions by `stagger_kind`, probing a move) are in `docs/agents/animation.md`.
