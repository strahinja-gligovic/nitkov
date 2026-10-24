# VFX: how effects look and how they are built

Read this before you add or change a visual effect: a spell's charge, release, travel, impact or aftermath, a status look on a body, or the impact-feel layer (camera, screen, accents). The `SpellFx` contract and the steps for adding a whole spell are in `docs/agents/spells.md`. The commands for looking at the game are in `docs/agents/verification.md`.

## Adding an effect

1. **Put it in its element's folder.** Use `src/vfx/<element>/` and prefix the class with the element (`FireMuzzle`, `LightningFlare`, `WindRibbon`). Only the element module (`FireFx`, `FrostFx`, `LightningFx`, `WindFx`) calls it, and gameplay code reaches the module only through `SpellFx`. Done when `grep -rn YourClass src | grep -v '^src/vfx/'` prints nothing.
2. **Import.** A new `class_name` needs `godot_console --headless --path . --import` before other scripts, tests and runs can see it. Done when the import prints no parse errors.
3. **Build shared resources once.** Shaders, materials, static meshes, particle recipes and generated textures go in static caches (the folder's kit, or the module's `_build_shared`). Per-spawn variation goes through `instance uniform`s, MultiMesh custom data or a node's scale. Done when a second spawn creates no new `Shader`, `ShaderMaterial` or `Image`; only per-instance geometry (a trail's `ImmediateMesh`, an arc's `ArrayMesh`, a burst's `MultiMesh`) is new.
4. **Give it one root that frees itself.** Particles, lights and parts are children of that root, and the root frees itself on a fixed clock (a tween, `FireKit.free_after`, or an age check in `_process`). Done when a headless run's node count returns to its baseline after the effect ends (see "Check your effect").
5. **Guard the entry point** (see "Headless and out of the tree"). Done when the GUT suite and a headless run print no `ERROR` lines.
6. **Prewarm it** (see "Prewarm"). Done when `SpellFx.prewarm` reaches the code path that fills your cache.
7. **Look at it.** Work through "Check your effect" below, and fix the weakest beat before you stop.

## Art direction

Build every effect procedurally and originally: `ArrayMesh` or primitive meshes, `.gdshader` files, `GPUParticles3D` or CPU-simulated `MultiMeshInstance3D`, `FastNoiseLite`, gradients, `Decal`, and images painted in GDScript. Effects use no imported or downloaded assets.

