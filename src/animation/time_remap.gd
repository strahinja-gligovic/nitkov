class_name TimeRemap
extends RefCounted
## Pose-to-pose timing. The simulation decides when a swing connects or a
## spell leaves the hand; a clip has its own idea. Instead of stretching the
## whole clip evenly, matching key pairs pin each key pose (wind-up extreme,
## strike start, contact, follow-through) to its simulation moment, and the
## motion between two keys keeps the clip's own spacing. Holds stretch, the
## strike compresses: anticipation reads, and the hit snaps.


## Clip time for simulation time `t`. `sim_keys` and `clip_keys` pair up and
## ascend. Before the first key it holds the first clip key, after the last
## key the last one.
static func map(t: float, sim_keys: PackedFloat32Array, clip_keys: PackedFloat32Array) -> float:
	var count := mini(sim_keys.size(), clip_keys.size())
	if count == 0:
		return t
	if t <= sim_keys[0]:
		return clip_keys[0]
	for i in range(1, count):
		if t < sim_keys[i]:
			var span := sim_keys[i] - sim_keys[i - 1]
			var u := (t - sim_keys[i - 1]) / span if span > 0.0 else 1.0
			return lerpf(clip_keys[i - 1], clip_keys[i], u)
	return clip_keys[count - 1]


## Simulation key times for a swing or a cast, pairing with a move's clip keys
## [start, antic, go, contact, settle, end]. Contact lands exactly when the
## active frames begin (or the spell releases). The strike (go -> contact)
## takes `strike` seconds and the wind-up extreme is held `hold` seconds
## before it; short wind-ups squeeze the hold first, then the strike.
## The follow-through settles `settle_fraction` of the way into recovery.
static func swing_keys(windup: float, active: float, recovery: float,
		strike: float, hold: float, settle_fraction: float) -> PackedFloat32Array:
	var contact := maxf(windup, 0.0)
	var go := maxf(contact - strike, contact * 0.4)
	var antic := maxf(go - hold, go * 0.5)
	var after := maxf(active, 0.0) + maxf(recovery, 0.0)
	var settle := contact + maxf(active, 0.0) + maxf(recovery, 0.0) * clampf(settle_fraction, 0.0, 1.0)
	return PackedFloat32Array([0.0, antic, go, contact, minf(settle, contact + after), contact + after])


## Clip time for `t` seconds into a move lasting `duration`, whose key poses
## (`clip_keys`) land at `fractions` of the duration. Without fractions the
## keys are spaced like the clip: the whole stretch plays evenly.
static func timed(t: float, duration: float, clip_keys: PackedFloat32Array, fractions := PackedFloat32Array()) -> float:
	var count := clip_keys.size()
	if count < 2:
		return clip_keys[0] if count == 1 else t
	var sim := PackedFloat32Array()
	sim.resize(count)
	var first := clip_keys[0]
	var span := maxf(clip_keys[count - 1] - first, 0.0001)
	for i in count:
		var fraction := fractions[i] if fractions.size() == count else (clip_keys[i] - first) / span
		sim[i] = fraction * duration
	return map(t, sim, clip_keys)
