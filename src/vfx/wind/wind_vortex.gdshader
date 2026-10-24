shader_type spatial;
// A twisting tube of storm wind (the Wind Spear's shaft, its outer storm
// and the shock cone ahead of its point): helical bands that wind back
// along it as it spins, cut with hard cel edges, dark storm bands between
// the bright ones, a bright rim where the tube turns away from the camera
// and a translucent body. UV.x runs around, UV.y from the front (0) to the
// back (1). Premultiplied alpha: bright bands add, the storm bands cover.
render_mode unshaded, blend_premul_alpha, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

#include "res://src/vfx/wind/wind_common.gdshaderinc"

uniform vec4 band_color : source_color = vec4(0.5, 1.0, 0.72, 1.0);
uniform vec4 hot_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 body_color : source_color = vec4(0.1, 0.42, 0.4, 1.0);
uniform vec4 storm_color : source_color = vec4(0.03, 0.16, 0.18, 1.0);
// Helix strands around the tube and the turns they make along it.
uniform float strands = 3.0;
uniform float twist = 1.5;
// Turns per second the bands wind back.
uniform float speed = 2.5;
uniform float band_fill = 0.32;
uniform float storm_fill = 0.0;
uniform float storm_alpha = 0.6;
uniform float energy = 1.4;
uniform float rim_energy = 0.8;
uniform float body_alpha = 0.2;
// How the tube fades in at the front and out toward the back.
uniform float front_fade = 0.08;
uniform float back_fade = 1.0;
uniform float distortion = 0.0;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
instance uniform float anim_time = 0.0;
instance uniform float fade = 1.0;

void fragment() {
	float facing = abs(dot(NORMAL, VIEW));
	float rim = 1.0 - facing;
	float phase = UV.x * strands - UV.y * twist * strands + anim_time * speed * strands;
	float wobble = wind_noise(vec2(UV.x * 6.0, UV.y * 4.0 - anim_time * 3.0)) * 0.25;
	float band = 1.0 - wind_band(band_fill, fract(phase + wobble));
	float hot = (1.0 - wind_band(band_fill * 0.35, fract(phase + wobble))) * band;
	float storm = storm_fill > 0.0 ? (1.0 - wind_band(storm_fill, fract(phase + wobble + 0.5))) : 0.0;
	float along = (smoothstep(0.0, front_fade, UV.y)) * (1.0 - back_fade * UV.y * UV.y);
	float f = clamp(fade, 0.0, 1.0) * along;

	vec3 color = vec3(0.0);
	float alpha = 0.0;
	if (distortion > 0.0) {
		vec2 bend = NORMAL.xy * distortion * (0.5 + rim);
		float a_bg = 0.75 * f;
		color = texture(screen_tex, SCREEN_UV + bend).rgb * a_bg;
		alpha = a_bg;
	}
	float a_body = body_alpha * (0.5 + rim) * f;
	color = body_color.rgb * a_body + color * (1.0 - a_body);
	alpha = a_body + alpha * (1.0 - a_body);
	float a_storm = storm * storm_alpha * f;
	color = storm_color.rgb * a_storm + color * (1.0 - a_storm);
	alpha = a_storm + alpha * (1.0 - a_storm);
	vec3 add = mix(band_color.rgb, hot_color.rgb, hot) * band * energy;
	add += band_color.rgb * wind_band(0.72, rim) * rim_energy;
	color += add * f;
	ALBEDO = color;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
