"""Reaction, defence, dash, death and entrance moves (clip windows and key poses measured from the
clips). Each entry: AnimMove field -> value."""

def frac(game_times, duration):
    return [round(t / duration, 4) for t in game_times]


def twitch(clip_a, clip_b, until, count, end_key):
    """Keys and fractions for an electrocuted twitch: snap to clip_a, then jerk between clip_a and
    clip_b `count` times, closing in on the middle, until `until` (a fraction of the move), then
    ease to end_key by the end."""
    keys, fractions = [clip_a], [0.0]
    step = until / (count + 1)
    for i in range(count):
        shrink = 1.0 - 0.6 * i / max(count - 1, 1)
        mid = (clip_a + clip_b) * 0.5
        target = clip_b if i % 2 == 0 else clip_a
        keys.append(round(mid + (target - mid) * shrink, 4))
        fractions.append(round(step * (i + 1), 4))
    return keys + [end_key], fractions + [1.0]


_SHOCK_KEYS, _SHOCK_FRACTIONS = twitch(0.2, 0.07, 0.78, 17, 0.15)

REACT = {
    # guard: raise the gauntlet (Shield_OneShot 0-0.167) then hold Idle_Shield (loop), upper body
    "block": dict(clip="ual2/Shield_OneShot", chain_clip="ual2/Idle_Shield", chain_at=0.167, chain_from=0.0,
                  chain_to=2.5, chain_blend=0.05, keys=[0.0, 2.617], loop_from=0.167, blend_in=0.08),
    # a blocked hit: snap to the recoil peak, hold, then crossfade back to the guard
    # the recoil out and back along the same path, ending exactly on the hold
    "block_impact": dict(clip="ual2/Idle_Shield_Break", keys=[0.0, 0.05, 0.0], sim_keys=[0.0, 0.2, 1.0],
                         duration=0.25, blend_in=0.0),
    # parry deflect (event-triggered at the hit): blade sweeps up across the body
    "parry": dict(clip="ual2/Sword_Block", keys=[0.067, 0.1, 0.15, 0.333], sim_keys=frac([0.0, 0.03, 0.09, 0.27], 0.27),
                  duration=0.27, blend_in=0.0, blend_out=0.16),
    # guard smashed open (0.8 s stagger)
    # stops before the gauntlet swings back into a guard the fighter cannot use yet
    "guard_break": dict(clip="ual2/Idle_Shield_Break", keys=[0.0, 0.133, 0.233, 0.55],
                        sim_keys=frac([0.0, 0.10, 0.24, 0.80], 0.8), blend_in=0.03, blend_out=0.2),
    # light hit (0.25 s): frame 0 is the impact extreme
    "flinch": dict(clip="ual1/Hit_Chest", keys=[0.0, 0.033, 0.3, 0.333], sim_keys=frac([0.0, 0.03, 0.22, 0.25], 0.25),
                   blend_in=0.02, blend_out=0.15),
    # heavy hit (0.4 s): the biggest clean backward rock
    "flinch_heavy": dict(clip="ual2/Idle_Shield_Break", keys=[0.067, 0.133, 0.233, 0.6],
                         sim_keys=frac([0.0, 0.06, 0.14, 0.40], 0.4), blend_in=0.02, blend_out=0.18),
    # parried light (1.0 s): sword thrown up, arms wide, chest open
    "stagger": dict(clip="m2m_addon/Death_A", keys=[0.075, 0.3, 1.05], sim_keys=frac([0.0, 0.2, 1.0], 1.0), blend_in=0.03,
                    blend_out=0.18),
    # parried heavy (1.5 s): the same, stretched; never past the kneel at 1.45
    "stagger_long": dict(clip="m2m_addon/Death_A", keys=[0.075, 0.3, 0.6, 1.35],
                         sim_keys=frac([0.0, 0.25, 0.6, 1.5], 1.5), blend_in=0.03, blend_out=0.18),
    # Lightning Strike's stun (1.0 s): snapped rigid with the arms flung up and the legs braced, jerking
    # with the current, the jolts dying away (Jumping Jacks' grounded star, before it jumps)
    "stagger_shock": dict(clip="m2m_addon/Jumping Jacks", keys=_SHOCK_KEYS, sim_keys=_SHOCK_FRACTIONS, blend_in=0.0,
                          blend_out=0.2),
    # thrown through the air by a shove (a wind burst): legs swept up, arms flung, played over the
    # first half second off the ground (AnimDirector.BLOWN_SPEED)
    "blown": dict(clip="ual2/Hit_Knockback", keys=[0.03, 0.09, 0.12, 0.07], sim_keys=[0.0, 0.25, 0.65, 1.0],
                  duration=0.5, blend_in=0.05, blend_out=0.2),
    # Shatter: knocked flat, then back up (Hit_Knockback flowing into LayToIdle)
    # a cut whose get-up keeps the blade out of the floor and the thigh (1.13 s, fits the 1.2 s Shatter)
    "knockdown": dict(clip="ual2/Hit_Knockback", chain_clip="ual2/LayToIdle", chain_at=0.5, chain_from=0.625,
                      chain_to=1.4, chain_blend=0.15, keys=[0.0, 0.067, 0.3, 0.475, 0.725, 1.125], blend_in=0.02,
                      blend_out=0.15),
    # deaths: a full fall, and a blast-off variant
    # the killing blow snaps the body back (Hit_Chest), then it falls (Death01 past its slow buckle)
    "death": dict(clip="ual1/Hit_Chest", chain_clip="ual1/Death01", chain_at=0.12, chain_from=0.45, chain_to=1.6,
                  chain_blend=0.08, keys=[0.0, 0.52, 1.19], duration=1.19, blend_in=0.02),
    "death_blast": dict(clip="m2m_addon/Death_C", keys=[0.0, 0.6, 1.9], duration=1.9, blend_in=0.05),
    # dashes (0.25 s): played evenly across the window
    "dash_f": dict(clip="ual2/Sword_Dash", keys=[0.2, 0.217, 0.367, 0.4, 0.45], blend_in=0.05, blend_out=0.15),
    "dash_b": dict(clip="m2m_addon/Dodge_back", keys=[0.05, 0.1, 0.217, 0.3, 0.45], blend_in=0.03, blend_out=0.12),
    # side dodges start mid-takeoff: snappier, and the sword hand no longer passes the face
    "dash_l": dict(clip="m2m_addon/Dodge_left", keys=[0.15, 0.267, 0.5], blend_in=0.04, blend_out=0.14),
    "dash_r": dict(clip="m2m_addon/Dodge_right", keys=[0.15, 0.267, 0.5], blend_in=0.04, blend_out=0.14),
    # flourishes on their own clock
    # mirrored: the gauntlet fist goes up and the sword stays across the front (no blade through the torso)
    "taunt": dict(clip="m2m_addon/Victory", mirror=True, keys=[0.0, 0.4, 0.517, 0.767, 1.217, 1.667], duration=1.667,
                  blend_in=0.15, blend_out=0.2),
    # the landing mirrored: the gauntlet hand plants, the sword is held clear
    "entrance": dict(clip="m2m_addon/Land_Three_Point", mirror=True, chain_clip="ual2/NinjaJump_Land", chain_at=1.0,
                     chain_from=0.25, chain_to=1.267, chain_blend=0.2, keys=[0.0, 0.467, 0.733, 0.95, 1.38, 1.817],
                     duration=1.817, blend_in=0.0),
}
