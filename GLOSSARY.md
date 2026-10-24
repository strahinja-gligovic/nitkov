# Nitkov glossary

The vocabulary of Nitkov, a PvP arena brawler, in one alphabetical list: combat terms and the presentation and tooling words agents meet in code. Use these terms bare in code, tickets and docs. Each entry names the file that defines it. Load-bearing decisions are in `docs/adr/`.

## Language

**Action**:
The one thing a fighter is doing: idle, attack, cast, dash, flinch, stagger or dead. A new action can start only from idle and outside hit-stop. `src/combat/fighter_state.gd` (`FighterState.Action`)

**Active frames**:
The window of a swing in which the blade can hit, between wind-up and recovery. The contact key lands on its first frame. `src/combat/attack_data.gd`

**Aim assist**:
Controller-only help: look slowdown near an enemy and a slight bend of spells toward it. Melee has the magnet instead. `src/combat/combat_tuning.gd` (`assist_*`)

**Autopilot**:
The command-line verification driver. Any user argument after `--` creates it; it takes screenshots, quits, drives scenarios and spectates. Every flag is listed at the top of `src/debug/autopilot.gd`.

**Autotest**:
A headless bot-vs-bot run (`--autotest=<seconds>`, dice varied by `--seed`) that prints outcome counts, casts and TTK. `src/debug/autopilot.gd`

**Beat**:
(1) A simulation moment that a move's key pose is pinned to, such as contact on the first active frame or a spell's release. (2) One of the five stages of a spell's presentation: anticipation (the charge in the gauntlet hand through the wind-up, `SpellFx.charge`), release, travel (the flying look), impact, and aftermath (what lingers after it lands). The rules for each are in `docs/agents/vfx.md`. `src/animation/time_remap.gd`, `src/vfx/spell_fx.gd`

**Block**:
Holding guard, covering `block_arc` degrees in front. A blocked melee hit costs the attack's `block_stamina_cost`. A blocked spell costs `spell_block_stamina`, deals chip, keeps half its shove, and applies no statuses, reactions, flinch, stun or pop. `src/combat/combat_rules.gd`

**Burn**:
Fire's damage-over-time status. It refreshes rather than stacks, ticks as status damage outside hit resolution (so it never sets off Shatter), and credits kills to the last attacker. `src/combat/combat_rules.gd` (`apply_burn`, `tick_statuses`)

**Cast**:
The action that runs a spell: wind-up, release, recovery. A primary pays stamina at the start; a signature's cooldown starts at release. `src/combat/fighter.gd` (`_start_cast`, `_advance_cast`)

**Cast origin**:
The fixed point relative to the body where spells spawn (the left fist at full jab reach). It is never read from the animation. `src/combat/fighter.gd` (`cast_origin`)

**Chill**:
Frost's stacking status, capped at `chill_max_stacks`, with every stack refreshing its timer. At the cap it slows by `chill_slow`. `src/combat/combat_rules.gd` (`add_chill`)

**Chip**:
Damage that still lands through a block: `melee_block_chip` for swings, `spell_block_chip` for spells. `src/combat/combat_tuning.gd`

**Contact key**:
The fourth of a swing or cast move's six key poses (start, antic, go, contact, settle, end): the blade at the target line, or the spell leaving the hand. It lands exactly when the wind-up ends. `src/animation/anim_move.gd`
_Avoid_: strike frame, hit frame

**Dash**:
A short ground-only step in the move direction (backwards with no input), with invulnerability at its start. It can cancel late attack recovery and post-release cast recovery. `src/combat/fighter.gd` (`_try_dash`)

**Deflect**:
A Wind Spear burst turning enemy projectiles inside it away from its centre. A deflected projectile changes sides to the burst's caster. `src/spells/projectile.gd` (`deflect`)

**Duelist**:
The full AI opponent mode (`--bot_mode=4`). The other modes are dummies: idle, always block, attack loop, cast loop. `src/ai/bot_brain.gd` (`BotBrain.Mode`)

**Element**:
A spell's family: Fire burns, Frost chills and slows, Lightning interrupts and stuns, Wind shoves. Each has its own colour. `src/spells/spell_data.gd` (`SpellData.Element`)

**Exhausted**:
The timed state after an empty-stamina guard break: no regen, swing, dash, sprint, cast, block or rune. A heavy breaking a guard does not exhaust. `src/combat/fighter_state.gd` (`exhausted`)

**Fizzle**:
A projectile reaching its `max_range` without striking anything. It draws a fizzle and emits no `spell_impact`. A Wind Spear bursts instead. `src/spells/projectile.gd`

