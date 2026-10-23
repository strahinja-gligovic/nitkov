// Faceted cel-shaded ice, shared by every frost crystal: the Ice Spike,
// flying shards, crystal growths and the Nova's spikes. Unshaded on purpose:
// each flat facet picks one of three hard tones from a key light fixed in
// view space, so a spinning crystal flickers facet by facet. Facet edges and
// facets seen edge-on catch a bright rim, an optional core glows through the
// ice with real parallax (where the view ray passes closest to the crystal's
// axis), and the crystal can flash white or crumble away with a glowing edge.
// Per-edge barycentrics come in COLOR (see FrostKit). MultiMesh users pass
// (dissolve, flash, violet, seed) per instance in INSTANCE_CUSTOM; single
// meshes use the instance uniforms. Define GLASS to draw it after the ink
// outline pass (small bits that ink would turn into black specks).

uniform vec4 deep_color : source_color = vec4(0.1, 0.27, 0.62, 1.0);
uniform vec4 mid_color : source_color = vec4(0.27, 0.64, 1.0, 1.0);
uniform vec4 pale_color : source_color = vec4(0.64, 0.89, 1.0, 1.0);
uniform vec4 edge_color : source_color = vec4(0.8, 1.0, 1.0, 1.0);
uniform vec4 violet_deep : source_color = vec4(0.33, 0.17, 0.64, 1.0);
uniform vec4 violet_mid : source_color = vec4(0.66, 0.5, 1.0, 1.0);
uniform vec4 violet_pale : source_color = vec4(0.93, 0.86, 1.0, 1.0);
uniform float energy = 1.0;
// Facet edge lines, in barycentric units.
uniform float edge_width = 0.05;
uniform float edge_energy = 1.4;
uniform float rim_energy = 1.35;
// The inner glow runs along core_axis through the local origin, between
// core_span.x and core_span.y along it (0 energy = no core).
uniform float core_energy = 0.0;
uniform vec3 core_axis = vec3(0.0, 0.0, 1.0);
uniform float core_radius = 0.05;
uniform vec2 core_span = vec2(-0.5, 0.3);
uniform float dissolve_scale = 9.0;
uniform bool use_custom = false;

instance uniform float dissolve = 0.0;
instance uniform float flash = 0.0;
instance uniform float violet = 0.0;
instance uniform float seed = 0.0;

varying vec3 v_obj;
varying vec3 v_cam;
varying vec4 v_data;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash13(i), hash13(i + vec3(1.0, 0.0, 0.0)), u.x),
			mix(hash13(i + vec3(0.0, 1.0, 0.0)), hash13(i + vec3(1.0, 1.0, 0.0)), u.x), u.y),
			mix(mix(hash13(i + vec3(0.0, 0.0, 1.0)), hash13(i + vec3(1.0, 0.0, 1.0)), u.x),
			mix(hash13(i + vec3(0.0, 1.0, 1.0)), hash13(i + vec3(1.0, 1.0, 1.0)), u.x), u.y), u.z);
}

void vertex() {
	v_obj = VERTEX;
	v_cam = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	v_data = use_custom ? INSTANCE_CUSTOM : vec4(dissolve, flash, violet, seed);
}

void fragment() {
	// crumbling away: a noise threshold with a glowing edge
	float grain = noise3(v_obj * dissolve_scale + v_data.w * 17.31);
	if (grain < v_data.x) {
		discard;
	}
	float burn = v_data.x > 0.0 ? 1.0 - smoothstep(0.0, 0.09, grain - v_data.x) : 0.0;

	vec3 deep = mix(deep_color.rgb, violet_deep.rgb, v_data.z);
	vec3 mid = mix(mid_color.rgb, violet_mid.rgb, v_data.z);
	vec3 pale = mix(pale_color.rgb, violet_pale.rgb, v_data.z);
	vec3 rim = mix(edge_color.rgb, violet_pale.rgb, v_data.z);

	vec3 n = normalize(NORMAL);
	float lit = dot(n, normalize(vec3(-0.45, 0.78, 0.43)));
	vec3 color = lit > 0.58 ? pale : (lit > -0.15 ? mid : deep);
	// facets seen edge-on catch the rim light
	if (abs(dot(n, VIEW)) < 0.26) {
		color = rim * rim_energy;
	}
	// bright facet edges
	float m = min(COLOR.r, min(COLOR.g, COLOR.b));
	float w = fwidth(m);
	float edge = 1.0 - smoothstep(edge_width - w, edge_width + w, m);
	color = mix(color, rim * edge_energy, edge * 0.8);

	// the core seen through the ice: the view ray's closest approach to the axis
	if (core_energy > 0.0) {
		vec3 d = normalize(v_obj - v_cam);
		vec3 a = normalize(core_axis);
		float b = dot(d, a);
		float dd = max(1.0 - b * b, 1e-4);
		float dw = dot(d, v_obj);
		float aw = dot(a, v_obj);
		float t = (b * aw - dw) / dd;
		float s = aw + b * t;
		float dist = length(v_obj + d * t - a * s);
		float along = clamp((s - core_span.x) / (core_span.y - core_span.x), 0.0, 1.0);
		float radius = core_radius * smoothstep(0.0, 0.45, along) * (1.0 - smoothstep(0.8, 1.0, along));
		float aa = fwidth(dist) + 1e-4;
		float ahead = step(0.0, t);
		float inner = (1.0 - smoothstep(radius * 0.55 - aa, radius * 0.55 + aa, dist)) * ahead;
		float halo = (1.0 - smoothstep(radius - aa, radius + aa, dist)) * ahead;
		color = mix(color, mix(mid, rim, 0.55) * 1.35, halo * 0.7);
		color = mix(color, rim * core_energy, inner);
	}
	color = mix(color, vec3(1.7), clamp(v_data.y, 0.0, 1.0));
	color = mix(color, rim * 2.4, burn);
	ALBEDO = color * energy;
#ifdef GLASS
	ALPHA = 1.0;
#endif
}
