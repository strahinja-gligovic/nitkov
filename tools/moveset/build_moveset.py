"""Writes data/moves/humanoid.tres and bakes lunge profiles into data/weapons/longsword.tres.

Every number here was measured from the clips (key poses by blade-tip speed and contact with the
forward line, root travel from the root-motion versions of the clips, foot plants, ground speeds).
data/root_curves.json and data/keys_final.json hold the melee measurements.

Re-run after changing a swing's timing (windup/active/recovery in longsword.tres) or a move here:
    uv run --no-project python -I tools/moveset/build_moveset.py
"""
import json, math, os, re, sys
sys.stdout.reconfigure(encoding="utf-8")
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from moves_react import REACT, frac

REPO = os.path.dirname(os.path.dirname(HERE))
MELEE = os.path.join(HERE, "data")
# our characters' pelvis is 0.949 m vs 0.917 on the mannequin the clips were measured on
BODY_SCALE = 0.949 / 0.917

MELEE_MOVES = {
    "light_1": dict(clip="ual2/Sword_Regular_A", keys=[0.0, 0.167, 0.167, 0.25, 0.317, 0.433], strike=0.05, hold=0.0,
                    settle_fraction=0.0, recover="light_1_rec", blend_in=0.06,
                    slash_from=70.0, slash_to=-80.0, slash_tilt=40.0, slash_height=1.0),
    "light_2": dict(clip="ual2/Sword_Regular_B", keys=[0.0, 0.133, 0.2, 0.25, 0.367, 0.533], strike=0.03, hold=0.04,
                    settle_fraction=0.0, recover="light_2_rec", blend_in=0.05,
                    slash_from=-80.0, slash_to=80.0, slash_tilt=-11.0, slash_height=0.85),
    # windup 0.3 s: its hop and full spin need the room (at 0.2 s the hips spun ~4700 deg/s)
    "light_3": dict(clip="ual2/Sword_Regular_C", keys=[0.0, 0.45, 0.5, 0.693, 0.833, 1.617], strike=0.08, hold=0.02,
                    settle_fraction=0.0, blend_in=0.05,
                    slash_from=70.0, slash_to=-80.0, slash_tilt=-45.0, slash_height=1.0),
    "heavy": dict(clip="ual2/Sword_Heavy_Combo", keys=[2.0, 2.45, 2.5, 2.617, 2.667, 3.233], strike=0.1, hold=0.15,
                  settle_fraction=0.0, recover="heavy_rec", blend_in=0.15,
                  slash_from=-70.0, slash_to=60.0, slash_tilt=90.0, slash_height=1.3),
    # recoveries when the chain stops (presentation only, on their own clock)
    "light_1_rec": dict(clip="ual2/Sword_Regular_A_Rec", keys=[0.0, 0.65], duration=0.65, blend_in=0.0),
    "light_2_rec": dict(clip="ual2/Sword_Regular_B_Rec", keys=[0.0, 0.833], duration=0.833, blend_in=0.0),
    "heavy_rec": dict(clip="ual2/Sword_Heavy_Combo", keys=[3.233, 3.967], duration=0.733, blend_in=0.0),
}

CAST_MOVES = {
    # a left jab throws the bolt; on the move only the left arm and spine take it
    "cast_bolt": dict(clip="ual1/Punch_Jab", keys=[0.0, 0.133, 0.133, 0.2, 0.333, 0.867], strike=0.04, hold=0.0,
                      settle_fraction=0.3, left_arm_only=True, blend_in=0.05),
    # an overhand throw from the gauntlet hand slams the wall down ahead
    "cast_wall": dict(clip="ual2/OverhandThrow", mirror=True, keys=[0.0, 0.267, 0.267, 0.367, 0.45, 1.2], strike=0.09,
                      hold=0.0, settle_fraction=0.1, blend_in=0.08, blend_out=0.15),
    # a two-fisted ground pound bursts frost around the caster
    "cast_nova": dict(clip="m2m_addon/Attack_Ground_Pound", keys=[0.0, 0.25, 0.3, 0.733, 0.783, 0.933], strike=0.1,
                      hold=0.0, settle_fraction=0.1, blend_in=0.06, blend_out=0.15),
}

