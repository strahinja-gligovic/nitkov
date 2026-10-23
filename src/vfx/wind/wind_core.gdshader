shader_type spatial;
// A solid-looking knot of condensed wind (the Wind Spear's point, the burst's
// heart): cel bands by how much the surface faces the camera, white-hot in
// the middle, mint toward the edge and a dark ink silhouette, with bright
// streaks racing back along it. UV.y runs from the front (0) to the back (1)
// on lathed meshes.
render_mode unshaded, blend_premul_alpha, cull_back, depth_draw_never, shadows_disabled, fog_disabled;

#include "res://src/vfx/wind/wind_common.gdshaderinc"

uniform vec4 hot_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 glow_color : source_color = vec4(0.5, 1.0, 0.72, 1.0);
uniform vec4 ink_color : source_color = vec4(0.02, 0.13, 0.15, 1.0);
uniform float hot_energy = 2.8;
uniform float glow_energy = 1.5;
uniform float hot_band = 0.55;
uniform float ink_band = 0.86;
uniform float streak_speed = 6.0;
instance uniform float anim_time = 0.0;
instance uniform float fade = 1.0;
// When played as a one-shot pop (WindOneShot), it fades as this runs to 1.
instance uniform float progress = 0.0;

void fragment() {
	float rim = 1.0 - abs(dot(NORMAL, VIEW));
	float hot = 1.0 - wind_band(hot_band, rim);
	float ink = wind_band(ink_band, rim);
	float streak = wind_band(0.6, wind_noise(vec2(UV.x * 10.0, UV.y * 3.0 - anim_time * streak_speed)));
	float f = clamp(fade, 0.0, 1.0) * (1.0 - progress * progress);
	vec3 add = mix(glow_color.rgb * glow_energy, hot_color.rgb * hot_energy, max(hot, streak * 0.6)) * (1.0 - ink);
	float a_ink = ink * 0.85 * f;
	ALBEDO = ink_color.rgb * a_ink + add * f;
	ALPHA = a_ink;
}
