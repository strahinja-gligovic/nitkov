shader_type spatial;
// The Wind Spear's burst: a sphere of shoved air that slams out to `radius`
// in the first `grow_time` of its life (ease-out), then drifts a little
// further while it breaks up and fades. A hard white rim and a mint band
// where the shell turns away from the camera, a nearly clear body, and the
// background bent around the rim like a heat shimmer. Runs on a unit
// SphereMesh; `progress` (0..1) plays it.
render_mode unshaded, blend_premul_alpha, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

#include "res://src/vfx/wind/wind_common.gdshaderinc"

uniform vec4 edge_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 band_color : source_color = vec4(0.45, 1.0, 0.7, 1.0);
uniform vec4 body_color : source_color = vec4(0.25, 0.8, 0.6, 1.0);
uniform float edge_energy = 1.9;
uniform float band_energy = 0.9;
uniform float body_alpha = 0.07;
uniform float distortion = 0.035;
// Fraction of its life it takes to reach full size.
uniform float grow_time = 0.44;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
instance uniform float progress = 0.0;
instance uniform float fade = 1.0;
instance uniform float radius = 4.0;
instance uniform float seed = 0.0;

varying float v_t;

void vertex() {
	float t = clamp(progress, 0.0, 1.0);
	float grow = 1.0 - pow(1.0 - clamp(t / grow_time, 0.0, 1.0), 3.0);
	float drift = 1.0 + 0.12 * max(t - grow_time, 0.0) / (1.0 - grow_time);
	// a lumpy, churning shell rather than a perfect bubble
	float lump = sin(UV.x * TAU * 5.0 + seed * 3.0 + t * 9.0) * sin(UV.y * PI * 4.0 - seed + t * 6.0);
	VERTEX *= radius * mix(0.06, 1.0, grow) * drift * (1.0 + 0.045 * lump);
	v_t = t;
}

void fragment() {
	float t = v_t;
	float rim = 1.0 - abs(dot(NORMAL, VIEW));
	// the rim thins and breaks up as the shell spends itself
	float after = clamp((t - grow_time) / (1.0 - grow_time), 0.0, 1.0);
	float tear = wind_noise(UV * vec2(18.0, 9.0) + seed * 13.0);
	float alive = wind_band(after * 1.1, tear * 0.85 + 0.15);
	// streaks raked along the shell, so the rim reads as rushing air
	float rake = wind_noise(vec2(UV.x * 60.0 + seed * 7.0, UV.y * 3.0 - t * 4.0));
	float edge = wind_band(mix(0.87, 0.97, after), rim) * alive;
	float band = wind_band(mix(0.7, 0.9, after), rim) * (1.0 - edge) * alive * mix(0.45, 1.0, wind_band(0.45, rake));
	float f = clamp(fade, 0.0, 1.0) * (1.0 - after) * (1.0 - after);

	float a_bg = 0.85 * smoothstep(0.35, 0.8, rim) * f;
	vec2 bend = NORMAL.xy * distortion * (1.0 - after);
	vec3 color = texture(screen_tex, SCREEN_UV - bend).rgb * a_bg;
	float alpha = a_bg;
	float a_body = body_alpha * (0.4 + rim) * f;
	color = body_color.rgb * a_body + color * (1.0 - a_body);
	alpha = a_body + alpha * (1.0 - a_body);
	color += (edge_color.rgb * edge * edge_energy + band_color.rgb * band * band_energy) * f;
	ALBEDO = color;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
