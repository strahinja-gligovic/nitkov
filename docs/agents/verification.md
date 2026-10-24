# Verification: seeing and measuring the game

Read this before you check a change by running the game, take screenshots, write tests, run bot-vs-bot balance runs or measure performance. CLAUDE.md lists the basic commands, and every autopilot flag is listed at the top of `src/debug/autopilot.gd`. This doc covers the recipes that work and the traps. All commands run from the repo root.

## Screenshotting a moment

1. **Find the beats headless.** Run the scenario with `--log` (every hit) and `--cast_probe` (every release). Both print the autopilot clock, which is the same clock `--shots` uses, so you can read the times straight off. Done when the log shows the hit you want to see.
   ```
   godot_console --headless --path . --fixed-fps 60 -- --drive=spells --player_at=0,5 --bot_at=9 --bot_mode=0 --player_primary=firebolt --player_signature=flame_wall --log --cast_probe --quit=3.5
   ```
   Here the first Firebolt releases at 0.433 and hits at 0.63, and Flame Wall releases at 3.05 and ticks first at 3.32.
2. **Pick shot times one frame or more after each beat.** A shot shows the previous rendered frame (see below), so a shot at the exact hit time can miss the hit.
3. **Clear the folder and shoot windowed.** Done when `screenshots/` holds exactly one `shot_<time>.png` per requested time.
   ```
   rm -rf screenshots
   godot_console --path . --fixed-fps 60 -- --drive=spells --player_at=0,5 --bot_at=9 --bot_mode=0 --player_primary=firebolt --player_signature=flame_wall --shots=0.47,0.6,0.68,3.1,3.4 --quit=3.5
   ```
4. **Tile the shots into a contact sheet and look at it** with the Read tool (see Contact sheets). Done when the sheet shows the effect on the frames you expected.

## Reference

### Spawn on open ground
The player's default spawn is (0, 0, 17), facing north (-Z). The `low_wall` in `ArenaBuilder.BLOCKS` stands at z = 12: it is 1.5 m tall and 6 m wide, and spells are cast from 1.3 m. From the default spawn every projectile aimed at a bot placed with `--bot_at` hits that wall: `--drive=spells --bot_at=9` lands only Flame Wall ticks (the wall burns on the ground at the aim point, past the low wall), and `--drive=shatter --bot_at=6` lands Firebolt splash but never Shatters. Add `--player_at=0,5` to every spell run. The code applies `--player_yaw`, then `--player_at`, then `--bot_at` (relative to the moved player), whatever order you type them in.

Choose `--bot_at` for the spell you're testing. Frost Nova reaches only 5 m around the caster, so the `spells` scenario at `--bot_at=9` never shows it hitting. The `shatter` scenario walks the player forward before its Nova. Lightning Strike lands 3-18 m away. Wind Slash shoves the dummy back, so each later shot flies farther and lands later. Use `--bot_mode=0` (an idle dummy) for showcases: a duelist (`4`) interrupts the scripted signature at 2.7 s with its sword.

