shader_type canvas_item;
// Full-screen feedback for the local player, over the 3D view and under the
// HUD. Every layer hugs the screen's edges, so the middle (your enemy) stays
// clear, and gradients are stepped into hard bands (the cel look):
//   flash   a brief wash of light (a bolt landing nearby, Shatter, a stun)
//   pulse   a tinted vignette that swells and fades with it
//   frost   ice crystals growing in from the edges while Chilled
//   shock   electric arcs crackling along the edges while stunned
// `time` comes from code, so slow motion slows it too.

uniform vec4 flash_color : source_color = vec4(1.0);
uniform float flash = 0.0;
uniform vec4 pulse_color : source_color = vec4(1.0);
uniform float pulse = 0.0;
uniform float frost = 0.0;
uniform float shock = 0.0;
uniform float time = 0.0;
uniform float aspect = 1.7778;

const vec3 ICE = vec3(0.55, 0.84, 1.0);
const vec3 RIME = vec3(0.92, 0.98, 1.0);
const vec3 ICE_INK = vec3(0.07, 0.13, 0.3);
const vec3 SPARK = vec3(1.0, 0.86, 0.3);
const vec3 SPARK_CORE = vec3(1.0, 1.0, 0.9);
const vec3 INK = vec3(0.06, 0.03, 0.09);

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

// Distance in from the screen's border, in screen heights: 0 at the edge,
// 0.5 at the middle. Rounded corners sit a little deeper.
float inset(vec2 p) {
	vec2 half_size = vec2(aspect, 1.0) * 0.5;
	float r = 0.2;
	vec2 q = abs(p) - (half_size - r);
	return -(length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r);
}

