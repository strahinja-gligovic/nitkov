shader_type spatial;
// A spray of speed lines flying out from where they start (bursts, splashes,
// gust cones, a slash unravelling). Each line is a quad that faces the
// camera around its direction; `progress` (0..1) plays the whole spray: the
// lines shoot out with an ease-out, stretch, then shrink away. Per vertex:
// VERTEX is where the line starts, NORMAL where it flies, UV.x runs head (0)
// to tail (1), UV.y across, UV2 = (metres it travels, random), COLOR.r/g/b
// scale its length and width and delay its start (see WindMeshes.spray).
render_mode unshaded, blend_premul_alpha, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled, skip_vertex_transform;

#include "res://src/vfx/wind/wind_common.gdshaderinc"

uniform vec4 core_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 edge_color : source_color = vec4(0.5, 1.0, 0.72, 1.0);
uniform float energy = 1.8;
uniform float line_length = 1.2;
uniform float line_width = 0.06;
// The latest a line starts, as a fraction of the spray's life.
uniform float delay_spread = 0.25;
uniform float ease_power = 3.0;
// How much a line curls sideways as it flies (a swirl), in metres.
uniform float curl = 0.0;
// Fades out this close to the camera (metres), so a splash on you or a
// burst around you doesn't smear bars across the screen.
uniform float near_fade_from = 0.5;
uniform float near_fade_to = 2.0;
instance uniform float progress = 0.0;
instance uniform float fade = 1.0;
instance uniform float reach = 1.0;

varying float v_life;
varying float v_random;

void vertex() {
	float delay = COLOR.b * delay_spread;
	float t = clamp((progress - delay) / max(1.0 - delay, 0.001), 0.0, 1.0);
	float eased = 1.0 - pow(1.0 - t, ease_power);
	vec3 dir = NORMAL;
	vec3 side_dir = normalize(cross(dir, abs(dir.y) < 0.95 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
	float travel = UV2.x * reach;
	vec3 head = VERTEX + dir * travel * eased + side_dir * curl * eased * eased * (UV2.y - 0.5) * 2.0;
	// out to full length fast, then shrink to nothing as the line slows
	float len = line_length * reach * mix(0.5, 1.5, COLOR.r) * (1.0 - t) * min(t * 7.0, 1.0);
	vec3 tail = head - dir * len;
	vec3 point = mix(head, tail, UV.x);
	vec3 p = (MODELVIEW_MATRIX * vec4(point, 1.0)).xyz;
	vec3 d = (MODELVIEW_MATRIX * vec4(dir, 0.0)).xyz;
	float w = line_width * mix(0.6, 1.4, COLOR.g) * mix(1.0, 0.3, UV.x) * (1.0 - 0.6 * t);
	VERTEX = wind_face_camera(p, d, (UV.y - 0.5) * w);
	v_life = t;
	v_random = UV2.y;
}

void fragment() {
	float across = abs(UV.y * 2.0 - 1.0);
	float body = 1.0 - wind_band(0.8, across);
	float core = 1.0 - wind_band(0.38, across);
	float a = body * (1.0 - UV.x * 0.7) * fade * smoothstep(near_fade_from, near_fade_to, length(VERTEX)) * step(0.001, v_life) * (1.0 - v_life * v_life);
	vec3 color = mix(edge_color.rgb, core_color.rgb, core * (1.0 - v_life * 0.6)) * energy;
	ALBEDO = color * clamp(a, 0.0, 1.0);
	ALPHA = 0.0;
}