### Spell timing
Times are on the autopilot clock. The scripted press lands within a frame of its timeline time.
- **Release** = press time + the spell's `windup` (`data/spells/*.tres`). For example, `spells` with `--player_signature=lightning_strike` releases the signature at 2.7 + 0.4: `--cast_probe` prints 3.117.
- **Projectile hit** = release + (`--bot_at` − 0.8 hand reach − 0.4 body radius − the spell's `radius`) / `speed`. Firebolt at `--bot_at=9` releases at about 0.44 and hits at about 0.63.
- **Lightning Strike lands** at release + `delay` (0.9 s): 4.02 s in that run.
- **Scenario timelines** are in `src/debug/scenarios.gd`:
  - `spells`: primary at 0.3, 1.1, 1.9 and 4.6, signature at 2.7.
  - `shatter`: Ice Spike at 0.3, Firebolt at 1.0, which Shatters at about 1.27 s with `--bot_at=6`; then Nova at 3.9 and Firebolt at 4.7.
  - `melee`: lights at 0.3, 0.75 and 1.15, then a heavy at 2.2 (`--bot_at=2.2`).
  - `--drive=guard --bot_drive=bot_pressure --bot_at=2.2`: two blocks, a parry at 3.0 s, then a guard break at 5.5 s.

`--bot_drive=<scenario>` gives the bot a timeline, which it plays aiming at the player. `--trace` prints both fighters' action, stamina and position four times a second.

### What a screenshot shows
`Autopilot._capture` reads the viewport texture during `_process`, so a shot holds the frame rendered on the *previous* frame: 1/60 s earlier at `--fixed-fps 60`. Keep `--fixed-fps 60` on every screenshot run. It fixes each frame at 1/60 s of game time, so shot times match the simulation ticks and repeat run to run. Headless runs can't capture: they warn "no frame to capture" and save nothing, so drop `--shots` there.

`--slowmo=0.25` keeps `--shots` and `--quit` in game time and makes each frame, including each physics tick, 1/240 s of game time. That gives four times finer sampling of the simulation, effects and animation alike.

### Run recipes
Each recipe is the arguments after `godot_console --path . --fixed-fps 60 --`.
- **Spell showcase, player view:** step 3 above. The over-the-shoulder view is the one players see, so judge it first.
- **Shatter in slow motion:** `--drive=shatter --player_at=0,5 --bot_at=6 --bot_mode=0 --slowmo=0.25 --shots=1.27,1.29,1.32,1.36,1.45,1.6 --quit=1.65`. Add `--player_signature=frost_nova` (with `--quit=6`) to see the Nova land at about 4.2 s.
- **Side view of both fighters:** `--spectate=10 --spectate_angle=20 --hide_hud`. Without `--spectate_on`, the camera is placed once from the start positions and never moves, so a fighter that is shoved or walks away leaves the frame. A bare `--spectate` is 6 m.
- **Close follow cam:** `--spectate=4 --spectate_angle=30 --spectate_on=player` (or `=bot`). Add `--hide_fx` to judge the cast animation without the effects. Probing poses with `--probe` and `--cast_probe` is covered in `docs/agents/animation.md`.
- **Menu screenshots:** `--stay_in_menu --shots=1.0 --quit=1.1` shows the title screen. Add `--menu_screen=loadout` for the loadout screen (`--menu_screen=multiplayer` for the Multiplayer "coming soon" notice), and `--menu_pick=<spell or rune id>` to click a card (`src/ui/main_menu.gd`).
- **Keep runs apart:** `--out=screenshots/<name>` writes into a subfolder. Nothing clears `screenshots/` for you, and same-named shots overwrite while others linger, so `rm -rf screenshots` before each run is the convention.

### Contact sheets
`tools/screens/contact_sheet.gd` tiles PNGs into one image, so you read a single file instead of a dozen:
```
mkdir -p screenshots/sheets
godot_console --headless --path . -s tools/screens/contact_sheet.gd -- screenshots/sheets/fire.png 3 0.4 full screenshots/*.png
```
- **Arguments:** the output path, the number of columns, a scale (0.4 fits four 1600x900 columns on a screen), `full` or an `x,y,w,h` crop, then the inputs.
- **Crop:** it zooms every frame onto the same region. `640,250,480,300` at scale 1.0 frames a dummy 6 m in front of `--player_at=0,5`.
- **Paths** are OS paths, relative to the repo root.
- **The output folder must already exist**, and every input must exist. Otherwise the tool reports which and exits 1. An unmatched glob (say, a run already cleared `screenshots/`) reaches it as a literal `screenshots/*.png`, so check `ls screenshots` first.
- **Sheets go in a subfolder** like `screenshots/sheets/`, so the next `screenshots/*.png` glob doesn't pick them up.

### Unit tests
- **Layout.** GUT collects `tests/test_*.gd`. Most files extend `GutTest`. The four spell suites (`test_projectiles`, `test_lightning_strike`, `test_wind_burst`, `test_spell_casts`) extend `"res://tests/spell_world_test.gd"`, which has no `test_` prefix, so GUT doesn't run it on its own. The full suite takes about 20 s.
- **One file or one test:** `godot_console --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_wind_burst.gd -gunit_test_name=guard -gexit` (the name is a substring match).
- **Errors fail tests.** GUT's default `failure_error_types` (engine, gut, push_error) fail any test that logs an engine error or a `push_error`. The spell tests spawn every element's effects headless, so they double as a headless-safety check for VFX code. A clean run prints no `ERROR` lines.
- **The `spell_world_test.gd` pattern.** Each test gets a fresh `world` with a floor, freed afterwards. `add_fighter()` places fighters with their physics off. `release()` (or `add_projectile()`) puts spell nodes in play with their physics off and returns them. The test then advances time by hand: `drive(fighter, command(...), n)` calls `Fighter.simulate` n times at 1/60, `step(nodes, n)` calls each spell node's `_physics_process`, and `ticks(seconds)` converts seconds to ticks. Results are exact and don't depend on frame timing. The hooks record `hits`, `impacts` and `casts` from `CombatEvents`. Use `drive_physics()` (awaits real physics frames) only when a test measures distance, because `move_and_slide()` takes its delta from the engine. A movement test run outside a physics frame steps by whatever time GUT's frame took, anywhere from 8 to 144 ms, and fails at random.
- **Free coverage for new spells.** `test_every_spell_casts_end_to_end` is parameterised over `GameData.spells`. It casts each spell through a real fighter, and `test_spells_and_their_effects_clean_up_after_themselves` casts every spell in `GameData.spells` and checks that `get_tree().get_node_count()` returns to its baseline. A new spell is covered by both as soon as it's in `GameData`.
- **Probing a mechanic.** To answer "what happens when...", write a throwaway GUT file that extends `spell_world_test.gd`, builds the situation (a pillar with `add_block`, fighters, a release), steps it and `print`s positions and hits. Run it with `-gtest=`, then delete it.

### Bot-vs-bot balance runs
```
godot_console --headless --path . --fixed-fps 60 -- --autotest=180 --seed=2 --player_primary=lightning_bolt --player_signature=lightning_strike --bot_primary=wind_slash --bot_signature=wind_spear
```
- **What runs.** Both sides get a `DUELIST` brain, at `--player_skill` and `--bot_skill` (default 0.5 each). The default loadouts are Firebolt/Flame Wall/Leap for the player side and Ice Spike/Frost Nova/Blink for the bot. The `--player_*` and `--bot_*` loadout flags override them. Headless, 120 s of game takes about 9 s.
- **Seeds are deterministic.** The same flags and `--seed` print identical results. Vary the seed for more samples, and keep the seed fixed to A/B a data change.
- **The player side is favoured.** It takes 56-57 % of kills, even in mirror matchups (z ≈ 2.5 over 354 kills); the cause is unknown. Run every matchup both ways round by swapping the `player_` and `bot_` flags, and pool the results. A single-sided comparison is skewed by about 7 points.
- **Reading the summary.** `kills` is keyed by display name: `You` is the player side. `HIT:<source>` and `cast:<id>` counts give hit rates (`HIT:id / cast:id`). Periodic damage (Flame Wall ticks) and Burn are not counted, so Flame Wall shows casts but no hits. A Wind Spear's burst counts as a second `HIT:wind_spear`. Damage per cast isn't printed; add `--log` and sum the damage from its lines.
- **One run is noise.** A 120 s run yields about 5-6 kills. Compare with 16 matchups (every cross pairing on both sides, plus mirrors) × 4 seeds × 180 s.
- **Baselines on the current data** (that 128-run sweep):

  | metric | value |
  |---|---|
  | TTK under fire (`TtkTracker`) | about 9.5 s mean, 8.2-11.9 s per matchup |
  | TTK wall clock (first damage to death) | 21-29 s |
  | primaries: hit rate, damage per cast | 48-61 %, 4.1-5.7 |
  | signatures: damage per cast | 4.5 (Flame Wall) to 9.6 (Wind Spear) |
  | Lightning Strike / Frost Nova hit rate | about 28 % / 80 % |
  | element kill share, cross matchups | 46-56 % (SE about 3 %) |

  The spec's TTK target is 4-6 s; ticket 16 (`.scratch/nitkov-combat-prototype/issues/16-ttk-pacing.md`) owns that gap. About 65 % of damage is melee (`light_1` alone about 30 %), so tune melee and pacing there rather than chasing TTK with spell data.

### Measuring performance
The budget is 120 fps (8.3 ms) with two fighters casting freely. `--perf` prints frame-time stats at quit, for frames after the first second.
- **Drop `--fixed-fps` and add `--disable-vsync`.** Under `--fixed-fps 60`, every delta is exactly 1/60, so `--perf` always reports 16.67 ms. With vsync on, the delta pins to the monitor's refresh: a flat 4.17 ms on a 240 Hz screen. Run `godot_console --path . --disable-vsync -- --drive=spells --player_at=0,5 --bot_at=9 --perf --quit=4` windowed; headless renders nothing.
- **Print nothing during the run.** Each `print()` costs about 13-15 ms on the Windows console, so `--log`, `--trace`, `--cast_probe` and `--sfx_log` put false spikes on every event. If you time a function, stamp it with `Time.get_ticks_usec()`, buffer the lines, and print them at quit.
- **Repeat each run.** A window without focus can be throttled by Windows: its frames pin at about 15.6 ms (the 64 Hz timer), and the same config has measured 63 fps on one run and 453 on the next. Throw away a run whose frames sit at 15.6 ms.
- **Frame time is not work time.** Steady-state CPU work is about 0.6-0.9 ms a frame (p99 about 1.1 ms), and GPU time about 0.5-1.0 ms on an RTX 4090. The real risks are one-off stalls on first use, so look at `worst` and run long enough to cover each element's first cast. `SpellFx.prewarm` takes those stalls at load time (see `docs/agents/vfx.md`). After it, the worst remaining frame is the match's first spell hit, at 13-20 ms.

### Windows and tool gotchas
- **`python` is a Microsoft Store stub.** Run Python through uv: `uv run --no-project python -I <script>`. Piped output is cp1252, so call `sys.stdout.reconfigure(encoding="utf-8")` before printing non-ASCII (`-I` ignores `PYTHONIOENCODING`).
- **`Path.write_text` writes CRLF on Windows**, which makes git show every line as changed. Write with `open(path, "w", newline="\n")` or `write_bytes`. Check line endings with `file <path>`: Git Bash's `grep -c $'\r'` prints 0 even on a CRLF file.
- **There's no `bc`.** Do shot-time arithmetic with `awk 'BEGIN{print 3.117+0.9}'`.
- **Write multi-line code to a file through a quoted heredoc** (`<<'EOF'`). Unquoted heredocs and double-quoted `python -c "..."` strings expand `$` and run backticks, which mangles GDScript `$Node` paths and markdown without an error.
