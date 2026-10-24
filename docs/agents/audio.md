# Audio

How the game's sound works: the procedural synth in `tools/sfx/`, the runtime in `src/audio/` (`SfxBank`, `SfxPool`, `SpellSfx`, `CombatSfx`), and how to check a sound without hearing it. Read this before adding, changing or retuning a sound. Which `SpellFx` call triggers which spell sound is part of the spell presentation contract in `docs/agents/spells.md`.

Every file in `assets/sfx/` is generated. Change a recipe and rebuild; a hand-made `.wav` dropped in there fails the analyzer ("not in the build registry").

## Adding a sound

1. **Write the recipe** in `tools/sfx/build_sfx.py`: a function `fn(rng, v)` returning float samples, registered with `@sound("<name>", "<kind>", variants=N, loop=(seconds, crossfade), held=False)`. `kind` picks the loudness target in `TARGET` (add an entry for a new kind). Mix layers with `stack(n, (signal, gain_db), ...)`; the gains are loudness against each other, not peak. Use `rng` for every random choice and `v` (the variant index, 0-based) to vary variants, for example `jitter(v, 0.08)`. Keep `variants` at 6 or fewer (`SfxBank.MAX_VARIANTS`); a loop recipe returns at least `seconds + crossfade` of samples (`dsp.make_loop` asserts it). Done when `uv run --no-project python -I tools/sfx/build_sfx.py --list` shows the name.
2. **Build it:** `uv run --no-project python -I tools/sfx/build_sfx.py <name>`. Done when `assets/sfx/<name>.wav` exists (one variant) or `<name>_1.wav` ... `<name>_N.wav` do. If you changed a sound's variant count, delete the old files and their `.import` files yourself: the builder never deletes, and `SfxBank` prefers `<name>.wav` over `<name>_1.wav`, so a stale single file hides the new variants.
3. **Measure it:** `uv run --no-project python -I tools/sfx/analyze_sfx.py <name> --png=screenshots/sfx`. Done when it exits 0 ("0 with problems") and the sheet shows the shape you meant (see "Verifying without ears").
4. **Import it:** `godot_console --headless --path . --import`. Done when a `.wav.import` sits next to each new file. Until then the game doesn't see the file (`ResourceLoader.exists` is false and `SfxBank` warns "no sound named"); running the game doesn't import it. Commit the `.wav.import` files with the `.wav`s.
5. **Play it.** A spell sound goes in a `SpellSfx` function, called from the matching `SpellFx` function (the contract is in `docs/agents/spells.md`). A melee or movement sound goes in `CombatSfx`, from a `CombatEvents` signal or from fighter state. Pick or add a `SfxPool.Params` (below). Done when `godot_console --headless --path . --fixed-fps 60 -- --drive=<scenario> --quit=4 --sfx_log` prints `[sfx ...] <name>...wav` at the moment you expect.
6. **Test it:** add the name to `SOUNDS` in `tests/test_sfx.gd`. Done when the GUT run from CLAUDE.md passes; `-gselect=test_sfx.gd` runs just this file.

## Regenerating

```
uv run --no-project python -I tools/sfx/build_sfx.py              # all 49 sounds, 90 files, about 4 s
uv run --no-project python -I tools/sfx/build_sfx.py fire_hit     # just these names
uv run --no-project python -I tools/sfx/build_sfx.py --list       # name, kind, variants, loop
```

- **Byte-identical.** Each file is seeded from `crc32("<name>:<variant>")`, so a rebuild of unchanged recipes leaves `git status` clean. A diff in an untouched sound means something shared changed (`dsp.py`, a helper, `TARGET`).
- **Stdlib only** (`tools/sfx/dsp.py` is the DSP kit). The build fans out over processes; `--serial` runs in one process, which gives a plain traceback when a recipe throws.
- **Mastering, per file:** DC block; one-shots get fades (fade-out at least 12% of the length, unless `held`); loops are crossfaded into a seamless cycle and get a `smpl` chunk. Then gain to the kind's `TARGET` (max momentary LUFS for one-shots, integrated for loops) and a true-peak limit at -1 dBTP. Output is 44.1 kHz 16-bit mono.
- **Loops come from the `smpl` chunk.** The `.import` files keep `edit/loop_mode=0` (detect from WAV); leave it, or loops stop looping. `compress/mode=2` is QOA; switch a file to `0` (PCM) if it ever shows artefacts.

