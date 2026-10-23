# Character sources

All models and textures here are public domain (CC0 1.0 Universal), by Quaternius (https://quaternius.com).

| Folder | Source |
|---|---|
| `outfits/` | *Modular Character Outfits – Fantasy* (Standard, free version), glTF Godot–Unreal export: Male/Female Ranger, Male/Female Peasant |
| `ubc/` | *Universal Base Characters* (Standard, free version): the Superhero base bodies (heads are cut from these at load time, see `src/animation/head_builder.gd`) and the hairstyles rigged to the head bone |

Changes from the originals: only base-colour textures are kept (normal, ORM and roughness maps are not used by the
toon look and their references were removed from the `.gltf` files), and the textures were downscaled
(outfits 2048², skin 1024², hair 512²).
