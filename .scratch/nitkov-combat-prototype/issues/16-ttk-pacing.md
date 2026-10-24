# 16 — Bring time-to-kill back to 4–6s

Status: needs-triage
Blocked by: 15

## Why
Bot-vs-bot autotests measure about 9.5s of time under fire per kill (21–29s wall clock), against the spec's 4–6s.
It was already 10.3s at the end of ticket 14, so the spell overhaul didn't cause it. About 65% of damage is melee
(light_1 alone is about 30%), so spell numbers alone can't fix it.

## What
- Measure where the time goes: blocked and parried hits, whiffs, bot spacing, orb heals, stamina starvation.
- Tune `combat_tuning.tres`, the longsword's damage and the duelist's aggression to land 4–6s, without making any
  one element dominate (check with `--autotest=180 --seed=n` across element matchups).

## Acceptance
- Autotest TTK under fire averages 4–6s across element matchups, on 2+ seeds.