## From file to speaker

- **`SfxBank`** maps a name to `res://assets/sfx/<name>.wav`, else `<name>_1.wav` up to `MAX_VARIANTS` (6). `pick()` never returns the same variant twice in a row. Streams load on first use and are cached statically.
- **`SfxPool.of(node)`** is the pool for that node's viewport, made on first use as a child of the viewport (the arena's root viewport, or the menu showcase's SubViewport). It returns null for a node outside the tree, so every caller null-checks. It has 24 one-shot voices and 12 loop voices, made once; nothing ever adds nodes.
- **`SfxPool.Params`** (`volume_db`, `near`, `max_distance`, `pitch_jitter`, `priority`) is how one sound plays; spell kinds live in `SpellSfx._p()`, melee ones at the top of `CombatSfx`. A full pool steals the lowest-priority, then oldest, voice; if every voice outranks the new sound, the new sound is dropped (`play` returns 0).

| Priority | Used for |
|---|---|
| 1 | charge, flight loop, fizzle, swing, dash, land |
| 2 | release, hit, surface, flame wall roar, shock, flesh hit, block clang |
| 3 | `big` (nova, thunder, shatter, wind burst, wall ignite), strike warning, parry, guard break, death |

- **Distance is computed by `SfxPool`, not Godot.** Players use `ATTENUATION_DISABLED`; Godot only pans and muffles. Full level inside `near`, `DB_PER_DOUBLING` (-5 dB) beyond, faded to silence over the last fifth of `max_distance`. A one-shot beyond `max_distance` isn't started (a loop is, at silence). The listener is the viewport's camera; with no camera everything plays at its own level.
- **Buses** (`default_bus_layout.tres`, loaded by Godot from that path with no project setting): Master has a hard limiter (ceiling -0.5 dB), SFX a gentle compressor (-8 dB threshold, 2.5:1) and sends to Master. Every voice uses SFX, falling back to Master if the bus is missing.
- **`CombatSfx`** is a node `TrainingMode._ready` adds to the arena, so the menu gets spell sounds but no melee sounds. Hits, deaths and landings come from `CombatEvents`. Swings and dashes have no event: it watches each fighter's `action_serial`, and drops a pending swing whoosh if the attack was interrupted. Spell hits (`result.element != NONE`) are left to `SpellSfx`; a spell stopped by a guard still clangs.
- **The menu showcase** sets `audio_listener_enable_3d = true` on its SubViewport (`src/ui/menu_showcase.gd`); without it the showcase's casts are silent.

## Timing invariants

These numbers are written twice, once in a recipe and once in the runtime. Change both.

| Runtime | Recipe | Why |
|---|---|---|
| `SpellSfx.CHARGE_TAIL` = 0.08 | `tail = 0.08` in each `_<element>_charge` | `charge` starts the riser at `length - CHARGE_TAIL - windup` so its peak lands on the release. |
| Spell `windup` in `data/spells/*.tres` (primaries 0.14 to 0.16, signatures 0.3 to 0.45) | `build` passed to `_<element>_charge`: 0.24 for `<element>_charge`, 0.45 to 0.55 for `<element>_charge_sig` | A riser is shared by element and slot. A windup longer than its build starts the riser at 0 and it peaks early. |
| `SpellSfx.WARNING_BUILT_FOR` = 0.9, `delay = 0.9` in `data/spells/lightning_strike.tres` | `strike_warning` `build = 0.9`, then 0.35 s held top (`held=True`) | The countdown tops out on the bolt; the held top covers a late bolt, and the warning node's removal cuts it. |
| `CombatSfx.SWING_PEAK` 0.075, `HEAVY_SWING_PEAK` 0.13 | `swing_env(n, 0.075, ...)` / `swing_env(n, 0.13, ...)` | The whoosh starts early by its peak time, so it peaks on the first active frame. Heavy means `attack.hyperarmor`. |

## Voices attached to targets

