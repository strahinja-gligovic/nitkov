shader_type spatial;
// The scoured ground a wind burst leaves: dark grooves and pale dust swept
// out in streaks from where it hit, with a broken ring of dust piled at the
// edge, all fading out. Drawn on a flat quad on the floor (UV centre = the
// burst); it holds, then fades out as `progress` runs 0..1.
render_mode unshaded, blend_premul_alpha, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

#include "res://src/vfx/wind/wind_common.gdshaderinc"

uniform vec4 dust_color : source_color = vec4(0.74, 0.66, 0.7, 1.0);
uniform vec4 groove_color : source_color = vec4(0.12, 0.08, 0.15, 1.0);
uniform float groove_alpha = 0.32;
uniform float dust_alpha = 0.3;
// The mark softens right under the camera, where it would fill the bottom
// of the screen for someone standing in it.
uniform float near_fade_from = 1.0;
uniform float near_fade_to = 4.0;
instance uniform float progress = 0.0;
instance uniform float seed = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x) / TAU + 0.5;
	float rays = wind_noise(vec2(a * 46.0 + seed * 10.0, r * 2.0));
	float rays2 = wind_noise(vec2(a * 97.0 - seed * 7.0, r * 3.0 + 3.0));
	// streaks start a little out from the centre and thin out toward the edge
	float zone = smoothstep(0.06, 0.22, r) * (1.0 - smoothstep(0.55, 0.92, r));
	float groove = wind_band(0.69, rays) * zone;
	float dust = wind_band(0.66, rays2) * zone * (1.0 - groove);
	float pile = wind_band(0.8, r) * (1.0 - wind_band(0.96, r)) * wind_band(0.45, wind_noise(vec2(a * 31.0, seed * 5.0)));
	float f = smoothstep(0.0, 0.03, progress) * (1.0 - smoothstep(0.12, 1.0, progress));
	f *= mix(0.35, 1.0, smoothstep(near_fade_from, near_fade_to, length(VERTEX)));
	float a_groove = groove * groove_alpha * f;
	float a_dust = (dust * dust_alpha + pile * (dust_alpha + 0.15)) * f;
	vec3 color = groove_color.rgb * a_groove;
	float alpha = a_groove;
	color = dust_color.rgb * a_dust + color * (1.0 - a_dust);
	alpha = a_dust + alpha * (1.0 - a_dust);
	ALBEDO = color;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
