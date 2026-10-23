shader_type spatial;
// A frost flash: a camera-facing six-ray ice star with a white-hot core and
// an ink rim that snaps out in held beats and fades (`progress` 0..1).
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 ink : source_color = vec4(0.05, 0.04, 0.14, 1.0);
// Held beats (~15-20 fps), like hand-drawn effects.
uniform float steps = 4.0;

instance uniform float progress = 0.0;
instance uniform vec4 tint : source_color = vec4(0.35, 0.8, 1.0, 1.0);
instance uniform float spin = 0.0;
instance uniform float energy = 3.0;

void vertex() {
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * scale.x, INV_VIEW_MATRIX[1] * scale.y,
			INV_VIEW_MATRIX[2] * scale.z, MODEL_MATRIX[3]);
}

float star(vec2 p, float size) {
	float a = atan(p.y, p.x) + spin;
	float long_rays = pow(abs(cos(a * 3.0)), 30.0);
	float short_rays = pow(abs(sin(a * 3.0)), 30.0);
	float shape = 0.24 + 0.76 * long_rays + 0.28 * short_rays;
	float r = length(p);
	float aa = fwidth(r) * 1.5;
	return 1.0 - smoothstep(size * shape - aa, size * shape, r);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float beat = floor(progress * steps + 0.5) / steps;
	float grow = 0.55 + 0.45 * sqrt(beat);
	float outer = star(p, grow);
	float inner = star(p, grow * 0.8);
	float r = length(p);
	float core = 1.0 - smoothstep(grow * 0.2, grow * 0.24, r);
	vec3 color = mix(tint.rgb * energy, vec3(energy * 0.85), max(core, 1.0 - beat * 2.0));
	ALBEDO = mix(ink.rgb, color, inner);
	ALPHA = outer * (1.0 - smoothstep(0.5, 1.0, beat));
}