- **Following.** `play(..., follow, offset)` and `loop(target, ...)` track a node by instance id each frame. Loops always stop with their target (0.15 s fade when it's freed). One-shots stop with it only when `stop_with_target` is set (0.04 s fade).
- **Explicit stops:** `stop_target(id, fade)` fades every voice on that node: `projectile_end` (0.09 s), `cancel_charge` (0.06 s). `stop_after(handle, s, fade)` schedules one: the flame wall roar dies with the flames (`duration - 0.45`, 0.4 s fade), the shock loop ends with the stun. `extend(handle, s)` pushes a stop later; `SpellSfx.shock` keeps the handle per body in `_shocks`, so a re-applied stun extends the loop instead of stacking a second one.
- **The charge riser needs an explicit cancel.** It follows the gauntlet core, which is never freed, so freeing alone won't stop it. `FighterVisual._update_gauntlet` calls `SpellFx.cancel_charge` when the cast is interrupted before release; any new sound on a long-lived node needs the same.
- **Looks arrive before they're in the tree.** Projectile looks and the flame wall's look are handed to `SpellSfx` before `add_child`, so `projectile`, `flame_wall` (and `strike_warning`, whose node is already in the tree) go through `_when_in_tree`, which defers the start to the end of the frame the node enters. The deferred lambda checks `is_instance_id_valid` first, because a projectile can end before it runs. Without that guard the engine logs "Lambda capture at index 0 was freed", and in tests the error lands between tests, where GUT doesn't count it.
- **Shapes.** Every loop starts at a random point of its cycle, so repeats never line up. Flight loops bend pitch on fly-by (`doppler`, stylised `SOUND_SPEED` 240). The flame wall roar is a line source: `line_half` = `spell.length * 0.5` along the look's local X, so it sounds from the point of the wall nearest the listener.
- **Game time.** Ages, fades and scheduled stops advance with `_process` delta, so under `--slowmo` they stay on gameplay while the audio itself plays at normal speed.

## Headless runs are silent

`SfxPool._silent` is true when the display server is `headless` (`--headless`, GUT, `--autotest`). Then voices are claimed, followed, faded, stolen and released as usual, but `player.play()` is never called. A one-shot holds its voice for its stream length. The tests rely on this, and it avoids "leaked instance / resources still in use" errors at quit from playbacks that outlive the dummy driver. When a pool leaves the tree it releases its voices and clears the `SfxBank` and `SpellSfx` static caches.

## Verifying without ears

- **`tools/sfx/analyze_sfx.py`** measures every file (or the names given, matched by prefix) and exits 1 on any problem: peak above -1 dBFS, true peak above -0.8 dBTP, DC above 0.002, an isolated click (one big sample step among small ones; crackle grains pass), a one-shot not starting and ending at zero, a cut tail (louder than -35 dB, unless `held`), a loop seam that jumps or steps more than 3 dB. The table also gives LUFS, spectral centroid, attack, and octave bands from 63 Hz to 16 kHz relative to the loudest. The footer compares each kind with its `TARGET`; expect within about 0.5 dB.
- `--selftest` checks the click detector itself (it must catch a step and a hard start and pass grains). Run it after touching `clicks()`.
- `--png=<dir>` writes one sheet per name prefix (`fire.png`, `sword.png`, ...): waveform with the 10 ms RMS line and 100 ms ticks, over a log-frequency spectrogram (dotted guides at 100 Hz, 1 kHz, 10 kHz) with the centroid line. `--cols=N` sets the columns, `--same` puts a sheet on one time scale. Read the PNG to judge shape: a fire release should sweep down, a riser should brighten into its end, a loop should look even across the seam. Write sheets under `screenshots/` (gitignored), not `assets/`.
- **At runtime,** `--sfx_log` (read by `sfx_pool.gd`, not listed in `autopilot.gd`) prints each sound started, its distance, its start offset (`from`) and busy voices, plus a node count every 60 frames. The stamp is wall-clock time, not game time. A charge's `from` should equal its built length minus the windup, for example 0.10 for Firebolt.

## Nobody has listened

The sounds were tuned by measurement, spectrograms and logs only; no one has heard them. Balance between elements, and against any future music, wants a listening pass. The volume levers, cheapest first:

1. The `Params` per kind (`volume_db`, `near`, `max_distance`). No rebuild needed.
2. The SFX bus `volume_db` in `default_bus_layout.tres`, for everything at once.
3. `TARGET` in `build_sfx.py` (a whole kind's loudness) or the layer gains inside a recipe (its character). Rebuild and reimport.
4. The distance curve in `SfxPool`: `DB_PER_DOUBLING` and `_distance_db()`. `max_db` (6) in `_make_voice` caps any boost.
