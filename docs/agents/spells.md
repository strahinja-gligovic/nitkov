# Spells

This doc covers a spell end to end: what the simulation does (`src/spells/`, `CombatRules.resolve_spell`), the presentation contract (`SpellFx`, the element modules, `SpellSfx`), and how to add a spell or an element. Read it before you touch a spell, a zone or an element module. How effects should look is in `docs/agents/vfx.md`, cast moves in `docs/agents/animation.md`, sounds in `docs/agents/audio.md`, run recipes in `docs/agents/verification.md`, and terms in `GLOSSARY.md`.

## Add a spell (existing element)

Most new spells are a new `.tres` of an existing class. Write a new `SpellData` subclass only for a new kind of effect; then steps 3, 5, 8 and 9 also need code.

1. **Data.** Copy a sibling `.tres` of the same class to `data/spells/<id>.tres`, with `id` equal to the file name. Set `element`, `slot`, `windup`, `recovery` and `animation`. A primary needs a `stamina_cost`, a signature a `cooldown`. Without a `PickCard.TAGLINES` entry, the menu tagline is `description` up to its first `:`.
2. **Register.** Append the path to `GameData.SPELL_PATHS` (`src/core/game_data.gd`). Its order is the order of the menu cards (`GameData.spells_for` keeps load order). `tests/test_data_files.gd` pins the set at 8 spells, 4 per slot, and one primary and one signature per element, so a ninth spell fails `test_eight_spells_load_with_unique_ids`, `test_each_slot_offers_four_spells` and `test_every_element_has_a_primary_and_a_signature`. Change those on purpose. *Done when* `tests/test_data_files.gd` passes.
3. **Simulation** (new class only). Subclass `SpellData` in `src/spells/` and override `release(caster, target)`, which runs once, on the release tick. Either resolve the hits on the spot (like `NovaSpell`) or add an entity under `caster.get_parent()`, following "Spell entities" below. Run `godot_console --headless --path . --import` so the new `class_name` is visible. `tests/test_spell_casts.gd` casts every id in `GameData.spells` through a real fighter at a foe 8 m straight ahead (3 m for a `NovaSpell`): if your class can't reach 8 m, add it to `_duel`'s distance. *Done when* `godot_console --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_spell_casts.gd -gexit` passes.
4. **Cast move.** `animation` names a move in `data/moves/humanoid.tres`; its contact key lands on `windup`, the release. To add a move, follow `docs/agents/animation.md`. *Done when* `test_every_spell_plays_a_move_in_the_move_set` passes.
5. **Presentation.** Build the look in the element module (`src/vfx/<element>/`) and route it through `SpellFx`, following the contract below. A projectile goes through `SpellFx.projectile` and `SpellFx.impact`. Any other effect gets its own `SpellFx.<name>(spell, ...)`, which calls the module and then `SpellSfx`; the spell code calls only that. *Done when* the effect shows in `godot_console --path . --fixed-fps 60 -- --drive=spells --player_at=0,6 --player_primary=<id> --bot_at=9 --bot_mode=0 --shots=0.4,0.6 --quit=1` (use `--player_signature=<id>` for a signature; the press times are in the `spells` scenario in `src/debug/scenarios.gd`).
6. **Prewarm.** `SpellFx.prewarm` repeats the routing without sound. *Done when* every module function the spell's `SpellFx` routing calls is also called in `prewarm`'s loop over `GameData.spells_for(...)`.
7. **Sound.** A spell of an existing element reuses that element's sounds (see `SpellSfx` below). A moment of its own needs a `SpellSfx` function, called from its `SpellFx` function, and new sounds (`docs/agents/audio.md`). *Done when* every new name is in `SOUNDS` in `tests/test_sfx.gd` and `test_every_sound_exists` passes.
8. **Bot.** `BotBrain` (`src/ai/bot_brain.gd`) picks behaviour by class. `_plan_signature` decides when to cast a signature, for the duelist and the cast-loop dummy alike, and returns null for a class it doesn't list, so the bot never casts it. The mid-range cast in `_duel` and `_try_opportune_shot` cast `me.primary as ProjectileSpell`, so a primary of another class is never cast. `_aim_cast` aims by plan kind, `_watch_casts` reads the opponent's wind-up, and `_watch_projectiles` dodges shots in flight. A new projectile `.tres` already works; a new class needs a plan, an aim and a counter. *Done when* `godot_console --headless --path . --fixed-fps 60 -- --autotest=120 --player_signature=<id>` (or `--player_primary`) prints a `cast:<id>` count, and a `HIT:<id>` count unless all its hits are `periodic`, which the summary leaves out.
9. **HUD and menu** (`src/ui/`). Draw an icon in a new `UiIcons._design` branch (unknown ids get a plain orb). Optionally add a `PickCard.TAGLINES` entry. For a new class, add a branch to `MenuShowcase._aim_for`, where the menu preview aims each class. The cards come from `GameData.spells_for`. *Done when* `godot_console --path . --fixed-fps 60 -- --stay_in_menu --menu_screen=loadout --menu_pick=<id> --shots=2 --quit=2.5` shows the card with its own icon and the preview casting it.
10. **Feel and tests.** Set the spell's weight in `CombatFeedback.WEIGHT` (`src/world/combat_feedback.gd`); a missing id gets 0.5. New rules go in `resolve_spell`, with tests in `tests/test_spell_rules.gd` or `tests/test_spell_reactions.gd`. World tests extend `tests/spell_world_test.gd`. *Done when* the full suite (the command in CLAUDE.md) exits 0.

