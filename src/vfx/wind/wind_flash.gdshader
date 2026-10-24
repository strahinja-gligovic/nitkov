shader_type spatial;
// Wind's flash: a pinwheel star whose spikes are bent by a swirl, white-hot
// in the middle with mint spike tips and an ink rim. It pops to full size
// and is gone within a few frames. Drawn on a camera-facing quad;
// `progress` (0..1) plays it, held in beats like a hand-drawn effect. The
// quad is pulled toward the camera so a wall it lands on doesn't cut it.
render_mode unshaded, blend_premul_alpha, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled, skip_vertex_transform;

#include "res://src/vfx/wind/wind_common.gdshaderinc"

uniform vec4 hot_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 tip_color : source_color = vec4(0.5, 1.0, 0.72, 1.0);
uniform vec4 ink_color : source_color = vec4(0.02, 0.13, 0.15, 1.0);
uniform float energy = 2.2;
uniform float spikes = 6.0;
uniform float swirl = 2.2;
uniform float steps = 4.0;
// How far toward the camera the quad is pulled, in quad sizes.
uniform float pull = 0.5;
instance uniform float progress = 0.0;
instance uniform float spin = 0.0;

void vertex() {
	float size = length(MODEL_MATRIX[0].xyz);
	vec3 center = (VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0)).xyz;
	vec3 toward = -normalize(center);
	VERTEX = center + vec3(VERTEX.xy * size, 0.0) + toward * min(pull * size, max(-center.z - 0.3, 0.0));
}

float shape(vec2 p, float size) {
	float r = length(p);
	float a = atan(p.y, p.x) + spin + r * swirl;
	float spike = pow(abs(cos(a * spikes * 0.5)), 6.0);
	float reach = size * (0.32 + 0.68 * spike);
	return 1.0 - wind_band(reach, r);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float beat = floor(clamp(progress, 0.0, 1.0) * steps + 0.5) / steps;
	float size = 0.55 + 0.45 * sqrt(beat);
	float outer = shape(p, size);
	float inner = shape(p, size * 0.8);
	float hot = 1.0 - wind_band(size * 0.3, length(p));
	float gone = 1.0 - smoothstep(0.5, 1.0, beat);
	vec3 glow = mix(tip_color.rgb, hot_color.rgb, hot) * energy;
	float a_ink = (outer - inner) * 0.9 * gone;
	ALBEDO = ink_color.rgb * a_ink + glow * inner * gone;
	ALPHA = clamp(a_ink, 0.0, 1.0);
}
