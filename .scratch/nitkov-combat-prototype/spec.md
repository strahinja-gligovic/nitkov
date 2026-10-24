# Spec: Nitkov combat-feel prototype (milestone 1)

Status: done

## Goal

Nitkov is an original PvP team-deathmatch arena game: elemental gauntlet spells with combos, readable block/parry melee, and committed, stamina-driven combat. Tone: stylized dark fantasy, cel-shaded with ink outlines, gritty but colorful and cheerful.

Milestone 1 is **single-player combat feel only**: one player against a dummy or an AI duelist in a small greybox arena, structured so online play can be added later without a rewrite.

## Design rules

### Camera and input
- Over-the-shoulder, always free aim, no lock-on. The fighter turns to face the aim direction (strafe locomotion), so "block what you look at". The body turns toward the world point under the crosshair rather than parallel to the camera, which cancels the shoulder offset's parallax at sword range.
- Mouse and keyboard and controller from day one.

| Action | Keyboard / mouse | Controller |
|---|---|---|
| Move / look | WASD / mouse | Left stick / right stick |
| Light attack | Left mouse | RB |
| Heavy attack | F or mouse thumb button | RT |
| Block (hold) / parry (tap) | Right mouse | LB |
| Dash-step | Space | A |
| Sprint | Shift (hold) | L3 (click, stays on while moving) |
| Primary spell | E | LT |
| Signature spell | Q | Y |
| Mobility rune | R | B |
| Loadout menu | Tab | Start |
| Quick-swap gauntlet (debug) | T | D-pad right |
| Debug: tuning panel / hitboxes / slow-mo / combat log | F1 / F2 / F3 / F4 | Back / D-pad up / D-pad down / D-pad left |
| Controls help | H | |

### Loadout
Everyone is a hybrid: one melee weapon (milestone 1: **longsword**), one elemental gauntlet, and one mobility rune (**Leap** or **Blink**). The gauntlet holds a primary and a signature from any of the four elements (**Fire**, **Frost**, **Lightning**, **Wind**; ticket 15), mixed and matched.

### Stamina (one shared pool)
- 100 max. Regenerates 35/s after a 0.6s delay since the last spend, at half speed while blocking. Sprinting drains 10/s.
- An action can start whenever stamina > 0 (it drains to a floor of 0).
- **Exhausted** (1.5s, triggered by an empty-stamina guard break): no regen, and no dash, sprint, cast, block or rune.

### Melee (light and heavy only)
- **Light**: 3-hit chain, 8/8/10 damage, 10 stamina each (12 in the original plan; lowered after measuring so a full bar covers most of a kill), ~0.4s per hit including hit-stop. The next light can cancel the previous one's recovery. Light hits flinch for 0.25s.
- **Heavy**: fixed 0.7s wind-up with a glowing tell, 22 damage, 25 stamina. Hyperarmor during wind-up and active frames: lights don't interrupt it. **Always breaks block.** Not chargeable.
- Swings go toward the camera's forward direction, with a soft magnet: an enemy within ~30° and ~4.5m gets rotation and lunge assist during the wind-up.
- Attack recovery can be cancelled into dash or rune late in recovery.

### Block and parry
- Hold block: covers the front 180°, and you move at 50% speed.
- A blocked light costs 10 stamina and 0 chip damage. A blocked spell costs 8 stamina, deals 40% chip damage and applies **no statuses or reactions**.
- If a blocked hit costs more stamina than you have, the guard breaks: stagger for 0.8s, plus exhausted.
- A blocked heavy always breaks the guard: 0.8s stagger and 50% of the heavy's damage (default, tunable).
- **Parry**: block pressed within 150ms before a melee hit lands, from the front. The attacker is staggered for 1.0s after a light or 1.5s after a heavy, and the defender takes nothing. A new parry window can open only 0.6s after the previous press; holding block still blocks.
- Fire on the ground (Flame Wall), burn damage over time and the Lightning Strike (it comes from above) can't be blocked.

### Stagger (flinch rules, no poise bar)
- Light hits flinch for 0.25s and heavy hits for 0.4s. A flinch interrupts lights, casts and dashes, but not heavies.
- Parry, guard break and Shatter cause a long stagger.
- Spells don't flinch, except Lightning: the Lightning Bolt flinches (not through hyperarmor) and the Lightning Strike stuns ("shock" stagger). Attacker and victim freeze briefly on melee contact (hit-stop).

### Dash-step
4m over 0.25s, 0.15s of invulnerability from the start, 20 stamina. It goes in the move direction, or backwards with no input. Ground only.

