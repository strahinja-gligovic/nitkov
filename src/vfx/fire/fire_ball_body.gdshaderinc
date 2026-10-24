// The body of the fireball shaders (fire_ball.gdshader, opaque with an ink
// outline, and fire_ball_soft.gdshader, drawn in the transparent pass): a
// roiling ball of fire on a unit sphere. Boiling simplex noise sets the heat,
// drawn in hard toon bands (white core, yellow, orange, red, ink); holes are
// cut with discard. Everything that varies per spawn is an instance uniform,
// so one material serves every fireball. Define FIRE_BALL_SOFT before the
// include for the transparent variant.

#include "res://src/vfx/fire/fire_noise.gdshaderinc"

instance uniform float seed = 0.0;
// 1.2 white-hot, 0.8 yellow-orange, 0.4 red, 0.1 nearly burnt out.
instance uniform float heat = 0.8;
// 0 solid .. 1 gone. Holes open where the ball faces the camera first, so a
// dying fireball leaves a ragged burning rim instead of covering what's behind.
instance uniform float dissolve = 0.0;
// 0..1: a burning-out fireball (explosions). Its coolest bands burn away
// first, so the last scraps are red-orange flame with a thin ink edge, never
// loose ink-dark shards.
instance uniform float burnout = 0.0;
// Tail length behind the ball (+Z), in radii (bolts and muzzle jets).
instance uniform float stretch = 0.0;
// Surface boil, in radii.
instance uniform float boil = 0.15;
// Noise speed. The pattern streams toward +Z when stretched, else upward.
instance uniform float flow = 1.0;

varying vec3 v_obj;
varying float v_back;

vec3 drift_dir() {
	return stretch > 0.001 ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0);
}

void vertex() {
	vec3 drift = drift_dir();
	float t = TIME * flow;
	float back = clamp(VERTEX.z, 0.0, 1.0);
	vec3 p = VERTEX;
	float n = fire_noise(VERTEX * 1.7 - drift * t * 2.6 + seed * 7.31);
	p += NORMAL * n * boil * (1.0 + back * 1.5);
	// the back half streams out into a tapering tail
	float s = min(stretch, 1.0);
	p.z += back * back * stretch;
	p.xy *= 1.0 - 0.55 * back * s;
	v_obj = VERTEX;
	v_back = back * s;
	VERTEX = p;
}

void fragment() {
	vec3 drift = drift_dir();
	float t = TIME * flow;
	vec3 q = v_obj * 2.3 - drift * t * 3.2 + seed * 13.7;
	float n = fire_fbm(q);
	float facing = clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	// hottest where the ball faces the camera, cooling toward its silhouette
	float h = heat - 0.27 + 0.42 * facing - 0.5 * v_back + 0.36 * n;
	if (!FRONT_FACING) {
		// the inside of the shell, seen through holes: a little cooler
		h -= 0.15;
	}
	// derivatives first: they're undefined after a discard
	float aa = max(fwidth(h), 0.002);
	// chunky holes, opening where the ball faces the camera first
	float erode = 0.5 + 0.5 * fire_noise(v_obj * 1.6 - drift * t * 1.2 + seed * 5.1);
	erode = erode * 0.55 + (1.0 - facing) * 0.45;
	// ragged tail and flame licks: too cool to be fire is not drawn
	float cutoff = FIRE_T_INK + burnout * (FIRE_T_ORANGE - FIRE_T_INK + 0.04);
	if (h < cutoff || erode < dissolve) {
		discard;
	}
	vec3 color = fire_ramp(h, aa);
	// a scorched ink edge along the holes (and along the burnt-away bands),
	// thinning as the fireball burns out
	float rim_w = mix(0.025, 0.012, burnout);
	float rim = dissolve > 0.0 ? 1.0 - smoothstep(dissolve + rim_w * 0.6, dissolve + rim_w * 1.6, erode) : 0.0;
	rim = max(rim, burnout > 0.0 ? 1.0 - smoothstep(cutoff, cutoff + max(aa * 1.5, 0.02), h) : 0.0);
	ALBEDO = mix(color, FIRE_INK, rim);
#ifdef FIRE_BALL_SOFT
	ALPHA = 1.0;
#endif
}