## Add an element

1. **Enum.** Append the element to `SpellData.Element`. Keep the existing order, because `.tres` files store the int. Give it a distinct colour in `SpellData.element_color` and add it to `ELEMENTS` in `tests/test_data_files.gd`. *Done when* `test_each_element_has_its_own_colour` passes.
2. **Spells.** Add one primary and one signature with "Add a spell". *Done when* `test_every_element_has_a_primary_and_a_signature` passes.
3. **Module.** Create `src/vfx/<element>/<element>_fx.gd` with `class_name <Element>Fx`, implementing the module contract below, with the conventions in `docs/agents/vfx.md`. *Done when* `--import` reports no errors.
4. **Routing.** Add the element to every `match spell.element` in `SpellFx` (`projectile`, `impact`, `charge`, `release`, the per-spell loop in `prewarm`) and add its `charge` and `release` calls to `prewarm`'s first loop. An unrouted element fails silently: `projectile` falls back to an empty `Node3D`, the other matches do nothing. *Done when* every function in `src/vfx/spell_fx.gd` that names `WindFx` also names the new module.
5. **Sound.** Add the element's name to `SpellSfx._element` and make its per-element sounds (see `SpellSfx` below). *Done when* they are in `SOUNDS` in `tests/test_sfx.gd` and `test_every_sound_exists` passes.
6. **Other element switches.** These fall back quietly, so give the new element a branch in each: `UiIcons.palette`, `Vfx.accent`, `CombatFeedback._element_shake` and `_on_spell_cast`, and `FighterVisual._take_hit`. *Done when* each has one.
7. **Combos.** Cross-element reactions go in `resolve_spell` (Shatter is Fire meeting Chill). The bot plays Shatter in `_plan_nova`, `_plan_wall` and `_try_opportune_shot`; teach it any new combo there. *Done when* the new rule has a test and the full suite exits 0.

## Reference

### Cast lifecycle