**Flinch**:
A short interrupting reaction that stops lights, casts and dashes, but not a heavy's hyperarmor. It never shortens a running stagger. After a spell flinch, further spell flinches wait out `spell_flinch_immunity`. `src/combat/fighter_state.gd` (`apply_flinch`)
_Avoid_: stun (that is a stagger)

**Gauntlet**:
The left-hand caster that holds a fighter's primary and signature spells. There is no gauntlet resource: spells are picked individually in the loadout. `src/animation/character_rig.gd`

**Guard break**:
A block that fails. A heavy on a guard (`breaks_block`) deals `heavy_guard_break_damage` of its damage. A block you can't pay for drops stamina to 0 and exhausts you. Both stagger with kind `guard_break`. `src/combat/combat_rules.gd`

**Heavy**:
The weapon's slow attack: a long wind-up with a tell, hyperarmor, and it always breaks block. `data/weapons/longsword.tres`

**Hit-stop**:
Seconds a fighter is frozen on impact: its simulation skips everything except input buffering. Melee contact (hit, block, guard break or parry) freezes both fighters; a spell freezes only the target. `src/combat/fighter_state.gd` (`hitstop`)
_Avoid_: freeze frame, hitlag

**Hyperarmor**:
A heavy's immunity to flinch through its wind-up and active frames. Staggers still land. `src/combat/fighter_state.gd` (`has_hyperarmor`)

**Impact**:
The fourth beat of a spell's presentation, where it lands. In the simulation, the moment `CombatEvents.spell_impact` fires (a fizzle doesn't fire it). `src/vfx/spell_fx.gd` (`SpellFx.impact`)

**InputCommand**:
One physics tick of one fighter's intent: move, aim yaw, aim point, and held and pressed button bits. It is the only way a controller affects the simulation. `src/core/input_command.gd`

**Key poses**:
A move's poses in clip seconds (`AnimMove.keys`). Swings and casts use six: start, antic (wind-up extreme), go (strike begins), contact, settle (follow-through stops), end. `src/animation/anim_move.gd`

**Knockback**:
The push a blade gives on contact. It eases in, unlike a shove. `src/combat/fighter.gd` (`_apply_melee_impact`)

**Light chain**:
The weapon's sequence of light attacks. A light starts the next one if pressed during an attack or within `combo_reset` after it; otherwise the chain starts over. `src/combat/weapon_data.gd`

**Loadout**:
A fighter's picks: a character, any primary, any signature and a rune, mixed across elements. `src/core/loadout.gd`

**Look**:
The presentation node of a spell (a projectile's body, the Flame Wall's fire, the strike warning), built by `SpellFx`. Its -Z faces the direction of flight. An optional `finish()` lets it fade out after the projectile ends. `src/vfx/spell_fx.gd`, `src/vfx/<element>/*_look.gd`

**Lunge profile**:
Metres a swing steps forward, sampled every 1/60 s and baked offline from the clip's footwork. It is how the simulation moves a swing without reading animation. `src/combat/attack_data.gd` (`lunge_profile`)

**Magnet**:
The soft melee assist: an enemy within `magnet_angle` and `magnet_range` steers the wind-up's turn and the lunge, which stops at `magnet_stop_distance`. `src/combat/fighter.gd` (`_find_magnet_target`)

**Move**:
How one action looks: a clip window, key poses, and timing (`AnimMove`). Gameplay data names moves by id. `src/animation/anim_move.gd`

**MoveSet**:
Every move by id, stored in `data/moves/humanoid.tres` and generated by `tools/moveset/build_moveset.py`. `src/animation/move_set.gd`

**Orb**:
A health pickup that heals `orb_heal_fraction` of max HP over `orb_heal_duration`. Any damage cancels the heal. It respawns after `orb_respawn`. `src/world/health_orb.gd`

**Parry**:
A block press opens a `parry_window`, at most once per `parry_cooldown`. A melee hit from the front inside the window does nothing to the defender and staggers the attacker (kind `parried`). Spells can't be parried. `src/combat/combat_rules.gd` (`resolve_melee`)

**Periodic**:
Repeating area damage, such as Flame Wall ticks. It gets quieter feedback. `src/spells/spell_hit.gd`

**Pop**:
Upward velocity a spell gives its target (`launch`, m/s). The highest one pending wins. A blocked spell never pops. `src/combat/combat_rules.gd` (`apply_push`)
_Avoid_: launch (in prose; it is the field name), knock-up

