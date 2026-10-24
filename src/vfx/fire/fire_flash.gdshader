shader_type spatial;
// The white-hot flash of a release or an explosion: a camera-facing burst of
// flame rays around a blinding core, with an ink rim. It lives only two to
// four frames; `progress` runs 0..1 over that.
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

#include "res://src/vfx/fire/fire_noise.gdshaderinc"

instance uniform float progress = 0.0;
instance uniform float seed = 0.0;
uniform float rays = 9.0;

void vertex() {
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			INV_VIEW_MATRIX[0] * scale.x, INV_VIEW_MATRIX[1] * scale.y, INV_VIEW_MATRIX[2] * scale.z, MODEL_MATRIX[3]);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x) + seed * 6.2831;
	// jagged rays, each a different length
	float spikes = pow(abs(cos(a * rays * 0.5)), 3.0);
	float jag = fire_noise(vec3(cos(a) * 1.7, sin(a) * 1.7, seed * 9.0)) * 0.5 + 0.5;
	float grow = 0.55 + 0.45 * sqrt(progress);
	float reach = grow * (0.42 + 0.58 * spikes * (0.5 + 0.5 * jag));
	float inside = reach - r;
	float h = 1.25 - r * 0.9 - progress * 0.45;
	float aa = max(fwidth(h), 0.002);
	float edge_aa = max(fwidth(inside), 0.002);
	if (inside < 0.0) {
		discard;
	}
	vec3 color = fire_ramp(h, aa);
	color = mix(FIRE_INK, color, smoothstep(0.035, 0.035 + edge_aa, inside));
	ALBEDO = color;
	ALPHA = 1.0 - smoothstep(0.6, 1.0, progress);
}
