# 0002: Tuning lives in Resource files, read through GameData

## Context

Combat feel is found by iterating on numbers while playing: stamina costs, wind-ups, Chill caps, push speeds. Hard-coded numbers would need a code edit and a restart for every change. Separate copies of the data per fighter would let the live editor change one fighter and not the other.

## Decision

- Each kind of data is a `Resource` script (`CombatTuning`, `WeaponData`/`AttackData`, `SpellData` and its subclasses, `RuneData`, `CharacterData`, `MoveSet`), and its instances are `.tres` files under `data/`.
- The `GameData` autoload loads each file once and everything reads those shared instances (`GameData.tuning`, `GameData.spells[id]`, ...). Logic holds no tuning constants.
- The F1 tuning panel (`TuningPanel`, built by `DebugOverlay`) edits those instances live, so a change takes effect on the next tick. Its "Save to data/" button writes them back with `ResourceSaver`.

## Consequences

- `GameData` loads explicit path lists (`SPELL_PATHS`, `RUNE_PATHS`, `CHARACTER_PATHS`, ...) and does not scan folders. A new `.tres` is in the game once it is listed there, and `tests/test_data_files.gd` pins the spell counts per slot and element.
- Godot writes only the properties that differ from the script's defaults. `data/combat_tuning.tres` holds no overrides, so the live combat numbers are the defaults in `src/combat/combat_tuning.gd`, and changing a default there changes the game.
- For the same reason, a panel save of `data/weapons/longsword.tres` strips `light_1` down to its non-default lines: its `id`, `windup`, `active`, `recovery` and `arc` all equal the `AttackData` defaults. `tools/moveset/build_moveset.py` finds each swing by its `id =` line and reads those timings, so it then skips `light_1` silently. After a panel save, restore those five lines in the `light_1` block before re-baking.
- Two data files are generated, so edit their generator instead of the file: `data/moves/humanoid.tres` (all of it) and the `lunge_profile` lines in `data/weapons/longsword.tres`, both written by `tools/moveset/build_moveset.py` (see `0004-animation-as-data.md`).
- A fighter's picks are ids in a `Loadout`. The start menu hands them to the arena through the `MatchConfig` autoload, and `Fighter.apply_loadout` keeps the current pick when an id is unknown or in the wrong slot.
