# 0001: A network-ready simulation driven by InputCommands

## Context

Nitkov is meant to become online PvP. Milestone 1 is single-player only, but the spec requires it to be "structured so online play can be added later without a rewrite". Online play needs one place where intent enters the game, a fighter state that can be snapshotted, and rules that run the same on a server with no window.

## Decision

- Each 60 Hz physics tick (`physics/common/physics_ticks_per_second` in `project.godot`), every `Fighter` pulls one `InputCommand` from its controller and runs `Fighter.simulate()`. `PlayerInput`, `BotBrain` and the autopilot's `ScriptedController` all produce the same commands, so the player and the bot run identical code.
- Combat state is plain data in `FighterState` (a `RefCounted`, no nodes). The rules that resolve hits, blocks, parries, statuses and reactions are pure static functions in `CombatRules`, unit tested headless under `tests/`.
- The simulation never reads `Input`, animation or visuals. It reports what happened through the `CombatEvents` autoload, and presentation (visuals, animation, sound, HUD, camera) only reads state and listens.

## Consequences

- A new rule goes into `src/combat/combat_rules.gd` as a function over `FighterState`, with a GUT test. Rules that need the world, such as sweeps, raycasts and zone occupancy, stay in `Fighter`, `Projectile` and the zone nodes, and hand the result to `CombatRules`.
- `FighterState` is not the whole snapshot. Position and velocity live on the `Fighter` `CharacterBody3D`, and projectiles and zones are nodes with their own state. A network layer has to carry those too.
- Hit-stop and knockback are simulation state, because they change timing and position (`Fighter._apply_melee_impact`). Shake, damage numbers and sounds listen to `CombatEvents.hit_resolved` instead.
- Bots act only through `InputCommand`s. They may read an opponent's `FighterState` (`BotRead`), filtered through a reaction delay. Their dice live in the controller (`BotBrain.rng`, varied by `--seed`). `Fighter`, `CombatRules` and `src/spells/` use no randomness; the `randf` calls in `FighterVisual` and `CameraRig` are presentation.
- Presentation draws between ticks: `TickSmoother` interpolates above 60 Hz and is off in `--fixed-fps` runs. A value that only presentation needs (for example `FighterState.action_serial`) may be added to the state, but presentation never writes it.
- Fire-and-forget `Vfx.*` and `SpellFx` calls from simulation code are allowed because they read and write nothing (see `0003-spell-presentation-through-spellfx.md`).
