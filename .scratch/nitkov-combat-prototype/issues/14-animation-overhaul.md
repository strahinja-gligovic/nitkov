# 14 — Expressive animation overhaul

Status: in-progress
Blocked by: 13

## Why
The KayKit chibi clips read as stiff and snappy-cheap: swings don't connect on the frame that hits, feet skate,
reactions are weak, casts come from the sword hand, and the heavy's tell hides behind a big head. Target feel:
weighty, readable and expressive, in the spirit of Monster Hunter / Spellbreak / V Rising.

## What
- Characters: Quaternius Modular Outfits (Fantasy) with heads from the Universal Base Characters, on the shared
  65-bone humanoid rig; the longsword in the right fist, the gauntlet on the left hand. (CC0)
- Clips: Quaternius Universal Animation Library 1 + 2 and Mesh2Motion (CC0), merged into one library
  (`AnimLibrary`), with mirrored copies baked for left-hand casts (`AnimMirror`).
- `MoveSet` / `AnimMove` data: each move's clip window and key poses (antic, go, contact, settle).
- `AnimDirector`: pose-to-pose time remap (`TimeRemap`) so contact lands on the first active frame; phase-synced
  locomotion matched to ground speed; upper-body guard and on-the-move casts; leap phases; respawn entrance.
- Procedural layers: head look-at, breathing, spring hit reactions from the blow's direction, body yaw spring,
  lean, squash and stretch, hit-stop shake, heavy wind-up tremble.
- Effects: blade trail, slash arcs, heavy ready flash, afterimages on dashes and blinks, camera kick and FOV punch.
- Sim: lunge curves matched to the clips' steps; spells leave from the left hand; render smoothing above 60 Hz.

## Acceptance
- On every swing, the blade is at the target line on the frame the hit registers.
- No visible foot sliding while walking, sprinting, strafing or stepping into swings.
- Hits read from their direction; the heavy's wind-up is unmistakable; casts come from the gauntlet hand.
- All tests pass; bot-vs-bot autotest still lands TTK in 4–6 s.