### Gauntlets and spells
Each gauntlet has a **primary** (costs stamina) and a **signature** (15s cooldown, no stamina cost). You can cast while walking (at 60% speed) and while airborne.

| Gauntlet | Primary | Signature |
|---|---|---|
| Fire | **Firebolt**: projectile, 12 damage plus Burn (3/s for 3s); 1.5m splash dealing 4 damage plus Burn; 15 stamina | **Flame Wall**: 8 × 2m strip of burning ground across the aim point, 4s, 8 damage per second to anyone standing in it |
| Frost | **Ice Spike** (was Shard Volley, ticket 15): one spike, 10 damage and +1 Chill; 15 stamina | **Frost Nova**: 5m blast around the caster, 10 damage, +3 Chill, 40% slow for 2s |
| Lightning | **Lightning Bolt**: near-instant bolt (80 m/s), 9 damage and a 0.25s flinch; 15 stamina | **Lightning Strike**: marks a 3m circle at the aim point (3–18m); 0.9s later a bolt from the sky deals 24 damage, a 1s stun and a pop up. Unblockable |
| Wind | **Wind Slash**: a wide crescent (1m hit radius, fades at 25m), 8 damage and a shove; 15 stamina | **Wind Spear**: 14 damage to whoever it hits; it bursts where it lands, blowing everyone within 4m away and off their feet (8 damage to enemies, caster and allies only pushed) and knocking enemy spells off course. 14s cooldown |

- **Chill** stacks to 3 and expires 4s after the last stack. At 3 stacks you're slowed 30%. Slows don't add up; the strongest one wins.
- **Shatter** (status-based combo, any source): a Fire hit on a Chilled target (Firebolt direct or splash, or a Flame Wall tick) deals 25 bonus damage and a 1.2s stagger, and consumes the Chill. Burn ticks don't trigger it.

### Mobility runes
- **Leap**: big vertical jump (~3.8m) carrying the momentum you're moving with, then a slow fall. 12s cooldown. Ground only.
- **Blink**: ~8m instant teleport in the move direction (or forward with no input), stopped by walls, 0.1s invulnerability. 10s cooldown.

### Health, death and respawn
- 100 HP. Medium time to kill: ~4–6s of sustained hits.
- Health orbs at fixed spots heal 50% over 1s; damage interrupts the heal. Orbs respawn 30s after pickup.
- Death leads to a 3s respawn at the team's spawn point, with health, stamina, statuses and cooldowns reset.

### Opponent
- **Dummy modes**: idle, always block, attack loop (light chains and heavies, for parry practice), cast loop.
- **AI duelist**: it approaches, attacks, blocks, parries, dashes, casts, uses its rune and grabs orbs when low. It reads the player through a reaction delay, and a difficulty slider (0–1) scales reaction time, parry, block and dodge odds, and aim.

### Arena
A ~40×40m greybox: pillars, one raised ledge with a ramp, 2 health orbs, and spawn points on opposite sides.

### Presentation
- Toon shader with banded light and hatched shadow edges, plus screen-space ink outlines and a bold palette.
- KayKit Knight (player) and Barbarian (bot), both CC0, with 76 shared animations. The animations are time-warped so their strike frame lands on each attack's logical active frame.
- **HUD**: health and stamina bars, primary/signature/rune slots with cooldowns, crosshair, hit-marker, enemy health bar, damage numbers, status icons.
- **Debug**: live tuning panel (with a save-to-data-files button), hitbox, block-arc and parry-window visualisation, slow-mo, and a combat log that measures TTK.

## Architecture (network-ready, no networking yet)
- Each physics tick, an `InputCommand` (move, aim yaw, aim target point, held and pressed button bits) comes from `PlayerInput` **or** `BotBrain`. Both feed the same `Fighter` simulation, and these commands are what will cross the network later.
- All gameplay runs in `_physics_process` (60 Hz). The simulation never reads `Input` directly.
- Combat state lives in plain data (`FighterState`). Animations only *display* it.
- The rules live in a pure, node-free `CombatRules` and are unit tested headless with GUT.
- Tuning lives in `Resource` files under `data/`.

## Done when
These can be done on both keyboard/mouse and controller:
- Kill the AI duelist using melee only, spells only, and mixed.
- Parry a heavy and punish it.
- Get guard-broken from empty stamina.
- Trigger Shatter by chilling the bot with Frost, then quick-swapping (T) to Fire and hitting it.
- Leap onto the ledge, Blink away from a heavy, and grab a health orb.
- TTK in the combat log reads ~4–6s.

## Out of scope
Networking, teams larger than 1v1, TDM scoring, more weapons, Lightning and Wind status combos, Steam combos, gliding, music, and final art.
