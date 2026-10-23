shader_type spatial;
// Opaque toon puffs, drawn as a MultiMesh: the storm cloud's billows
// (LightningCloud) and the dust a strike kicks up (LightningDust). Lit in
// hard bands like the toon shader, so they pick up ink outlines; each
// instance dissolves through noise with a dark edge (INSTANCE_CUSTOM.x,
// 0 solid .. 1 gone), can glow from inside (.y, lightning in the cloud), and
// has its own noise seed (.z) and shade (.w, 0 dark .. 1 light). A
// `hotspot` (per node: mesh-space x, z and a reach in w) keeps the glow to a
// patch, in hard rings: the storm cloud's body lit round a flash.
render_mode cull_back, specular_disabled;

uniform vec4 dark_color : source_color = vec4(0.11, 0.09, 0.17, 1.0);
uniform vec4 light_color : source_color = vec4(0.27, 0.23, 0.38, 1.0);
uniform vec4 glow_color : source_color = vec4(1.0, 0.9, 0.55, 1.0);
uniform float glow_energy = 2.4;
uniform vec4 edge_ink : source_color = vec4(0.05, 0.02, 0.08, 1.0);
uniform float noise_scale = 2.2;
uniform float lit_threshold = 0.35;
uniform float mid_level = 0.45;
instance uniform vec4 hotspot = vec4(0.0);

varying vec3 v_local;
varying vec3 v_world_normal;
varying float v_dissolve;
varying float v_glow;
varying float v_seed;
varying float v_shade;

void vertex() {
	v_local = VERTEX;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_dissolve = INSTANCE_CUSTOM.x;
	v_glow = INSTANCE_CUSTOM.y;
	v_seed = INSTANCE_CUSTOM.z;
	v_shade = INSTANCE_CUSTOM.w;
}

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x),
			mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
			mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void fragment() {
	vec3 q = v_local * noise_scale + vec3(v_seed * 13.1, v_seed * 7.7, v_seed * 3.3);
	float n = noise(q) * 0.62 + noise(q * 2.3) * 0.38;
	// dissolve: noise below the threshold is gone, with an ink rim at the edge
	float cut = v_dissolve * 1.08 - 0.04;
	if (n < cut) {
		discard;
	}
	float rim = v_dissolve > 0.01 ? 1.0 - step(cut + 0.07, n) : 0.0;
	vec3 base = mix(dark_color.rgb, light_color.rgb, v_shade);
	ALBEDO = mix(base, edge_ink.rgb, rim);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	// lightning inside lights the underside (and a little of the edges);
	// the tops stay dark, so a flash reads as light in the cloud, not a
	// white cloud
	float under = clamp(-v_world_normal.y * 1.1 + 0.2, 0.0, 1.0);
	float rim_view = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float lit = v_glow * (under + rim_view * 0.3);
	if (hotspot.w > 0.0) {
		// a ragged patch, not a disc
		float d = distance(v_local.xz, hotspot.xz) + (noise(v_local * 5.0 + v_seed * 9.0) - 0.5) * hotspot.w * 0.7;
		lit *= 1.0 - smoothstep(0.0, hotspot.w, d);
		lit *= 1.6;
	}
	float glow_band = step(0.35, lit) * 0.4 + step(0.8, lit) * 0.6;
	EMISSION = glow_color.rgb * glow_energy * glow_band * (1.0 - rim);
}

void light() {
	float lit = clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION;
	float tone = step(0.04, lit) * mid_level + step(lit_threshold, lit) * (1.0 - mid_level);
	DIFFUSE_LIGHT += LIGHT_COLOR * tone / 3.14159265;
}
