"""Reaction, defence, dash, death and entrance moves (clip windows and key poses measured from the
clips). Each entry: AnimMove field -> value."""

def frac(game_times, duration):
    return [round(t / duration, 4) for t in game_times]

REACT = {
    # guard: raise the gauntlet (Shield_OneShot 0-0.167) then hold Idle_Shield (loop), upper body
    "block": dict(clip="ual2/Shield_OneShot", chain_clip="ual2/Idle_Shield", chain_at=0.167, chain_from=0.0,
                  chain_to=2.5, chain_blend=0.05, keys=[0.0, 2.617], loop_from=0.167, blend_in=0.08),
    # a blocked hit: snap to the recoil peak, hold, then crossfade back to the guard
    "block_impact": dict(clip="ual2/Idle_Shield_Break", keys=[0.0, 0.067, 0.067], sim_keys=[0.0, 0.27, 1.0],
                         duration=0.25, blend_in=0.0),
    # parry deflect (event-triggered at the hit): blade sweeps up across the body
    "parry": dict(clip="ual2/Sword_Block", keys=[0.067, 0.1, 0.167, 0.333], sim_keys=frac([0.0, 0.03, 0.09, 0.27], 0.27),
                  duration=0.27, blend_in=0.0),
    # guard smashed open (0.8 s stagger)
    "guard_break": dict(clip="ual2/Idle_Shield_Break", keys=[0.0, 0.133, 0.233, 0.95, 1.067],
                        sim_keys=frac([0.0, 0.10, 0.24, 0.72, 0.80], 0.8), blend_in=0.03),
    # light hit (0.25 s): frame 0 is the impact extreme
    "flinch": dict(clip="ual1/Hit_Chest", keys=[0.0, 0.033, 0.3, 0.333], sim_keys=frac([0.0, 0.03, 0.22, 0.25], 0.25),
                   blend_in=0.02),
    # heavy hit (0.4 s): the biggest clean backward rock
    "flinch_heavy": dict(clip="ual2/Idle_Shield_Break", keys=[0.067, 0.133, 0.233, 0.6],
                         sim_keys=frac([0.0, 0.06, 0.14, 0.40], 0.4), blend_in=0.02),
    # parried light (1.0 s): sword thrown up, arms wide, chest open
    "stagger": dict(clip="m2m_addon/Death_A", keys=[0.075, 0.3, 1.05], sim_keys=frac([0.0, 0.2, 1.0], 1.0), blend_in=0.03),
    # parried heavy (1.5 s): the same, stretched; never past the kneel at 1.45
    "stagger_long": dict(clip="m2m_addon/Death_A", keys=[0.075, 0.3, 0.6, 1.35],
                         sim_keys=frac([0.0, 0.25, 0.6, 1.5], 1.5), blend_in=0.03),
    # Shatter: knocked flat, then back up (Hit_Knockback flowing into LayToIdle)
    "knockdown": dict(clip="ual2/Hit_Knockback", chain_clip="ual2/LayToIdle", chain_at=0.4, chain_from=0.083,
                      chain_to=1.4, chain_blend=0.08, keys=[0.0, 0.067, 0.3, 0.637, 0.987, 1.637], blend_in=0.02),
    # deaths: a full fall, and a blast-off variant
    # the killing blow snaps the body back (Hit_Chest), then it falls (Death01 past its slow buckle)
    "death": dict(clip="ual1/Hit_Chest", chain_clip="ual1/Death01", chain_at=0.12, chain_from=0.45, chain_to=1.6,
                  chain_blend=0.08, keys=[0.0, 0.52, 1.19], duration=1.19, blend_in=0.02),
    "death_blast": dict(clip="m2m_addon/Death_C", keys=[0.0, 0.6, 1.9], duration=1.9, blend_in=0.05),
    # dashes (0.25 s): played evenly across the window
    "dash_f": dict(clip="ual2/Sword_Dash", keys=[0.2, 0.233, 0.267, 0.367, 0.45], blend_in=0.03),
    "dash_b": dict(clip="m2m_addon/Dodge_back", keys=[0.05, 0.1, 0.217, 0.3, 0.45], blend_in=0.03),
    "dash_l": dict(clip="m2m_addon/Dodge_left", keys=[0.083, 0.133, 0.15, 0.267, 0.5], blend_in=0.03),
    "dash_r": dict(clip="m2m_addon/Dodge_right", keys=[0.083, 0.133, 0.15, 0.267, 0.5], blend_in=0.03),
    # flourishes on their own clock
    "taunt": dict(clip="m2m_addon/Victory", keys=[0.0, 0.4, 0.5, 0.767, 1.217, 1.667], duration=1.667, blend_in=0.15),
    "entrance": dict(clip="m2m_addon/Land_Three_Point", chain_clip="ual2/NinjaJump_Land", chain_at=1.0,
                     chain_from=0.25, chain_to=1.267, chain_blend=0.2, keys=[0.0, 0.5, 0.7, 0.95, 1.817],
                     duration=1.817, blend_in=0.0),
}
