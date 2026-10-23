# Nitkov

An original PvP arena brawler prototype in **Godot 4.7 / GDScript**: elemental gauntlet spells with combos, block/parry melee, and one shared stamina pool. The design and milestone-1 scope are in `.scratch/nitkov-combat-prototype/spec.md`; tickets are in its `issues/` folder.

## Commands

The Godot console binary is installed through winget: `godot_console` (`%LOCALAPPDATA%\Microsoft\WinGet\Links\godot_console.exe`).

- **Import / refresh the class cache:** `godot_console --headless --path . --import`. Run this after adding a new `class_name` script, or other scripts won't see it.
- **Play:** `godot_console --path .`, or open the project in the editor and press F5. This boots into the start menu (`src/ui/main_menu.tscn`), which hands your picks to the arena through the `MatchConfig` autoload. Running `src/world/arena.tscn` directly uses MatchConfig's defaults.
- **Unit tests (GUT):** `godot_console --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit`
- **Automated run with screenshots:** `godot_console --path . --fixed-fps 60 -- --drive=<scenario> --shots=1.0,2.5 --quit=3`. Screenshots land in `screenshots/` (gitignored). Scenarios live in `src/debug/scenarios.gd`, and every flag is listed at the top of `src/debug/autopilot.gd`. Add `--headless` and drop `--shots` for fast logic-only runs. Any `--` arguments make the start menu skip straight to the arena; add `--stay_in_menu` (plus `--menu_screen=loadout`) to screenshot the menu instead.
- **Bot vs bot:** `godot_console --headless --path . --fixed-fps 60 -- --autotest=120` prints outcome counts and TTK.
- **Animation checks:** add `--spectate=4 --spectate_angle=30 --spectate_on=player` to an automated run for a side camera that follows a fighter.
- **Regenerate the move set:** `uv run --no-project python -I tools/moveset/build_moveset.py` rewrites `data/moves/humanoid.tres` and re-bakes each swing's `lunge_profile` in `data/weapons/longsword.tres`. Run it after changing a swing's windup/active/recovery.

## Architecture rules

- **Simulation vs presentation.** Gameplay state changes only in `Fighter.simulate()` and world entities' `_physics_process`, driven by `InputCommand`s. Nothing in the simulation reads `Input`. Visuals, HUD and VFX read state and never write it. This keeps the game network-ready.
- **Pure rules.** Rules that resolve hits, blocks, parries, statuses and reactions live in `src/combat/combat_rules.gd` as pure functions over `FighterState`, with unit tests in `tests/`.
- **Data.** Numbers live in `Resource` scripts (`CombatTuning`, `WeaponData`, `SpellData`, `RuneData`, `CharacterData`, ...) whose instances are in `data/*.tres`. Read them through the `GameData` autoload, and don't hard-code tuning in logic. A fighter's picks are a `Loadout` (character, any primary, any signature, rune); spells mix and match across elements.
- **Events.** The simulation reports what happened through the `CombatEvents` autoload. Listeners must not mutate simulation state.
- **Animation is presentation.** `FighterVisual` builds a `CharacterRig` (Quaternius outfit, a head cut from the matching base body by `HeadBuilder`, hair, the longsword, the gauntlet anchor) and drives it through an `AnimDirector`. Moves are data: `data/moves/humanoid.tres` is a `MoveSet` of `AnimMove`s (clip, key poses, timing), and `AttackData.animation` / `SpellData.animation` name moves in it. Clips come from `assets/animations/` and are converted per skeleton at load by `AnimLibrary` (rest-pose retarget, renames, mirrored and spliced copies). `TimeRemap` maps simulation time onto clip time so each key pose lands on its simulation beat (contact on the first active frame). The simulation never reads animation: swing lunges come from `AttackData.lunge_profile`, baked offline from the clips' footwork.
- **VFX from the simulation.** Fire-and-forget `Vfx.*` calls in simulation code (impacts, rings) are allowed: they never read or write state, and a headless server could make them no-ops.
- **Spell presentation.** Every spell's visuals and sounds go through `SpellFx` (`src/vfx/spell_fx.gd`). It routes to one module per element (`src/vfx/<element>/`: `FireFx`, `FrostFx`, `LightningFx`, `WindFx`) and to `SpellSfx` (`src/audio/`). Spell and zone code calls `SpellFx` only and never builds visuals itself.
- **Conventions.** Yaw follows Godot's convention: forward is -Z (`CombatRules.yaw_to_dir`). Physics layer 1 is world geometry and layer 2 is fighters.

## Agent skills

### Issue tracker

Issues are local markdown files under `.scratch/<feature>/`. See `docs/agents/issue-tracker.md`.

### Triage labels

Uses the five default triage labels (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `GLOSSARY.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
