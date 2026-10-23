# Animation sources

All clips here are public domain (CC0 1.0 Universal).

| File | Source | License |
|---|---|---|
| `UAL1_Standard.glb` | Quaternius, *Universal Animation Library* (Standard, Unreal-Godot export) — https://quaternius.itch.io/universal-animation-library | CC0 1.0 |
| `UAL2_Standard.glb` | Quaternius, *Universal Animation Library 2* (Standard, Unreal-Godot export) — https://quaternius.itch.io/universal-animation-library-2 | CC0 1.0 |
| `m2m_addon.glb` | Mesh2Motion, `human-addon-animations.glb` — https://github.com/Mesh2Motion/mesh2motion-app | CC0 1.0 |

The game merges and converts them at load time (`src/animation/anim_library.gd`): every clip is
re-expressed for each character's rest pose, Mesh2Motion's `head` bone is renamed to `Head`, and
some clips are mirrored or spliced. Which clip plays for which move is in `data/moves/humanoid.tres`.
