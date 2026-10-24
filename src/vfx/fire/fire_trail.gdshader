shader_type spatial;
// The Firebolt's flame trail: a camera-facing ribbon rebuilt every frame from
// the bolt's recent path. Each vertex carries its path point in world space
// (VERTEX, with the mesh at the world origin), the path direction (NORMAL),
// the distance along the path (UV.x, so the flames stay put in the air), the
// side (UV.y, -1..1) and (age 0 head..1 tail, half width) in UV2. Hot flame
// at the head cools through the toon bands into a dark smoke wisp.
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

#include "res://src/vfx/fire/fire_noise.gdshaderinc"

uniform vec4 smoke_color : source_color = vec4(0.2, 0.15, 0.2, 1.0);
instance uniform float seed = 0.0;
// 1 while flying; runs to 0 after impact, cooling the whole trail to smoke.
instance uniform float fade = 1.0;

varying float v_age;
varying float v_dist;
varying float v_side;

void vertex() {
	vec3 to_cam = INV_VIEW_MATRIX[3].xyz - VERTEX;
	vec3 side = cross(NORMAL, to_cam);
	float len = length(side);
	side = len > 0.0001 ? side / len : INV_VIEW_MATRIX[0].xyz;
	VERTEX += side * UV.y * UV2.y;
	v_age = UV2.x;
	v_dist = UV.x;
	v_side = UV.y;
}

void fragment() {
	float t = TIME;
	float across = abs(v_side);
	float n = fire_fbm(vec3(v_dist * 1.7, v_side * 0.8, t * 3.0 + seed));
	float wisp = fire_noise(vec3(v_dist * 0.9 - t * 0.6, v_side * 0.5 + seed, t * 1.1));
	// substance: a soft-edged core that frays with age
	float body = 1.0 - across + n * 0.28 * (0.4 + v_age) - v_age * 0.2;
	float cool = (1.0 - fade) * 0.9;
	float h = (1.0 - across * 0.85) * (1.15 - v_age * 1.25) + n * 0.32 - cool;
	float aa = max(fwidth(h), 0.002);
	if (body < 0.12) {
		discard;
	}
	vec3 color = fire_ramp(h, aa);
	float alpha = 1.0;
	if (h < FIRE_T_INK) {
		// burnt out: a thin wisp of smoke
		color = smoke_color.rgb;
		alpha = 0.55 * smoothstep(-0.25, 0.4, wisp + 0.3 - v_age * 0.4);
	}
	alpha *= smoothstep(0.12, 0.3, body) * (1.0 - smoothstep(0.82, 1.0, v_age));
	ALBEDO = color;
	ALPHA = clamp(alpha * clamp(fade * 1.5, 0.0, 1.0), 0.0, 1.0);
}
