shader_type spatial;
// Wind's flying bits, one MultiMesh instance each (see WindParticles):
// cel-shaded dust puffs with ink rims that dissolve as they age, leaves and
// stone chips that tumble with their transform, and glowing motes. Dust and
// motes face the camera. INSTANCE_CUSTOM = (kind, life 0..1, random, alpha).
// Premultiplied alpha: the motes add light, everything else covers.
render_mode unshaded, blend_premul_alpha, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

#include "res://src/vfx/wind/wind_common.gdshaderinc"

uniform vec4 ink_color : source_color = vec4(0.07, 0.04, 0.1, 1.0);
uniform vec4 dust_light : source_color = vec4(0.7, 0.62, 0.66, 1.0);
uniform vec4 dust_mid : source_color = vec4(0.54, 0.46, 0.55, 1.0);
uniform vec4 dust_dark : source_color = vec4(0.4, 0.33, 0.44, 1.0);
uniform vec4 stone_light : source_color = vec4(0.52, 0.46, 0.56, 1.0);
uniform vec4 stone_dark : source_color = vec4(0.3, 0.26, 0.34, 1.0);
uniform vec4 mote_color : source_color = vec4(0.5, 1.0, 0.72, 1.0);
uniform float mote_energy = 2.2;
// Bits this close to the camera (metres) thin out, so dust you stand in
// doesn't wall off the screen.
uniform float near_fade_from = 0.8;
uniform float near_fade_to = 2.6;

varying flat float v_kind;
varying float v_life;
varying float v_seed;
varying float v_alpha;

void vertex() {
	v_kind = INSTANCE_CUSTOM.x;
	v_life = INSTANCE_CUSTOM.y;
	v_seed = INSTANCE_CUSTOM.z;
	v_alpha = INSTANCE_CUSTOM.w;
	if (v_kind < 0.5 || v_kind > 2.5) {
		// dust (0) and motes (3) face the camera, keeping the instance's size
		float size = length(MODEL_MATRIX[0].xyz);
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * size, INV_VIEW_MATRIX[1] * size,
				INV_VIEW_MATRIX[2] * size, MODEL_MATRIX[3]);
	}
}

vec3 leaf_color(float pick) {
	if (pick < 0.3) {
		return vec3(0.42, 0.78, 0.3);
	} else if (pick < 0.55) {
		return vec3(0.72, 0.86, 0.32);
	} else if (pick < 0.8) {
		return vec3(0.36, 0.9, 0.62);
	}
	return vec3(0.95, 0.7, 0.3);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	int kind = int(v_kind + 0.5);
	vec3 color = vec3(0.0);
	float alpha = 0.0;
	vec3 glow = vec3(0.0);
	if (kind == 0) {
		// dust: a lumpy cel-shaded puff, lit from above, eaten away as it ages
		float d = length(p);
		float lump = wind_noise(p * 2.2 + v_seed * 31.0);
		float edge = 0.72 + 0.26 * lump;
		float shape = 1.0 - wind_band(edge, d);
		float holes = wind_noise(p * 4.5 - v_seed * 13.0) * (1.0 - 0.5 * d);
		shape *= wind_band(v_life * v_life * 0.75, holes);
		vec3 n = normalize(vec3(p.x, -p.y, sqrt(max(1.0 - d * d, 0.05))));
		float light = dot(n, normalize(vec3(-0.35, 0.85, 0.4)));
		color = light > 0.5 ? dust_light.rgb : (light > 0.05 ? dust_mid.rgb : dust_dark.rgb);
		color = mix(color, ink_color.rgb, wind_band(edge - 0.13, d) * 0.45);
		alpha = shape * v_alpha * 0.55;
	} else if (kind == 1) {
		// leaf: a pointed oval with a bent midrib and an ink edge
		float x = p.x;
		float y = p.y - 0.18 * (x * x - 0.35);
		float half_width = 0.5 * pow(max(1.0 - x * x, 0.0), 0.75);
		float inside = 1.0 - wind_band(half_width, abs(y));
		float stem = (1.0 - wind_band(0.06, abs(y))) * step(0.8, x);
		color = leaf_color(v_seed);
		if (!FRONT_FACING) {
			color *= 0.68;
		}
		color = mix(color, color * 0.55, (1.0 - wind_band(0.045, abs(y))) * step(abs(x), 0.8));
		color = mix(color, ink_color.rgb, wind_band(half_width - 0.16, abs(y)) * 0.9);
		alpha = max(inside, stem) * v_alpha;
		color = mix(color, ink_color.rgb, stem * (1.0 - inside));
	} else if (kind == 2) {
		// stone chip: a jagged flat shard
		float angle = atan(p.y, p.x);
		float r = 0.62 + 0.2 * sin(angle * 3.0 + v_seed * 19.0) + 0.12 * sin(angle * 5.0 + v_seed * 7.0);
		float d = length(p);
		float inside = 1.0 - wind_band(r, d);
		color = FRONT_FACING ? stone_light.rgb : stone_dark.rgb;
		color = mix(color, ink_color.rgb, wind_band(r - 0.2, d));
		alpha = inside * v_alpha;
	} else {
		// mote: a glowing speck
		float d = length(p);
		float core = 1.0 - wind_band(0.3, d);
		float halo = (1.0 - wind_band(0.75, d)) * 0.45;
		glow = (mix(mote_color.rgb, vec3(1.0), core) * max(core, halo)) * mote_energy * v_alpha;
	}
	float near = smoothstep(near_fade_from, near_fade_to, length(VERTEX));
	alpha *= near;
	glow *= near;
	ALBEDO = color * alpha + glow;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
