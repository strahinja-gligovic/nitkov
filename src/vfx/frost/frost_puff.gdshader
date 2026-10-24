shader_type spatial;
// Cold mist: camera-facing puffs with hard-edged tone bands (cel smoke) that
// swell, drift and erode away as they age. Drawn by FrostBits; per instance
// INSTANCE_CUSTOM = (age 0..1, seed, opacity, violet).
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 core_color : source_color = vec4(0.93, 0.99, 1.0, 1.0);
uniform vec4 mid_color : source_color = vec4(0.62, 0.87, 1.0, 1.0);
uniform vec4 rim_color : source_color = vec4(0.3, 0.52, 0.88, 1.0);
uniform vec4 violet_color : source_color = vec4(0.8, 0.68, 1.0, 1.0);
uniform float energy = 1.0;
uniform float opacity = 1.0;

varying vec4 v_data;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
			mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * scale.x, INV_VIEW_MATRIX[1] * scale.y,
			INV_VIEW_MATRIX[2] * scale.z, MODEL_MATRIX[3]);
	v_data = INSTANCE_CUSTOM;
}

void fragment() {
	float age = v_data.x;
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	vec2 q = p * 1.7 + vec2(v_data.y * 13.1, v_data.y * 7.7 - age * 0.9);
	float n = noise(q) * 0.65 + noise(q * 2.3 + 4.1) * 0.35;
	float density = (1.0 - r) * 1.35 + (n - 0.5) * 0.85;
	float d = density - age * age * 1.1 - 0.04;
	float aa = fwidth(d) + 1e-4;
	float body = smoothstep(-aa, aa, d);
	if (body <= 0.0) {
		discard;
	}
	float core = smoothstep(0.42 - aa, 0.42 + aa, d);
	float mid = smoothstep(0.16 - aa, 0.16 + aa, d);
	vec3 color = mix(mix(rim_color.rgb, mid_color.rgb, mid), core_color.rgb, core);
	float alpha = mix(mix(0.26, 0.4, mid), 0.55, core);
	color = mix(color, color * violet_color.rgb * 1.15, v_data.w);
	ALBEDO = color * energy;
	ALPHA = alpha * body * v_data.z * opacity;
}
