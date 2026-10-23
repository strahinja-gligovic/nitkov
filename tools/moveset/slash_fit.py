"""Fits each swing's slash arc (Vfx.slash: a sector in the forward plane rolled by `tilt`) to the
measured blade-tip positions at go, contact and settle (character frame: Forward, Right, Up)."""
import json, math, os
PIVOT_UP = 1.25
MELEE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")


def fit(points):
    rel = [(f, r, u - PIVOT_UP) for f, r, u in points]
    srr = sum(r * r for _, r, _ in rel)
    suu = sum(u * u for _, _, u in rel)
    sru = sum(r * u for _, r, u in rel)
    # smallest eigenvector of [[srr, sru], [sru, suu]] -> (sin t, cos t)
    tr, det = srr + suu, srr * suu - sru * sru
    lam = tr / 2 - math.sqrt(max(tr * tr / 4 - det, 0.0))
    if abs(sru) > 1e-9:
        s, c = lam - suu, sru
    else:
        s, c = (1.0, 0.0) if srr < suu else (0.0, 1.0)
    norm = math.hypot(s, c)
    s, c = s / norm, c / norm
    t = math.atan2(s, c)
    if t > math.pi / 2:
        t -= math.pi
    elif t < -math.pi / 2:
        t += math.pi
    s, c = math.sin(t), math.cos(t)
    angles, radii = [], []
    for f, r, u in rel:
        right = c * r - s * u
        angles.append(math.degrees(math.atan2(right, f)))
        radii.append(math.hypot(right, f))
    go, contact, settle = angles
    # the strike only: from 90 deg before contact to 50 deg past it, in the direction the
    # follow-through travels (backswings can go the long way round, so not from go)
    delta = (settle - contact + 540.0) % 360.0 - 180.0
    direction = 1.0 if delta > 0 else -1.0
    return dict(slash_from=round(contact - direction * 90.0, 1), slash_to=round(contact + direction * 50.0, 1),
                slash_tilt=round(math.degrees(t), 1), slash_height=PIVOT_UP)


def fits():
    data = {e["id"]: e for e in json.load(open(os.path.join(MELEE, "keys_final.json"), encoding="utf-8"))}
    out = {}
    for move, key in [("light_1", "A"), ("light_2", "B"), ("light_3", "C"), ("heavy", "Heavy_4")]:
        d = data[key]["direction"]
        out[move] = fit([d["tip_go"], d["tip_contact"], d["tip_settle"]])
    return out


if __name__ == "__main__":
    for move, arc in fits().items():
        print(move, arc)
