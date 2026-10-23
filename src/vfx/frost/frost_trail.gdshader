shader_type spatial;
// The Ice Spike's frost-mist streak, a camera-facing ribbon built by
// FrostTrail. Per vertex: NORMAL is the trail's direction there, UV.x the
// sample's age (0 new .. 1 gone), UV.y side to side, UV2 = (half width,
// metres along the path). A thin bright contrail right behind the spike;
// around it banded mist that widens, thins and tears into wisps with age.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 core_color : source_color = vec4(0.88, 1.0, 1.0, 1.0);
uniform vec4 mist_color : source_color = vec4(0.66, 0.9, 1.0, 1.0);
uniform vec4 rim_color : source_color = vec4(0.36, 0.64, 0.98, 1.0);
uniform float opacity = 1.0;

varying float v_path;

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
	vec3 to_camera = normalize(CAMERA_POSITION_WORLD - VERTEX);
	vec3 side = cross(NORMAL, to_camera);
	side = length(side) > 1e-4 ? normalize(side) : vec3(0.0, 1.0, 0.0);
	VERTEX += side * (UV.y * 2.0 - 1.0) * UV2.x;
	v_path = UV2.y;
}

void fragment() {
	float age = clamp(UV.x, 0.0, 1.0);
	float across = abs(UV.y * 2.0 - 1.0);
	float n = noise(vec2(v_path * 2.3, UV.y * 2.6)) * 0.6 + noise(vec2(v_path * 5.4 + 9.0, UV.y * 5.2)) * 0.4;
	float d = (1.0 - across * across) * pow(1.0 - age, 1.4) + (n - 0.5) * (0.7 + age * 0.6) - 0.16 - age * 0.22;
	float aa = fwidth(d) + 1e-4;
	float body = smoothstep(-aa, aa, d);
	float inner = smoothstep(0.32 - aa, 0.32 + aa, d);
	vec3 color = mix(rim_color.rgb, mist_color.rgb, inner);
	float alpha = body * mix(0.2, 0.4, inner);
	// the contrail: a thin hot line right behind the spike
	float contrail = (1.0 - smoothstep(0.08, 0.15, across)) * (1.0 - smoothstep(0.04, 0.28, age));
	color = mix(color, core_color.rgb * 1.6, contrail);
	alpha = max(alpha, contrail * 0.85);
	ALBEDO = color;
	ALPHA = alpha * opacity;
}