**Style.** Cel-shaded and comic: crisp shapes, hard-stepped color bands (white-hot core, then the element's saturated bands, then an ink rim), and dark ink accents where they help (smoke with dark edges). Effects are snappy in and linger on the way out. Stylized, not realistic.

**The five beats.** Every spell has all five, and a new effect must fit the beat it belongs to:

| Beat | Rule |
|---|---|
| Anticipation | The charge sits in the fist and lasts exactly the cast's windup (`seconds`). It grows toward the release. |
| Release | A bright muzzle flash of 2–4 frames, plus a burst of particles. Rings and gusts either snap out within about 0.1 s or travel down the throw (`WindOneShot.add_moving`). A ring that hangs around the fist reads as a reticle and hides the shot. |
| Travel | The body is alive: flicker, spin, a pulsing core, secondary motion, and a trail laid in world space that lingers after the head has passed. |
| Impact | A white-hot flash of 1–2 frames, then shapes expanding with ease-out, debris flying, and a light flash that dies within about 0.15 s. Hits on a fighter, on a wall or the floor, and fizzles at max range each get their own version; a fizzle is a small, dim sputter. |
| Aftermath | Smoke, mist or sparks linger 0.3–1.0 s, and a ground or wall mark fades over 2–4 s where it fits. |

**Element identities.** Each element must read at a glance from 20 m by shape and motion, not only by color.
- **Fire** is heat and chaos: roiling toon fireballs, flame tongues, embers, dark-edged smoke, scorch.
- **Frost** is crystalline: faceted crystals, glitter, cold mist, shattering, frost patches.
- **Lightning** is jagged and violent: branching arcs that re-randomize every couple of frames, strobes, white-hot cores, Lichtenberg scorch.
- **Wind** is flowing and translucent: streak lines, spirals, crescents, refraction, dust, and visible displacement.

## Readability

- **Uncover an enemy's body and attack tells within about 0.15 s.** A Firebolt exploding on a body burns open by 0.25 s (`FireExplosion`), so the target shows through within about 0.15 s. The Ice Spike's crystal star off a struck body starts crumbling at 0.14 s. Fire's smoke from a body hit spawns 1.2 m above the hit point, over the head.
- **Bloom starts at 1.1** (`glow_hdr_threshold` in `ArenaBuilder`'s environment). Only the white-hot core and the hottest band go past it, and big flashes stay brief. An accent that blows out turns into a white speck at range, so `Vfx.ACCENT_ENERGY` (1.35) keeps element accents under it.
- **Keep effects out of the camera's face.** Wind's shaders fade out near the camera (the `near_fade_from` / `near_fade_to` uniforms). Frost Nova shrinks spikes within 2.2 m of the camera. Lightning's flashes stay short and the screen flash is capped (`ScreenFx.MAX_FLASH` = 0.42). Copy one of these approaches for anything big that can spawn on or next to the player.
- **See-through is allowed.** The Flame Wall's red and orange bands are 50% opaque (`opacity` in `fire_tongue.gdshader`), so a fighter behind it still reads. Keep dust and smoke small or thin, because big opaque puffs read as rocks.
- **Lights tint the floor.** Keep `omni_range` tight (3.5–4.5 m for the lightning release and impact flashes), or every cast leaves a muddy pool of light around the caster.

## Performance budget

The target is 120 fps with two fighters casting freely.
- **Lights:** at most 2 `OmniLight3D` per live effect, with `shadow_enabled = false`.
- **Lifetime:** effects end within about 1.5 s. The exceptions are the Flame Wall (its spell's `duration`) and ground marks (4 s at most, fading).
- **Static caches and instance uniforms.** Create each `Shader` and base material once. `FireKit._material` and `FrostKit` key their caches by name, and `FireKit.ball` sets `seed` and `heat` with `set_instance_shader_parameter`. Duplicate a material only when a uniform truly can't be per-instance.
- **MultiMesh for many small bits.** `FrostBits`, `FrostCrystals`, `LightningSparks`, `LightningPuffs`, `LightningDebris`, `WindParticles` and `FireMotes` each draw a whole burst in one draw call and simulate it on the CPU. That lets the bits bounce on the real floor height. Fire's bursts use `GPUParticles3D` with shared `ParticleProcessMaterial` recipes (`FireKit.recipe`).
- **Trails by distance.** A fast body lays its trail by distance travelled, not per frame (`FrostSpikeLook`, `WindRibbon`), so it looks the same at any frame rate.
- **One-shot particles:** a one-shot `GPUParticles3D` is a child of its effect's root and is freed with it.
- **Reuse buffers in hot loops** where it's easy. Arcs reuse their mesh (`LightningArc.clear()`, `add()`, `commit()`).
- **Expensive generation goes off the hit frame.** `LightningScorch.prepare()` paints one scorch variant per call, and it is called at the charge and the strike warning rather than on the frame the bolt lands.

## Materials and the ink outline

`ToonMaterials.make_ink_pass()` is a full-screen quad on the camera. It draws ink wherever the opaque pass has depth or normal edges, and it's drawn first among transparent objects (`RENDER_PRIORITY_MIN`).
- **Opaque effect geometry gets a comic outline for free.** Use opaque materials for big, solid silhouettes: a fireball at its peak (`fire_ball.gdshader`), big crystals (`frost_crystal.gdshader`), cloud, dust and debris (`lightning_puff.gdshader`).
- **Use transparent-pass materials for anything that breaks into small bits or burns open through `discard`.** Otherwise every scrap gets its own outline and the burn-out ends in black confetti. Fire switches a fireball to `FireKit.ball_soft_material()` (`depth_prepass_alpha`) the moment it starts to open. Frost draws its small shards with `frost_crystal_glass.gdshader`.
- **A transparent effect that wants an outline draws its own.** The big lightning bolts (the Bolt's channel, the Strike's bolt) use the inked ribbon, `LightningArc.shared_material(true)` with `lightning_ink.gdshader`.

## Headless and out of the tree

Effects run in places with nothing to draw. Autotests and servers run `--headless`. The GUT suite's spell worlds (`tests/spell_world_test.gd`) run real projectiles, strikes and bursts, so their effects run in tests too, in worlds without a camera.
- **Guard every static entry point that touches global transforms, `get_tree()` or physics.** A world or hand that isn't in the tree (being torn down, or built by a test) otherwise logs `Condition "!is_inside_tree()" is true` errors, which bury real errors in the logs. Either return early (`FrostFx._usable`, the `hand.is_inside_tree()` check in `FireFx.charge`), or only `add_child` and do the tree work in `_ready()` (`WindChargeFx`, `LightningChargeFx`).
- **Face the camera in the vertex shader** (`LightningArc`, `FrostTrail`, `wind_face_camera` in `wind_common.gdshaderinc`). Where a script does need a camera (`CombatFeedback._range_scale`, Frost Nova's spike check), it handles `get_camera_3d()` returning null.
- **Skip pure-render work headless.** `LightningScorch.prepare()` paints nothing when `DisplayServer.get_name() == "headless"`.
- **Raycast through the viewport's world.** The `world` that effects receive in the arena is `TrainingMode`, a plain `Node`, so a cast to `Node3D` gives null. Use `world.get_viewport().find_world_3d().direct_space_state`, as `FrostKit.floor_below` and `WindFx._floor_below` do (`LightningFx.floor_below` casts, so in the arena it always returns its fallback). In the start menu the world sits in the showcase's `SubViewport`, which has its own World3D, and the same query finds that floor.
- **Cosmetic randomness uses the global `randf()`.** The simulation rolls no dice and the bots roll their own seeded `RandomNumberGenerator` (`BotBrain.rng`), so effects can roll as many as they like without changing a `--seed` run.

## Prewarm

`SpellFx.prewarm(world)` runs once in `TrainingMode._ready()`. It builds every element's charge (primary and signature), release, projectile look, impacts (struck and not), Flame Wall, Nova, strike warning and strike, Shatter and shock, out of sight at y = -80. It skips `SpellSfx`, so it is silent, and everything it builds frees itself. It costs about 0.3 s at arena load. Without it, each element's first charge, release and impact stalls a frame by tens of milliseconds while GDScript builds the caches.

Prewarm calls impacts with `fizzled = false`, and nothing is under y = -80, so floor-only branches never find a floor. If your cache is filled only in a fizzle or floor branch, either build it eagerly in the module's shared builder (as `WindFx._build_shared` builds every wind material at once) or add a call to `prewarm` that reaches that branch. A new element or a new kind of signature needs its own branch in `prewarm`, because it matches on element and spell class.

## Hooks into the fighter and the spells

- **Charge.** `FighterVisual._update_gauntlet` calls `SpellFx.charge` with the gauntlet core as `hand`. It remembers the children that the call added (`_charge`, by child count), and `SpellFx.cancel_charge` frees them if the cast is interrupted. So the charge adds its root directly under `hand`, synchronously. Once the spell is released nobody tracks the charge, so it frees itself after `seconds`. The core swells up to 1.75x during the windup, so charges counter-scale (`FireCharge`, `FrostCharge`) or go `top_level` (`LightningChargeFx`).
- **Projectile look and `finish()`.** If a look implements `finish()`, `SpellFx.release_look` moves it into the world at its last transform and calls `finish()` when the projectile ends; the look then fades its trail and frees itself. A look without `finish()` is freed at once.
- **Lightning hand-offs.** `LightningFx` matches a bolt to its release flash and to its impact by physics frame (`claim_release`, `claim_impact`). Keep release, spawn and impact on the tick the simulation fires them.
- **Bones.** An effect that follows limbs (`LightningShockFx`, the arm crawl in `LightningChargeFx`) reads bone poses in the skeleton's `skeleton_updated` signal, the only time the modifiers' final pose is visible. It disconnects in `_exit_tree`, because the skeleton outlives it.
- **Shock and Shatter.** `FighterVisual._update_shock` calls `SpellFx.shock(_pivot, seconds)` once per stun. `CombatFeedback._shatter` calls `SpellFx.shatter`; the spell code doesn't.

## Element folders

| Folder | Main classes |
|---|---|
| `src/vfx/fire/` | `FireFx` routes the calls. `FireKit` holds the shaders, cached materials, meshes, particle recipes and scorch textures. Then `FireBoltLook`, `FireCharge`, `FireMuzzle`, `FireExplosion` (burst and fizzle), `FireScorch` (decal), `FireMotes` (CPU MultiMesh) and `FlameWallLook` (a MultiMesh of tongues over an ember bed, driven by `set_intensity`). Shaders share `fire_noise.gdshaderinc` and `fire_ball_body.gdshaderinc`. |
| `src/vfx/frost/` | `FrostFx` builds the impacts, Nova and Shatter from parts. `FrostKit` holds the palette, crystal meshes, materials, `flash`, `light`, `ring`, `patch` and `floor_below`. Then `FrostBits` (chunks, sparkles, puffs), `FrostCrystals` (erupting crystals), `FrostSpikeLook`, `FrostTrail`, `FrostCharge` and `FrostCling` (crust on a struck body). |
| `src/vfx/lightning/` | `LightningFx` routes the calls and holds the frame hand-offs, `light_flash` and `floor_below`. `LightningArc` and `LightningCrackle` draw the jagged ribbons. Then `LightningFlare`, `LightningSparks`, `LightningPuffs`, `LightningDebris`, `LightningScorch`, `LightningBoltLook`, `LightningChargeFx`, `LightningWarningFx`, `LightningCloud`, `LightningStrikeFx` and `LightningShockFx`. |
| `src/vfx/wind/` | `WindFx` routes the calls and caches the materials, meshes and sprays (`_build_shared`). `WindOneShot` plays shader parts once on a `progress` instance uniform and then frees itself. Then `WindMeshes` (procedural meshes), `WindParticles`, `WindRibbon`, `WindSlashLook`, `WindSpearLook`, `WindChargeFx` and `WindPushTrail`. Shaders share `wind_common.gdshaderinc`. |
| `src/vfx/` | `SpellFx` (the router and `prewarm`), `Vfx` (comic star `impact`, element `accent`, `ring`, `slash`), `WeaponTrail`, `Afterimages`, and the body shaders `ember.gdshader` and `frost_crust.gdshader`. |

## The impact-feel layer

Element modules draw the spell. The layer below reacts to `CombatEvents` and only reads simulation state.

| What | Owner |
|---|---|
| Camera shake: trauma, `buzz` (lightning), `rumble` (fire), `jolt` (frost), `push` / `push_from` (wind), `kick`, `fov_punch`. None of it moves the aim, and the summed layers are capped by `MAX_OFFSET`, `MAX_TILT` and `MAX_FOV`. `shake_scale` turns it all down. | `CameraRig` (`src/core/camera_rig.gd`) |
| Which shake, how strong, and when: per-spell `WEIGHT`, the element's flavor, felt-nearby falloff (`STRIKE_FELT`, `BURST_FELT`). The camera and screen react only to what involves `focus`, the local player. It's the only caller of the camera's shake and of `ScreenFx`. | `CombatFeedback` (`src/world/combat_feedback.gd`) |
| Screen effects: `flash`, `pulse`, `warp`, and the steady `frost` and `shock` edges. Canvas layer 2, under the HUD. | `ScreenFx` (`src/vfx/screen/`) |
| Impact stars and accents: the classic star for melee (`Vfx.impact`), an element-shaped accent for spells (`Vfx.accent`), nudged toward the camera and scaled up with range. | `CombatFeedback`, drawn by `Vfx` |
| Body reactions: per-element hit springs (`HitReactModifier.Feel` HARD for fire and Shatter, STIFF for frost and lightning), `HitReactModifier.shiver` and `jitter`, and `BodyDynamics` `recoil`, `squash`, `carry` and tumble. Hit flashes are styled by element (`FighterVisual.Flash`). | `FighterVisual._take_hit`, `src/animation/hit_react_modifier.gd`, `src/animation/body_dynamics.gd` |
| Status looks: the Burning rim and embers, the Chilled rim plus the `frost_crust.gdshader` next pass, and the stun's rim crackle. | `FighterVisual._update_status_tint` and `_update_frost_crust` |
| The electric spasm: `AnimDirector`'s `ShockJitter` for a stun, `HitReactModifier.jitter` for a Bolt flinch. Run one rigid layer per spasm, because two stack their poses. | `src/animation/anim_director.gd`, `HitReactModifier` |
| Damage numbers and callouts (SHATTER!, SHOCKED!, PARRY!, ...). | `DamageNumbers` (`src/ui/damage_numbers.gd`), not `CombatFeedback` |

Hit-stop is a simulation number in spell data (`hitstop`), applied by `CombatRules.resolve_spell`; `docs/agents/spells.md` covers it. Status looks live on the rim (`rim_color`, `rim_strength`), and a whole-body glow is kept to a brief pop, because the outfits are dark: even a little body emission repaints the whole figure flat orange or yellow.

## Check your effect

The commands and their caveats are in `docs/agents/verification.md`. For each effect, check:
1. **Player view.** The over-the-shoulder camera with the target at 5, 9 and 20 m (`--bot_at`, from open ground), as a contact sheet of 6–12 frames.
2. **Side and close views.** `--spectate=... --spectate_on=bot`, plus slow motion (`--slowmo=0.2`), with dense shots through all five beats.
3. **Every ending.** Hits on a fighter, on a wall and on the floor, a fizzle at max range, and the effect landing on the player's own camera.
4. **Headless.** A `--headless --drive=spells` run with your loadout prints no errors or warnings. With `--sfx_log` (read by `SfxPool`, not the autopilot), the node count it prints every 60 frames settles back to the baseline after the effects end.
5. **Tests.** The GUT suite stays green.
6. **Readability against the rules above:** 0.15 s of cover at most, no blow-out, and the element recognizable by shape at 20 m. Then fix the weakest beat.