`Fighter._try_cast` starts a cast from IDLE when not exhausted: a primary needs stamina, a signature needs `signature_cd` at 0. `_start_cast` charges the stamina at the press, so an interrupted primary is still paid for. When `action_time` reaches `windup`, `_advance_cast` does this, in order:
1. sets `spell_released`;
2. starts the cooldown (so an interrupted signature isn't spent);
3. calls `spell.release(self, cmd.aim_target)`, the only tick the aim is read;
4. emits `CombatEvents.spell_cast`.

Recovery runs until `windup + recovery`. A dash or rune cancels the cast only after the release; before it, only a flinch, a stagger or death ends it. Casting works on the move (`cast_move_mult`) and in the air.

On the presentation side, `FighterVisual._update_gauntlet` calls `SpellFx.charge(spell, gauntlet core, windup)` when it sees a new CAST `action_serial`, and `SpellFx.cancel_charge` if that cast ends before release. `FighterVisual._on_spell_cast` calls `SpellFx.release`.

### Spell classes

| Class | `release()` spawns | Spells |
|---|---|---|
| `ProjectileSpell` | `count` × `Projectile`; `burst_radius` > 0 adds a `WindBurst` where it ends | Firebolt, Ice Spike, Lightning Bolt, Wind Slash, Wind Spear |
| `FlameWallSpell` | `FlameWall`, a zone that burns enemies inside every `tick_interval` (unblockable, `periodic`) | Flame Wall |
| `NovaSpell` | nothing: resolves on the spot against enemies in `radius` with line of sight, blockable from the front | Frost Nova |
| `LightningStrikeSpell` | `LightningStrike`, a zone that warns for `delay`, then lands an unblockable `&"shock"` stagger plus a launch | Lightning Strike |

- **Projectiles** sweep each tick: a ray against layer 1, and `CombatRules.segment_hits_capsule` against fighters, so fast bolts never tunnel. A wide one (`radius` ≥ 0.5) also needs a clear path along its edge (`Projectile._reaches`), so a Wind Slash can't clip round a pillar. A shot spent at `max_range` fizzles: no splash and no `spell_impact`. A Wind Spear bursts there instead, which does report one.
- **The burst flag.** `burst_radius > 0` means "Wind Spear" to `SpellSfx` (any element's burst plays `wind_burst`), the Wind branches of `SpellFx` and `prewarm`, `BotBrain`, `CombatFeedback` and `MenuShowcase`. Another projectile given a burst inherits all of that.
- **WindBurst** shoves and pops everyone in reach, falling off from full strength at the centre to half at the edge. It needs line of sight from just off the surface; the struck fighter skips that check and takes half the burst damage. Allies and the caster get `CombatRules.apply_push` directly (no damage, no event, i-frames ignored) when `burst_moves_allies`. Enemy projectiles inside are deflected when `burst_deflects`.
- **Deflection changes sides.** `Projectile.deflect` takes the deflector's `caster` and `team` before turning the shot, and resets `_origin`, so a deflected shot can't hit the deflector's team even when it barely turns.

### Spell entities

- Resolve every hit as `SpellHit` → `CombatRules.resolve_spell(target.state, hit, from_front, tuning)` → `Fighter.report_hit(caster, target, result, at)`. `report_hit` drops IGNORED results and accepts a null caster.
- `from_front` is `CombatRules.is_in_front(target facing, target position, source, tuning.block_arc)`, where the source is where the blow comes from: `victim.global_position - travel` for a direct hit, the impact point for splash or a burst, the caster for a nova. Zones pass `false`.
- Skip your own team and the dead.
- Start each tick with `if not is_instance_valid(caster): caster = null` (as `Projectile` and `LightningStrike._strike` do), so the spell still lands, uncredited, after its caster leaves.
- Emit `CombatEvents.spell_impact(caster, spell, at)` where it lands: a projectile ending (not fizzling), a wall placed, a nova, a strike coming down.
- Do the work in `_physics_process(delta)` with the given `delta`: world tests switch physics off and call it by hand (`spell_world_test.gd` `step`).
- Join `"zones"` (see below) or, for a `Projectile` only, `"projectiles"`, and free yourself. Tests, `HitboxViz` and the bot find spell nodes only through those groups, and `BotBrain`, `HitboxViz` and `WindBurst.blast` cast every `"projectiles"` member to `Projectile`.
- **Hand placement.** `Fighter.cast_origin()` is fixed to the body (0.8 m ahead, 0.15 m left, 1.3 m up), never read from the animation, so it stays deterministic. Hugging a wall puts it inside the wall, and a ray that starts inside a shape doesn't hit it. So `ProjectileSpell.release` casts a ray from the body to the hand; if it's blocked, the spell starts 0.05 m off the wall's face aimed into it (a Wind Spear bursts right beside you). A new spell that leaves the hand needs the same check.
- **Ground placement.** Flame Wall and Lightning Strike clamp the flat aim distance to `[min_range, max_range]`, then settle onto layer 1 with a downward ray. The strike's ray starts 20 m up, so a mark on a pillar or ledge lands on top whatever the caster's height.

### Reactions (`CombatRules.resolve_spell`)

- **Untouched.** A dead or invulnerable target (dash i-frames, Blink) gets IGNORED: nothing applies. A projectile still ends on a dodger, though, and a spear still bursts there.
- **Blocked** when `blockable`, `from_front` and `blocking` all hold. The guard pays `spell_block_stamina` and takes `spell_block_chip` of the damage, or breaks if it can't pay. A blocked hit gets half the shove and nothing else: no launch, status, Shatter, flinch, stun or hit-stop.
- **Hit**, in this order: Shatter (Fire with `triggers_reactions` on a Chilled target); chill, burn, slow; `stagger` or else `flinch`; hit-stop; the shove; damage.
- **Stagger** goes through hyperarmor and records `stagger_kind`; `&"shock"` drives the shock visuals, the HUD's SHOCKED chip and the stun reaction. **Flinch** is stopped by a heavy's hyperarmor and by the `spell_flinch_guard` window. When a flinch really starts (`action_serial` changed), the guard is set to `flinch + spell_flinch_immunity`, so one bolt interrupts a cast but a stream can't chain-lock. Neither shortens a longer stagger already running.
- **Shoves and pops.** `apply_push` keeps the stronger horizontal shove outright (shoves don't add up) and sets `shoved`, and keeps the higher pop. In `Fighter._move`, a shoved knockback above 3 m/s gets at least 200 m/s² of acceleration so it moves the fighter at once; knockback decays at 14 m/s² and `shoved` clears at zero. A melee knockback clears `shoved`, so blades keep their tuned ease-in. A leaper isn't air-steered while knockback remains, or the shove would ride on top of the leap's momentum every tick.
- **Hit-stop.** A spell's hit-stop freezes only the target (melee freezes both). `Fighter.simulate` returns early while it runs, so the shove and pop wait in state until it ends.

### Zones

A zone is any node in the `"zones"` group with this duck-typed contract:
- `team`: the caster's team, which the zone ignores.
- `contains(point: Vector3, margin := 0.0) -> bool`: whether the point is in danger *now* (`LightningStrike` answers false once it has struck).
- `exit_direction(point: Vector3) -> Vector3`: a flat unit vector, the short way out.

Consumers:
- `BotBrain._scan_zones` builds `_hazards` from enemy zones after a reaction delay; `_leave_hazards`, `_escape_ground_fire`, `_steer`, `_hazard_ahead` and `_hazard_at` use only the contract. `_escape_strikes` casts to `LightningStrike` and reads `spell.radius` and `spell.delay`; `_escape_ground_fire` skips strikes and handles every other zone.
- `HitboxViz._process` (`src/debug/hitbox_viz.gd`, F2) type-checks `FlameWall` and `LightningStrike`; give a new zone class a branch there, or it isn't drawn.
- `tests/spell_world_test.gd` collects zones in `spell_nodes` and `adopt_new`.

### Presentation contract

`SpellFx` (`src/vfx/spell_fx.gd`) is the only entry point. Every effect is cosmetic: it frees itself and never reads back into the simulation. Each element module provides:

| Function | Meaning |
|---|---|
| `charge(hand: Node3D, seconds: float, signature: bool)` | `hand` is the gauntlet core and follows the fist. Parent everything under `hand` during the call (`top_level` is fine): `FighterVisual` takes the children added during the call as the charge and frees them if the cast is interrupted. Peak at `seconds`, the release. |
| `release(world: Node, at: Vector3, direction: Vector3, signature: bool)` | `at` is the gauntlet core's position on the release tick, not `cast_origin()`. `direction` is the caster's forward. |
| `impact(world, at, normal, struck: bool, fizzled: bool, spell: ProjectileSpell)` | Where a projectile ended. `normal` points out of the wall it hit, or back along the flight for a fighter hit or a fizzle. `struck` means it ended on a fighter, even a dodger. `fizzled` means it ran out of range without a burst. |
| projectile body (`FireFx.firebolt`, `FrostFx.ice_spike`, `LightningFx.bolt`, `WindFx.slash` / `spear`) | Returns a `Node3D` whose -Z is the flight. `Projectile` makes it `top_level` and places it every frame. |
| the element's own pieces | `FireFx.flame_wall` returns a `FlameWallLook` whose `set_intensity()` the wall drives every tick; `FrostFx.nova`, `FrostFx.shatter`; `LightningFx.strike_warning`, `strike`, `shock`; `WindFx.burst` (no `normal`). |

`world` is the node effects are added under: the caster's parent for spells, `CombatFeedback` for Shatter. Effects position themselves in global space.

- **Who calls what.** Spell and zone code calls `projectile`, `impact`, `release_look`, `flame_wall`, `nova`, `strike_warning` and `strike`. `FighterVisual` calls `charge`, `cancel_charge`, `release` and `shock`. `CombatFeedback` calls `shatter`.
- **`finish()` hand-off.** `Projectile._impact` calls `SpellFx.impact`, then moves the look to `at`, then calls `SpellFx.release_look`, which stops the flight loop and, if the look has `finish()`, reparents it to `world` at the same transform and calls `finish()` (otherwise frees it). `finish()` fades the trail and frees the look; its parent is `world` by then. `LightningBoltLook.finish` reads `LightningFx.claim_impact()`, which only answers on the same physics tick as the impact.
- **Strike warning.** `LightningStrike` keeps what `SpellFx.strike_warning` returns; `_strike` `queue_free`s it and calls `SpellFx.strike` in the same tick. The deferred free leaves the warning in `LightningWarningFx.GROUP` long enough for `LightningFx.strike` to take over its cloud and leader, and freeing it cuts the warning buzz that rides on it.
- **Prewarm.** `SpellFx.prewarm(world)` builds every element's charge and release, and each registered spell's body and impact or area pieces, at y = -80 without sound, so the first cast doesn't stall on caches and shader compiles. `TrainingMode._ready` calls it. It duplicates the routing because calling `SpellFx.projectile` would start sounds, so repeat any routing change there.

### SpellSfx

`SpellFx` calls `SpellSfx` right after each visual; how sounds are made and played is in `docs/agents/audio.md`. Each element's sounds are `<element>_charge`, `_charge_sig`, `_release`, `_release_sig`, `_loop`, `_hit`, `_surface` and `_fizzle`. `SpellSfx.release` skips a `NovaSpell` (its burst is its release), which is why `frost_release_sig` doesn't exist: a Frost signature of another class needs it. Signature moments have their own names: `flame_wall_ignite`, `flame_wall_loop`, `frost_nova`, `strike_warning`, `strike_thunder`, `wind_spear_loop`, `wind_burst`, `shatter`, `shock_loop`. A missing name logs `SfxBank: no sound named '<name>'` and plays nothing.
