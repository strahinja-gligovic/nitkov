shader_type spatial;
// A camera-facing electric flash (LightningFlare): a white-hot core inside a
// jagged star of uneven spikes and a faint halo, in hard bands. `progress`
// (0..1 over its life) pops it out and burns it down. The quad is pulled
// toward the camera so a flash on a wall or the floor doesn't clip into it.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, skip_vertex_transform;

instance uniform vec4 tint : source_color = vec4(1.0, 0.86, 0.3, 1.0);
instance uniform float progress = 0.0;
instance uniform float seed = 0.0;
instance uniform float strength = 1.0;
uniform vec4 core_color : source_color = vec4(1.0, 0.98, 0.9, 1.0);
uniform float spikes = 7.0;
uniform float pull = 0.45;

void vertex() {
	vec3 centre = (VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0)).xyz;
	float size = length(MODEL_MATRIX[0].xyz);
	vec3 toward = normalize(-centre);
	VERTEX = centre + vec3(VERTEX.xy * size, 0.0) + toward * min(pull * size, max(-centre.z - 0.2, 0.0));
	NORMAL = vec3(0.0, 0.0, 1.0);
}

float hash(float n) {
	return fract(sin(n * 12.9898 + 4.1414) * 43758.5453);
}

float band(float edge, float x) {
	float w = max(fwidth(x), 1e-4);
	return clamp((edge - x) / w + 0.5, 0.0, 1.0);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float turns = (atan(p.y, p.x) / 6.2831853 + 0.5) * spikes + seed * 3.7;
	float cell = floor(turns);
	float tri = 1.0 - abs(fract(turns) * 2.0 - 1.0);
	float reach = 0.45 + 0.55 * hash(cell + floor(seed * 97.0));
	float t = clamp(progress, 0.0, 1.0);
	float grow = 0.62 + 0.38 * sqrt(t);
	float star = band(mix(0.2, reach, pow(tri, 3.0)) * grow, r);
	float core = band((0.26 - 0.14 * t) * grow, r);
	float halo = band(0.95, r) * (1.0 - r);
	vec3 color = tint.rgb * 0.18 * halo;
	color = mix(color, tint.rgb * 1.7, star);
	color = mix(color, core_color.rgb * 3.2, core);
	float fade = (1.0 - t) * (1.0 - t * 0.5);
	ALBEDO = color * fade * strength;
	ALPHA = 1.0;
}