**Prewarm**:
Building every element's effects once, out of sight at load, so the first cast of each element doesn't stall a frame. Every new effect must be built there. `src/vfx/spell_fx.gd` (`SpellFx.prewarm`)

**Primary**:
The spell slot that costs stamina (E / LT). `src/spells/spell_data.gd` (`SpellData.Slot`)

**Reaction**:
A combo that a hit sets off, recorded in `HitResult.reaction`. Shatter is the only one. `src/combat/hit_result.gd`

**Release**:
The moment a cast's wind-up ends and the spell's effect spawns (`SpellData.release`). It is also the second beat of a spell's presentation: the flash as it leaves the hand. `src/combat/fighter.gd`, `src/vfx/spell_fx.gd`

**Rune**:
A mobility ability on its own cooldown: Leap or Blink. It is blocked by exhaustion and can cancel late recovery like a dash. `src/spells/rune_data.gd`

**Scenario**:
A named input timeline played in place of the player by `--drive=<name>`. `src/debug/scenarios.gd`, `src/debug/scripted_controller.gd`

**Shatter**:
Fire meeting frost: an unblocked Fire spell hit on a target with any Chill adds `shatter_damage`, staggers (kind `shatter`) and consumes the Chill. `src/combat/combat_rules.gd` (`resolve_spell`)

**Shock**:
The Lightning Strike's stun: a stagger of kind `shock`, shown twitching. `src/spells/lightning_strike.gd`
_Avoid_: electrocute, paralyse

**Shove**:
A horizontal push from a spell (`SpellHit.push`) that moves the target at once. A shove stronger than the running knockback replaces it instead of adding to it, and a blade's knockback cancels the shove. `src/combat/combat_rules.gd` (`apply_push`)
_Avoid_: knockback (that is melee)

**Signature**:
The spell slot with a cooldown and no stamina cost (Q / Y). `src/spells/spell_data.gd` (`SpellData.Slot`)

**Simulation / presentation**:
The simulation is gameplay state changed per physics tick from InputCommands. Presentation is everything that only reads it: visuals, animation, sound, HUD, camera. See `docs/adr/0001-network-ready-simulation.md`.

**Slow**:
A movement multiplier from spells and from max Chill. Slows don't add up: the strongest wins. `src/combat/combat_rules.gd` (`move_speed_mult`)

**Spectate**:
A side camera for automated runs (`--spectate=<metres>`, `--spectate_angle`, `--spectate_on=player|bot`), used to judge animation timing. `src/debug/autopilot.gd` (`spectate`)

**SpellHit**:
One spell effect reaching one fighter: a direct hit, splash, burst, ground tick or nova. `CombatRules.resolve_spell` consumes it. `src/spells/spell_hit.gd`

**Splash**:
A projectile's area hit around its impact: `splash_damage` and statuses, with no flinch, shove, pop or hit-stop. `src/spells/projectile_spell.gd` (`make_hit`)

**Stagger**:
A long reaction tagged with a `stagger_kind`: `parried`, `guard_break`, `shatter` or `shock`. The kind only picks the look. A stagger goes through hyperarmor and is never shortened by a later one. `src/combat/fighter_state.gd` (`apply_stagger`)
_Avoid_: stun (except for `shock`)

**Stamina**:
The single pool that pays for swings, blocks, dashes, sprint and primaries. An action can start while any stamina is left (it floors at 0). Regen waits `stamina_regen_delay` after a spend. `src/combat/fighter_state.gd` (`can_spend`, `spend_stamina`)

**Strike**:
(1) The Lightning Strike signature. (2) In a move, the go-to-contact stretch, timed by `AnimMove.strike`. Say "Lightning Strike" for the spell. `src/spells/lightning_strike_spell.gd`, `src/animation/anim_move.gd`

**TimeRemap**:
Pose-to-pose timing: it maps simulation time onto clip time so each key pose lands on its beat, and keeps the clip's own spacing between keys. `src/animation/time_remap.gd`

**TTK**:
Time to kill, measured two ways: wall clock (first damage to death) and time under fire (gaps capped at 1 s). The spec's 4-6 s target means time under fire. `src/debug/ttk_tracker.gd`

**Wind-up**:
An attack's or cast's lead-in before its active frames or release (`windup`). `src/combat/attack_data.gd`, `src/spells/spell_data.gd`

**Zone**:
A lasting area hazard in the `zones` group, with a team, `contains()` and `exit_direction()`: Flame Wall and Lightning Strike. Bots step out of zones. `src/spells/flame_wall.gd`, `src/spells/lightning_strike.gd`
