shader_type spatial;
// A cold glow behind the Ice Spike: a camera-facing disc in two hard
// cel bands (a pale core, an ice-blue ring) added over the scene. Seen from
// behind, the player's usual view, it lights the spike's tail so the crystal
// reads as bright ice instead of a small knot of ink.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled, blend_add;

uniform vec4 core_color : source_color = vec4(0.75, 0.95, 1.0, 1.0);
uniform vec4 ring_color : source_color = vec4(0.2, 0.55, 1.0, 1.0);

instance uniform float brightness = 1.0;

// 1 when the spike flies straight at or away from the camera, 0 side-on
varying float v_end_on;

void vertex() {
	vec3 to_camera = normalize(CAMERA_POSITION_WORLD - MODEL_MATRIX[3].xyz);
	v_end_on = abs(dot(normalize(MODEL_MATRIX[2].xyz), to_camera));
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * scale.x, INV_VIEW_MATRIX[1] * scale.y,
			INV_VIEW_MATRIX[2] * scale.z, MODEL_MATRIX[3]);
}

void fragment() {
	float r = length(UV * 2.0 - 1.0);
	float aa = fwidth(r) * 1.5;
	float core = 1.0 - smoothstep(0.32 - aa, 0.32 + aa, r);
	float ring = 1.0 - smoothstep(0.62 - aa, 0.62 + aa, r);
	float haze = (1.0 - smoothstep(0.62, 1.0, r)) * 0.25;
	vec3 color = core_color.rgb * core * 0.9 + ring_color.rgb * (ring - core) * 0.45 + ring_color.rgb * haze * (1.0 - ring);
	// side-on the crystal shows its own bright facets: keep the glow small there
	ALBEDO = color * brightness * mix(0.2, 1.0, smoothstep(0.55, 0.95, v_end_on));
}
