# 10 — Dummy modes and AI duelist

Status: ready-for-agent
Blocked by: 09

## What
- `BotBrain` producing `InputCommand`s. Dummy modes: idle, always block, attack loop, cast loop.
- Duelist: spacing, light chains, heavies against blockers, reactive block/parry/dash with a reaction delay, casts with lead and inaccuracy, signature use, rune escapes, orbs when low. Difficulty slider.
- Headless autotest: bot-vs-bot duel at fixed fps that reports hits, blocks, parries, kills and TTK.

## Acceptance
- The autotest runs without errors and produces kills with a measured TTK.
