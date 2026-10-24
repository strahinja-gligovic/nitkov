# 15 — Spell overhaul: Lightning, Wind, a single Ice Spike, and spells that hit hard

Status: done
Blocked by: 14

## Why
Player feedback after ticket 14: three ice shards per cast are overpowered, and the spells look and feel weak
next to the new melee. They asked for two new elements, Lightning (a horizontal bolt and a strike from the sky
after a delay) and Wind (a parabola-shaped slash and a big spear that bursts and pushes everything), and for
every spell to look good, animate well and land with impact.

## What
- **Ice Spike** replaces Shard Volley: one spike, 10 damage, +1 Chill (three hits to max Chill). It still sets
  up Shatter.
- **Lightning**:
  - Lightning Bolt (primary): a near-instant bolt that flinches, interrupting attacks and casts but not heavies.
  - Lightning Strike (signature): marks the ground, and 0.9s later a bolt from the sky deals 24 damage, an
    unblockable 1s "shock" stun and a pop up.
- **Wind**:
  - Wind Slash (primary): a wide crescent with a shove.
  - Wind Spear (signature): a spear that bursts where it lands, blowing everyone within 4m away and off their
    feet (enemies take damage; the caster and allies are only pushed), and knocking enemy spells off course.
- **Sim rules**: spell hits can flinch, stun (`stagger` + kind), shove (`push`) and pop up (`launch`). Spells
  stack the bigger shove, take the higher launch, and a blocked spell keeps half the shove. A new
  `CombatEvents.spell_impact` reports every landed spell.
- **Presentation**: all spell visuals and sounds go through `SpellFx`, which routes to one module per element
  (`src/vfx/<element>/`) and to `SpellSfx` (`src/audio/`).
  - Every spell gets anticipation, release, travel, impact and aftermath beats.
  - New cast animations for every spell, and a shock stagger.
  - Element-specific camera, screen and body reactions.
  - Procedural sound effects (the game had no audio).
- **UI**: per-spell icons, a four-element loadout menu, element-colored damage numbers with reaction callouts.
- **AI**: the duelist uses and counters every spell: leads the strike, escapes strike circles, and blasts with
  the spear.

## Acceptance
- Each element reads at a glance from 20m by shape and motion, not just color.
- The strike's warning gives a fair chance to step out.
- Wind visibly blows fighters around.
- Every spell has a distinct cast animation whose release matches the spell leaving the hand.
- All tests pass, including new tests for push, launch, flinch, stun, the strike and the burst.
- Bot-vs-bot autotests across element matchups use every spell, with no element dominating (kill shares 46–56%).
  TTK did not reach 4–6s: about 9.5s under fire, but it was already 10.3s before this ticket and is mostly
  melee pacing. Ticket 16 takes it on.
- 120 fps with two fighters casting freely.
