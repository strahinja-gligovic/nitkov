# 0003: Spell presentation goes through SpellFx, one module per element

## Context

Ticket 15 grew the game to four elements and eight spells, each needing a charge, release, travel, impact and aftermath, plus sounds, camera feel and body reactions. The elements were built in parallel. Projectiles and zones are simulation nodes, and they must stay headless-safe and unaware of how they look (see `0001-network-ready-simulation.md`).

## Decision

- Simulation code (`Projectile`, `FlameWall`, `LightningStrike`, `NovaSpell`) calls only `SpellFx` (`src/vfx/spell_fx.gd`) and never builds visuals or plays sounds itself.
- `SpellFx` routes by element to `FireFx`, `FrostFx`, `LightningFx` and `WindFx` (one folder per element under `src/vfx/<element>/`), and calls `SpellSfx` (`src/audio/spell_sfx.gd`) next to each visual.
- The beats that follow presentation state are triggered from presentation: `FighterVisual` calls `SpellFx.charge`, `cancel_charge`, `release` and `shock`, and `CombatFeedback` calls `SpellFx.shatter` on the `shatter` reaction.

## Consequences

- Every effect is fire-and-forget: it frees itself, reads nothing back, and its randomness is cosmetic. A look handed back to simulation (a projectile body, the Flame Wall fire, the strike warning) is driven only by its owner, for example `FlameWallLook.set_intensity`.
- Routing is by `SpellData.element` and the data's shape, not by spell id: Wind picks spear or slash by `burst_radius > 0`. A second spell of the same shape in an element needs its own branch in `SpellFx`.
- The release flash is drawn at the visual's gauntlet core, while the projectile spawns at `Fighter.cast_origin()`, so the cast move is what keeps them together (see `docs/agents/animation.md`).
- Every new effect is built in `SpellFx.prewarm`, which runs at arena load (`src/world/training_mode.gd`).
- The authoritative presentation contract and the steps for adding a spell are in `docs/agents/spells.md`. Art direction and the effect conventions are in `docs/agents/vfx.md`, and sound is in `docs/agents/audio.md`.
