# 13 — Start menu: loadout and opponent setup

Status: done
Blocked by: 12

## What
- Title screen, then a loadout screen: pick a character, a primary spell, a signature spell (any element, mix and match) and a rune.
- Opponent setup: character, behaviour (dummy modes or duelist), difficulty, spells, Randomize.
- A live 3D showcase of both fighters that previews picks (casts the picked spell).
- Picks reach the arena through the `MatchConfig` autoload; the in-match loadout menu offers the same rows.

## Acceptance
- Booting the game lands in the menu; FIGHT! starts the match with exactly the picked loadouts.
- Any `--` autopilot arguments skip the menu (`--stay_in_menu` keeps it for screenshots).
