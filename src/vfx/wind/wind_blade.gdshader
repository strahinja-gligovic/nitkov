shader_type spatial;
// Wind Slash's crescent: a thin curved shell of air. UV.x runs tip to tip,
// UV.y from the lower rim (0) over the leading edge (0.5) to the upper rim
// (1). Hard cel bands from the front back: a white-hot cutting edge, a
// saturated mint band, then a clear body that bends what's behind it, laced
// with streaks that flow out toward the tips, and a dark ink rim.
// Premultiplied alpha: the glows add, the ink and the bent background cover.
render_mode unshaded, blend_premul_alpha, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

#include "res://src/vfx/wind/wind_common.gdshaderinc"

uniform vec4 edge_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 glow_color : source_color = vec4(0.38, 1.0, 0.66, 1.0);
uniform vec4 body_color : source_color = vec4(0.2, 0.75, 0.55, 1.0);
uniform vec4 ink_color : source_color = vec4(0.02, 0.15, 0.17, 1.0);
uniform float edge_energy = 2.4;
uniform float glow_energy = 0.95;
uniform float streak_energy = 1.05;
uniform float body_alpha = 0.2;
uniform float ink_alpha = 0.55;
uniform float distortion = 0.012;
// The blade melts away this close to the camera (metres), so a slash that
// hits you or brushes past doesn't paint a slab across the screen.
uniform float near_fade_from = 0.9;
uniform float near_fade_to = 3.0;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
instance uniform float anim_time = 0.0;
instance uniform float fade = 1.0;
instance uniform float seed = 0.0;

void vertex() {
	// the shell flutters a little, more in the middle than at the sharp tips
	float c = UV.x * 2.0 - 1.0;
	float s = UV.y * 2.0 - 1.0;
	float flutter = sin(anim_time * 31.0 + c * 7.0 + seed * 6.0) * 0.5 + sin(anim_time * 17.0 - c * 4.0) * 0.5;
	VERTEX += NORMAL * flutter * 0.025 * (1.0 - c * c) * abs(s);
}

void fragment() {
	float c = UV.x * 2.0 - 1.0;
	float lateral = abs(c);
	float s = abs(UV.y * 2.0 - 1.0);
	float shimmer = wind_noise(vec2(c * 5.0 - anim_time * 4.0, s * 3.0 + anim_time * 2.0 + seed));

	float edge = 1.0 - wind_band(0.07 + 0.03 * shimmer, s);
	float glow = (1.0 - wind_band(0.24 + 0.05 * shimmer, s)) * (1.0 - edge);
	float rim = wind_band(0.87, s);
	float body = clamp(1.0 - glow - edge, 0.0, 1.0) * (1.0 - rim);

	// streaks: noise stretched along the blade, cut into hard bands and
	// flowing out toward the tips
	float flow = wind_noise(vec2(lateral * 2.2 - anim_time * 3.2, s * 11.0 + seed * 3.0));
	float flow2 = wind_noise(vec2(lateral * 3.1 - anim_time * 4.5 + 7.0, s * 17.0 - seed));
	float streak = max(wind_band(0.66, flow), wind_band(0.72, flow2) * 0.7) * body;

	float tip_fade = 1.0 - smoothstep(0.85, 1.0, lateral);
	float f = clamp(fade, 0.0, 1.0) * smoothstep(near_fade_from, near_fade_to, length(VERTEX));

	// layers, bottom to top: bent background, mint tint, ink rim, then glows
	float a_bg = 0.85 * (body + glow) * f;
	vec2 haze = vec2(wind_noise(vec2(c * 7.0 + anim_time * 6.0, s * 5.0)), wind_noise(vec2(s * 6.0 - anim_time * 5.0, c * 6.0))) - 0.5;
	vec2 bend = (NORMAL.xy * 0.5 + haze) * distortion * 2.0;
	vec3 color = texture(screen_tex, SCREEN_UV + bend).rgb * a_bg;
	float alpha = a_bg;
	float a_tint = body_alpha * (0.6 + 0.8 * shimmer) * body * f;
	color = body_color.rgb * a_tint + color * (1.0 - a_tint);
	alpha = a_tint + alpha * (1.0 - a_tint);
	float a_ink = ink_alpha * rim * tip_fade * f;
	color = ink_color.rgb * a_ink + color * (1.0 - a_ink);
	alpha = a_ink + alpha * (1.0 - a_ink);

	vec3 add = edge_color.rgb * edge * edge_energy;
	add += glow_color.rgb * glow * glow_energy * (0.75 + 0.5 * shimmer);
	add += glow_color.rgb * streak * streak_energy;
	color += add * f * mix(0.7, 1.0, tip_fade);

	ALBEDO = color;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