// Crystal cells around p: x = distance to the border with the next cell,
// y = the nearest cell's random id, zw = the nearest cell's seed point.
vec4 cells(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	vec2 best = vec2(0.0);
	vec2 best_cell = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 r = g + hash22(i + g) * 0.85 - f;
			float d = dot(r, r);
			if (d < d1) {
				d2 = d1;
				d1 = d;
				best = r;
				best_cell = i + g;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return vec4(sqrt(d2) - sqrt(d1), hash12(best_cell), p + best);
}

// Smooth 1D value noise, 0..1.
float noise1(float x, float seed) {
	float i = floor(x);
	float f = fract(x);
	return mix(hash12(vec2(i, seed)), hash12(vec2(i + 1.0, seed)), f * f * (3.0 - 2.0 * f));
}

// How far in the frost's crust reaches around screen point p (in screen
// heights): further in the corners, unevenly along each edge, growing with
// `frost`.
float frost_reach(vec2 p, vec3 ef) {
	vec2 half_size = vec2(aspect, 1.0) * 0.5;
	float corner = 1.0 - smoothstep(0.0, 0.55, length(half_size - abs(p)));
	float wobble = 0.55 + 0.9 * noise1(ef.z * 7.0, ef.x);
	return frost * (0.01 + 0.08 * corner * corner) * wobble + frost * frost * 0.012;
}

// The nearest screen edge to p (0 bottom, 1 right, 2 top, 3 left), the
// distance in from it and the position along it, all in screen heights.
vec3 edge_frame(vec2 p) {
	vec2 half_size = vec2(aspect, 1.0) * 0.5;
	vec2 gap = half_size - abs(p);
	float edge = gap.x < gap.y ? (p.x > 0.0 ? 1.0 : 3.0) : (p.y > 0.0 ? 2.0 : 0.0);
	return vec3(edge, min(gap.x, gap.y), gap.x < gap.y ? p.y : p.x);
}

// How far in the frost's ice teeth reach at p: a row of sharp crystals along
// each edge, every one its own length, two sizes interleaved.
float teeth(float along, float edge, float reach) {
	float big = along * 30.0 + edge * 17.0;
	float id = floor(big);
	// each tooth leans its own way, and only a few grow long
	float apex = (hash12(vec2(id, edge + 3.0)) - 0.5) * 0.6;
	float u = fract(big) - 0.5;
	float shape = u < apex ? (u + 0.5) / (apex + 0.5) : (0.5 - u) / (0.5 - apex);
	float len = frost * frost * (0.006 + 0.05 * pow(hash12(vec2(id, edge)), 2.5));
	float small = along * 83.0 + edge * 5.0;
	float v = fract(small) - 0.5;
	float len2 = frost * (0.003 + 0.01 * hash12(vec2(floor(small), edge + 9.0)));
	return reach + max(len * shape, len2 * (1.0 - 2.0 * abs(v)));
}

void fragment() {
	vec2 p = (UV - 0.5) * vec2(aspect, 1.0);
	float depth = inset(p);
	vec3 col = vec3(0.0);
	float a = 0.0;

	// frost: a rime crust packed against the edges (flat facets with bright
	// seams), ice teeth jutting in from it, and an ink line around the lot.
	// Translucent and thin along the edges, thicker in the corners; one stack
	// is a hint of rime, three a proper crust (the teeth grow with the square)
	if (frost > 0.001 && depth < 0.24) {
		// the side edges and the top/bottom edges each grow their own frost;
		// taking the deeper of the two keeps the corners seamless
		vec2 half_size = vec2(aspect, 1.0) * 0.5;
		vec2 gap = half_size - abs(p);
		vec3 ef_side = vec3(p.x > 0.0 ? 1.0 : 3.0, gap.x, p.y);
		vec3 ef_cap = vec3(p.y > 0.0 ? 2.0 : 0.0, gap.y, p.x);
		float reach_side = frost_reach(p, ef_side);
		float reach_cap = frost_reach(p, ef_cap);
		float in_side = teeth(ef_side.z, ef_side.x, reach_side) - gap.x;
		float in_cap = teeth(ef_cap.z, ef_cap.x, reach_cap) - gap.y;
		bool side_wins = in_side > in_cap;
		vec3 ef = side_wins ? ef_side : ef_cap;
		float reach = side_wins ? reach_side : reach_cap;
		float inside = max(in_side, in_cap);
		float inside_px = inside / max(fwidth(inside), 1e-5);
		if (inside > 0.0) {
			vec4 facet = cells(p * 18.0 + 11.0);
			float tone = floor(facet.y * 3.0) / 3.0;
			vec3 ice;
			float ia;
			if (ef.y < reach) {
				ice = mix(ICE, RIME, 0.45 + 0.4 * tone);
				ice = mix(ice, vec3(1.0), (1.0 - step(0.05, facet.x)) * 0.5);
				ia = 0.42 + 0.2 * (1.0 - step(0.012, ef.y));
			} else {
				// a tooth: pale ice, its lit half brighter (a cut facet)
				float side = step(0.5, fract(ef.z * 30.0 + ef.x * 17.0));
				ice = mix(ICE, RIME, 0.5 + 0.45 * side);
				ia = 0.5;
			}
			// now and then a facet catches the light
			float glint = step(0.94, hash12(vec2(facet.y * 97.0, floor(time * 6.0)))) * step(0.06, facet.x);
			// the ink line, measured in pixels so the teeth's steep flanks keep it
			bool ink = inside_px < 2.2;
			ice = ink ? ICE_INK : ice;
			col = ink ? ice : mix(ice, vec3(1.0), glint * 0.85);
			a = (ink ? 0.62 : ia) * smoothstep(0.0, 0.15, frost);
		}
	}

	// shock: short jagged arcs leaping off the screen's edges, two per edge,
	// each one re-drawn somewhere else about 20 times a second. Drawn like
	// ink: a white-hot core, a yellow body and a dark outline, all opaque. As
	// the stun wears off the arcs get rarer and shorter rather than fading,
	// so they never smear into a dull haze.
	if (shock > 0.001 && depth < 0.1) {
		vec3 ef = edge_frame(p);
		vec2 half_size = vec2(aspect, 1.0) * 0.5;
		float in_from = ef.y;
		float along = ef.z;
		float span = (ef.x == 1.0 || ef.x == 3.0) ? half_size.y : half_size.x;
		float beat = floor(time * 20.0);
		float px = 9999.0;
		for (int k = 0; k < 2; k++) {
			float seed = beat * 3.17 + ef.x * 11.3 + float(k) * 5.9;
			if (hash12(vec2(seed, 1.7)) > 0.2 + 0.55 * shock) {
				continue;  // this one skips a beat: crackle, not a frame
			}
			float centre = (hash12(vec2(seed, 4.1)) * 2.0 - 1.0) * span * 0.85;
			float reach = (0.07 + 0.09 * hash12(vec2(seed, 8.3))) * (0.55 + 0.45 * shock);
			float t = (along - centre) / reach;
			if (abs(t) >= 1.0) {
				continue;
			}
			// an arch that leaves the edge and comes back to it, kinked every few pixels
			float x = along * 70.0;
			float i0 = floor(x);
			float kink = mix(hash12(vec2(i0, seed)), hash12(vec2(i0 + 1.0, seed)), fract(x)) - 0.5;
			float arch = sqrt(1.0 - t * t);
			float line_depth = arch * (0.022 + 0.03 * hash12(vec2(seed, 2.3))) + kink * 0.016 * arch;
			// and a fork splitting off it, inward
			float fork_at = hash12(vec2(seed, 6.7)) * 1.2 - 0.6;
			float fork_depth = line_depth + max(t - fork_at, 0.0) * (0.05 + 0.05 * hash12(vec2(seed, 9.1)))
					+ kink * 0.01;
			// distances in pixels across the line, however steep the kink
			float f1 = in_from - line_depth;
			px = min(px, abs(f1) / max(fwidth(f1), 1e-5));
			if (t > fork_at) {
				float f2 = in_from - fork_depth;
				px = min(px, abs(f2) / max(fwidth(f2), 1e-5) * 1.5);
			}
		}
		vec3 c = SPARK;
		float ca = 0.0;
		if (px < 6.5) {
			c = px < 1.6 ? SPARK_CORE : (px < 4.0 ? SPARK : INK);
			ca = px < 4.0 ? 1.0 : 0.8;
		} else if (in_from < 0.008) {
			// a thin glow hugging the edge, flickering with the arcs
			ca = (0.12 + 0.16 * hash12(vec2(beat, 0.3))) * shock;
		}
		col = mix(col, c, ca);
		a = ca + a * (1.0 - ca);
	}

	// pulse: a tinted vignette in three hard bands
	if (pulse > 0.001) {
		float v = clamp(1.0 - depth / 0.3, 0.0, 1.0);
		v = floor(v * 3.0 + 0.5) / 3.0;
		float pa = v * pulse * 0.6;
		col = mix(col, pulse_color.rgb, pa);
		a = pa + a * (1.0 - pa);
	}

	// flash: a brief wash, lighter in the middle so the enemy stays readable
	if (flash > 0.001) {
		float fa = flash * mix(0.4, 1.0, clamp(1.0 - depth / 0.45, 0.0, 1.0));
		col = mix(col, flash_color.rgb, fa);
		a = fa + a * (1.0 - fa);
	}

	COLOR = vec4(col, clamp(a, 0.0, 1.0));
}
