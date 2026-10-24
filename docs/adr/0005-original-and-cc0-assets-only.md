# 0005: Original assets only: CC0 models and clips, everything else generated

## Context

Nitkov is an original game. Any asset whose license is unclear would be a liability later, and the art direction (cel-shaded, comic, element-specific) is better served by effects built for it than by stock packs. Agents also build and change assets with no art tools and no downloads.

## Decision

- Third-party content is CC0 only, and each source folder carries its license and provenance: `assets/animations/LICENSE.md` (Quaternius UAL 1 and 2, Mesh2Motion), `assets/characters/LICENSE.md` (Quaternius outfits and base bodies) and `assets/kaykit/LICENSE.txt` (KayKit, used only for `assets/kaykit/weapons/sword_1handed.gltf`).
- Effects are built in code: meshes, `.gdshader` shaders, GPU particles, and noise or generated textures. `src/` contains no image files.
- Sounds are synthesized by `tools/sfx/build_sfx.py` (Python standard library only, seeded) into `assets/sfx/`. UI icons are drawn with `CanvasItem` calls (`UiIcons`, `src/ui/ui_icons.gd`).

## Consequences

- A new model or clip is CC0 and gets a row in its folder's license file, saying what was changed from the original (as the characters' file does for the stripped texture maps).
- A new effect is code plus shaders under `src/vfx/<element>/`. It carries a CPU cost and a first-use compile cost, which `SpellFx.prewarm` pays at load (see `0003-spell-presentation-through-spellfx.md`).
- A sound changes by editing its recipe and regenerating; the workflow is in `docs/agents/audio.md`.
- The spec's presentation section still names the KayKit Knight and Barbarian. Ticket 14 replaced them with the Quaternius characters.
