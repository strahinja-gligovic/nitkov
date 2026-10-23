// Shared body of the toon shaders (toon.gdshader culls back faces,
// toon_double_sided.gdshader draws both, for open models like clothing).
// Comic toon look: light quantized into bands, with screen-space hatching
// along the light/shadow edges, plus a warm rim. Greybox surfaces can add a
// world-space grid and grunge. Hit flashes and heavy-attack tells are
// driven from code via flash_amount and glow_energy.

uniform vec4 albedo : source_color = vec4(0.8, 0.8, 0.8, 1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_texture = false;

// Three tones: shadow, mid and lit. Light above lit_threshold is fully lit,
// above mid_threshold it's mid_level, below that only ambient light remains.
uniform float lit_threshold : hint_range(0.0, 1.0) = 0.42;
uniform float mid_threshold : hint_range(0.0, 1.0) = 0.06;
uniform float mid_level : hint_range(0.0, 1.0) = 0.5;
uniform float band_softness : hint_range(0.005, 0.3) = 0.03;
// Diagonal hatch lines that break up band edges, in pixels between lines.
uniform float hatch_strength : hint_range(0.0, 1.0) = 0.35;
uniform float hatch_spacing = 6.0;

uniform vec4 rim_color : source_color = vec4(1.0, 0.78, 0.55, 1.0);
uniform float rim_strength : hint_range(0.0, 2.0) = 0.22;

uniform bool world_grid = false;
uniform float grid_size = 2.0;
uniform float grid_line = 0.035;
uniform float grunge_strength : hint_range(0.0, 1.0) = 0.0;

uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 glow_color : source_color = vec4(1.0, 0.45, 0.1, 1.0);
uniform float glow_energy = 0.0;

varying vec3 v_world_pos;
varying vec3 v_world_normal;

// Sine-free hash (Dave Hoskins): stays stable at large world coordinates.
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// The two world axes perpendicular to the dominant normal, for box mapping.
vec2 box_uv(vec3 pos, vec3 normal) {
	vec3 n = abs(normal);
	if (n.y > n.x && n.y > n.z) {
		return pos.xz;
	}
	return n.x > n.z ? pos.zy : pos.xy;
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec4 color = albedo;
	if (use_texture) {
		color *= texture(albedo_texture, UV);
	}
	vec2 p = box_uv(v_world_pos, v_world_normal);
	if (world_grid) {
		vec2 g = abs(fract(p / grid_size - 0.5) - 0.5) * grid_size;
		float line = 1.0 - smoothstep(grid_line, grid_line + 0.025, min(g.x, g.y));
		color.rgb *= 1.0 - line * 0.4;
	}
	if (grunge_strength > 0.0) {
		float g = value_noise(p * 0.6) * 0.6 + value_noise(p * 2.7) * 0.4;
		color.rgb *= 1.0 - grunge_strength * smoothstep(0.42, 0.85, g);
	}
	color.rgb = mix(color.rgb, flash_color.rgb, flash_amount);
	ALBEDO = color.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	EMISSION = rim_color.rgb * rim * rim_strength
			+ glow_color.rgb * glow_energy
			+ flash_color.rgb * flash_amount * 0.5;
}

void light() {
	float lit = clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION;
	float hatch = fract((FRAGCOORD.x + FRAGCOORD.y) / hatch_spacing);
	lit = clamp(lit + (hatch - 0.5) * hatch_strength * 0.2, 0.0, 1.0);
	float to_mid = smoothstep(mid_threshold - band_softness, mid_threshold + band_softness, lit);
	float to_lit = smoothstep(lit_threshold - band_softness, lit_threshold + band_softness, lit);
	float tone = to_mid * mid_level + to_lit * (1.0 - mid_level);
	DIFFUSE_LIGHT += LIGHT_COLOR * tone / PI;
}
