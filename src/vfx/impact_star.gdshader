shader_type spatial;
// Comic-book impact burst: a spiky star with an ink rim that grows and fades.
// Drawn on a camera-facing quad; `progress` runs 0..1 over its short life.
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.92, 0.6, 1.0);
uniform vec4 ink : source_color = vec4(0.06, 0.03, 0.09, 1.0);
uniform float points = 8.0;
uniform float progress = 0.0;
uniform float energy = 2.5;
uniform float spin = 0.0;

void vertex() {
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			INV_VIEW_MATRIX[0] * scale.x, INV_VIEW_MATRIX[1] * scale.y, INV_VIEW_MATRIX[2] * scale.z, MODEL_MATRIX[3]);
}

float star(vec2 p, float radius) {
	float a = atan(p.y, p.x) + spin;
	float spikes = 0.38 + 0.62 * pow(abs(cos(a * points * 0.5)), 5.0);
	return 1.0 - smoothstep(radius * spikes - 0.03, radius * spikes, length(p));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float grow = 0.45 + 0.55 * sqrt(progress);
	float outer = star(p, grow);
	float inner = star(p, grow * 0.78);
	ALBEDO = mix(ink.rgb, color.rgb * energy, inner);
	ALPHA = outer * (1.0 - smoothstep(0.55, 1.0, progress));
}
