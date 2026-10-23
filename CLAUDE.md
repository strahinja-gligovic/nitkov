# Nitkov

An original PvP arena brawler prototype in **Godot 4.7 / GDScript**: elemental gauntlet spells with combos, block/parry melee, and one shared stamina pool. The design and milestone-1 scope are in `.scratch/nitkov-combat-prototype/spec.md`; tickets are in its `issues/` folder.

## Commands

The Godot console binary is installed through winget: `godot_console` (`%LOCALAPPDATA%\Microsoft\WinGet\Links\godot_console.exe`).

- **Import / refresh the class cache:** `godot_console --headless --path . --import`. Run this after adding a new `class_name` script, or other scripts won't see it.
- **Play:** `godot_console --path .`, or open the project in the editor and press F5.
- **Unit tests (GUT):** `godot_console --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit`
- **Automated run with screenshots:** `godot_console --path . --fixed-fps 60 -- --drive=<scenario> --shots=1.0,2.5 --quit=3`. Screenshots land in `screenshots/` (gitignored). Scenarios live in `src/debug/scenarios.gd`. Add `--headless` and drop `--shots` for fast logic-only runs.

## Architecture rules

- **Simulation vs presentation.** Gameplay state changes only in `Fighter.simulate()` and world entities' `_physics_process`, driven by `InputCommand`s. Nothing in the simulation reads `Input`. Visuals, HUD and VFX read state and never write it. This keeps the game network-ready.
- **Pure rules.** Rules that resolve hits, blocks, parries, statuses and reactions live in `src/combat/combat_rules.gd` as pure functions over `FighterState`, with unit tests in `tests/`.
- **Data.** Numbers live in `Resource` scripts (`CombatTuning`, `WeaponData`, `GauntletData`, ...) whose instances are in `data/*.tres`. Read them through the `GameData` autoload, and don't hard-code tuning in logic.
- **Events.** The simulation reports what happened through the `CombatEvents` autoload. Listeners must not mutate simulation state.
- **VFX from the simulation.** Fire-and-forget `Vfx.*` calls in simulation code (impacts, rings) are allowed: they never read or write state, and a headless server could make them no-ops.
- **Conventions.** Yaw follows Godot's convention: forward is -Z (`CombatRules.yaw_to_dir`). Physics layer 1 is world geometry and layer 2 is fighters.

## Agent skills

### Issue tracker

Issues are local markdown files under `.scratch/<feature>/`. See `docs/agents/issue-tracker.md`.

### Triage labels

Uses the five default triage labels (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `GLOSSARY.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