AIR_MOVES = {
    "leap_start": dict(clip="ual2/NinjaJump_Start", keys=[0.033, 0.45], duration=0.59, blend_in=0.04),
    "leap_air": dict(clip="ual2/NinjaJump_Idle", keys=[0.0, 2.0], blend_in=0.2),
    "leap_fall": dict(clip="ual1/Jump", keys=[0.0, 2.5], blend_in=0.25),
    # UAL1 Jump_Land starts at touchdown and keeps the sword out of the floor (NinjaJump_Land drives it in)
    "leap_land": dict(clip="ual1/Jump_Land", keys=[0.0, 0.2, 0.8], duration=0.8, blend_in=0.05, blend_out=0.15),
    # a crouched arrival; it gives way to running (its planted feet would skate)
    "blink": dict(clip="ual2/Shield_Dash", keys=[0.1, 0.467, 0.8], duration=0.3, blend_in=0.0, blend_out=0.15),
}

LOCO_MOVES = {
    "idle": dict(clip="ual1/Sword_Idle", keys=[0.0, 1.667], blend_in=0.2),
    # first key: when the left foot plants, so the blended strides line up
    "walk": dict(clip="ual1/Walk", keys=[0.0, 1.333], ground_speed=1.0),
    # the first 0.042 s is a pose the importer holds before the first 24 fps key: cut, or every loop stutters
    "run": dict(clip="m2m_addon/Run_Female", clip_from=0.042, keys=[0.425, 0.791], ground_speed=3.47, play_at=2.75),
    "jog": dict(clip="ual1/Jog_Fwd", keys=[0.02, 0.933], ground_speed=6.15, play_at=5.0),
    "sprint": dict(clip="ual1/Sprint", keys=[0.0, 0.667], ground_speed=9.3, play_at=7.5),
}

# slash arcs fitted to the measured blade path (see slash_fit.py)
from slash_fit import fits as slash_fits
for _move, _arc in slash_fits().items():
    MELEE_MOVES[_move].update(_arc)

ALL = {}
for group in (LOCO_MOVES, MELEE_MOVES, CAST_MOVES, REACT, AIR_MOVES):
    for key, value in group.items():
        assert key not in ALL, key
        ALL[key] = value

FIELD_ORDER = ["clip", "clip_from", "keys", "sim_keys", "duration", "mirror", "blend_in", "blend_out", "left_arm_only",
               "keep_while_moving", "strike", "hold", "settle_fraction", "recover", "ground_speed", "play_at", "loop_from",
               "chain_clip", "chain_mirror", "chain_at", "chain_from", "chain_to", "chain_blend",
               "slash_from", "slash_to", "slash_tilt", "slash_height"]
STRINGNAMES = {"clip", "recover", "chain_clip"}


def fmt(value):
    return ("%.4f" % value).rstrip("0").rstrip(".") if isinstance(value, float) else str(value)


def tres_value(field, value):
    if field in STRINGNAMES:
        return '&"%s"' % value
    if field in ("keys", "sim_keys"):
        return "PackedFloat32Array(%s)" % ", ".join(fmt(float(v)) for v in value)
    if isinstance(value, bool):
        return "true" if value else "false"
    return fmt(float(value))


def write_moveset(path):
    lines = ['[gd_resource type="Resource" script_class="MoveSet" load_steps=%d format=3]' % (len(ALL) + 3), "",
             '[ext_resource type="Script" path="res://src/animation/anim_move.gd" id="1_move"]',
             '[ext_resource type="Script" path="res://src/animation/move_set.gd" id="2_set"]', ""]
    for move_id, fields in ALL.items():
        lines.append('[sub_resource type="Resource" id="Move_%s"]' % move_id)
        lines.append('script = ExtResource("1_move")')
        for field in FIELD_ORDER:
            if field in fields:
                lines.append("%s = %s" % (field, tres_value(field, fields[field])))
        lines.append("")
    lines.append("[resource]")
    lines.append('script = ExtResource("2_set")')
    entries = ",\n".join('&"%s": SubResource("Move_%s")' % (m, m) for m in ALL)
    lines.append('moves = Dictionary[StringName, ExtResource("1_move")]({\n%s\n})' % entries)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


