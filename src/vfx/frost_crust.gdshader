shader_type spatial;
// Chill on a fighter, drawn as a second pass over the body's toon materials:
// a crust of frost that hugs the silhouette and settles on surfaces facing
// up, broken into flat crystal facets with bright edges, an ink line where it
// ends, and glints that wink. `amount` (the Chill stacks, 0..1) grows it
// from a thin frosted rim to a rimed shell.
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform float time = 0.0;
uniform vec4 ice : source_color = vec4(0.5, 0.82, 1.0, 1.0);
uniform vec4 rime : source_color = vec4(0.9, 0.97, 1.0, 1.0);
uniform vec4 ice_ink : source_color = vec4(0.1, 0.2, 0.45, 1.0);
// Crystals across the texture layout.
uniform float crystal_scale = 40.0;

varying vec3 world_normal;

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

// x = distance to the border with the next cell, y = the cell's random id.
vec2 cells(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	vec2 best_cell = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 r = g + hash22(i + g) * 0.85 - f;
			float d = dot(r, r);
			if (d < d1) {
				d2 = d1;
				d1 = d;
				best_cell = i + g;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return vec2(sqrt(d2) - sqrt(d1), hash12(best_cell));
}

void vertex() {
	// a hair outside the body, so the crust sits on it rather than in it
	VERTEX += NORMAL * (0.004 + 0.01 * amount);
	world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	vec2 c = cells(UV * crystal_scale);
	float rim = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float up = clamp(normalize(world_normal).y, 0.0, 1.0);
	// where frost sits: the silhouette first, then whatever faces up, whole
	// crystals at a time
	float cover = rim * 1.1 + up * 0.5 + (c.y - 0.5) * 0.4;
	float threshold = 1.02 - amount * 0.52;
	if (cover < threshold) {
		discard;
	}
	float tone = floor(c.y * 3.0) / 3.0;
	vec3 col = mix(ice.rgb, rime.rgb, 0.15 + 0.5 * tone);
	col = mix(col, rime.rgb * 1.2, 1.0 - step(0.07, c.x));
	col = mix(col, ice_ink.rgb, step(cover, threshold + 0.05) * 0.85);
	float glint = step(0.94, hash12(floor(UV * crystal_scale) + floor(time * 6.0))) * step(0.08, c.x);
	ALBEDO = col + glint * 1.6;
	ALPHA = 0.8;
}
