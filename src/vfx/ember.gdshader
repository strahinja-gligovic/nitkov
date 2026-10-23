shader_type spatial;
// A glowing ember for particle quads: a little diamond spark, billboarded,
// drawn as solid comic color (a hot yellow core in a saturated body, both
// from the particle's color) rather than added light, so it stays orange
// over bright backgrounds instead of washing out to white. It winks as it
// rises, and dims and shrinks with the particle's alpha.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform float energy = 1.35;

varying float wink;

void vertex() {
	// face the camera, keep the particle's own scale
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			INV_VIEW_MATRIX[0] * scale.x, INV_VIEW_MATRIX[1] * scale.y, INV_VIEW_MATRIX[2] * scale.z, MODEL_MATRIX[3]);
	// a per-particle beat from its position, stepped so it flickers, not pulses
	float phase = fract(dot(MODEL_MATRIX[3].xyz, vec3(3.1, 1.7, 2.3)));
	wink = step(0.3, fract(TIME * 9.0 + phase));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = abs(p.x) + abs(p.y);
	// shrinks as it cools
	float size = mix(0.45, 1.0, COLOR.a);
	if (d > size) {
		discard;
	}
	float core = 1.0 - step(size * 0.38, d);
	vec3 hot = mix(COLOR.rgb, vec3(1.0, 0.95, 0.65), 0.6);
	ALBEDO = mix(COLOR.rgb, hot, core * wink) * energy;
	ALPHA = clamp(COLOR.a * 1.4, 0.0, 1.0);
}