# --- lunge profiles -------------------------------------------------------------------------

def swing_keys(windup, active, recovery, strike, hold, settle_fraction):
    """Mirror of TimeRemap.swing_keys."""
    contact = max(windup, 0.0)
    go = max(contact - strike, contact * 0.4)
    antic = max(go - hold, go * 0.5)
    after = max(active, 0.0) + max(recovery, 0.0)
    settle = contact + max(active, 0.0) + max(recovery, 0.0) * min(max(settle_fraction, 0.0), 1.0)
    return [0.0, antic, go, contact, min(settle, contact + after), contact + after]


def remap(t, sim, clip):
    if t <= sim[0]:
        return clip[0]
    for i in range(1, len(sim)):
        if t < sim[i]:
            span = sim[i] - sim[i - 1]
            u = (t - sim[i - 1]) / span if span > 0 else 1.0
            return clip[i - 1] + (clip[i] - clip[i - 1]) * u
    return clip[-1]


def interp(ts, vs, t):
    if t <= ts[0]:
        return vs[0]
    for i in range(1, len(ts)):
        if t <= ts[i]:
            u = (t - ts[i - 1]) / (ts[i] - ts[i - 1])
            return vs[i - 1] + (vs[i] - vs[i - 1]) * u
    return vs[-1]


def lunge_profile(attack, move, curve):
    sim = swing_keys(attack["windup"], attack["active"], attack["recovery"], move["strike"], move["hold"],
                     move["settle_fraction"])
    duration = sim[-1]
    ts = curve["t"]
    vs = curve["root_forward_m"]
    base = interp(ts, vs, move["keys"][0])
    out = []
    steps = int(math.ceil(duration * 60.0)) + 1
    for i in range(steps):
        t = min(i / 60.0, duration)
        c = remap(t, sim, move["keys"])
        out.append(round((interp(ts, vs, c) - base) * BODY_SCALE, 4))
    return out, sim


def bake_lunges(weapon_path):
    curves = {}
    for entry in json.load(open(os.path.join(MELEE, "root_curves.json"), encoding="utf-8")):
        if isinstance(entry, dict):
            curves[entry["label"].split(" = ")[0].strip()] = entry
    text = open(weapon_path, encoding="utf-8").read()
    blocks = re.split(r"(?=\[sub_resource )", text)
    report = []
    for b, block in enumerate(blocks):
        m = re.search(r'^id = &"(\w+)"', block, re.M)
        if not m or m.group(1) not in ("light_1", "light_2", "light_3", "heavy"):
            continue
        attack_id = m.group(1)

        def number(name):
            return float(re.search(r"^%s = ([\d.]+)" % name, block, re.M).group(1))

        attack = dict(windup=number("windup"), active=number("active"), recovery=number("recovery"))
        profile, sim = lunge_profile(attack, MELEE_MOVES[attack_id], curves[attack_id])
        block = re.sub(r"^lunge_speed = .*\n", "", block, flags=re.M)
        block = re.sub(r"^lunge_profile = .*\n", "", block, flags=re.M)
        block = re.sub(r"^lunge_scale = .*\n", "", block, flags=re.M)
        line = "lunge_profile = PackedFloat32Array(%s)\n" % ", ".join(fmt(v) for v in profile)
        block = re.sub(r"^(arc = .*\n)", lambda mm: mm.group(1) + line, block, count=1, flags=re.M)
        blocks[b] = block
        contact = profile[min(int(round(attack["windup"] * 60)), len(profile) - 1)]
        report.append("%s: %.2f m by contact, %.2f m total (sim keys %s)" % (
            attack_id, contact, profile[-1], ", ".join("%.3f" % k for k in sim)))
    with open(weapon_path, "w", encoding="utf-8", newline="\n") as f:
        f.write("".join(blocks))
    return report


if __name__ == "__main__":
    write_moveset(os.path.join(REPO, "data", "moves", "humanoid.tres"))
    print("moves:", len(ALL))
    for line in bake_lunges(os.path.join(REPO, "data", "weapons", "longsword.tres")):
        print(line)
