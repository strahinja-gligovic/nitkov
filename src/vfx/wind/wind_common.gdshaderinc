// Shared helpers for the wind shaders: a hash, value noise and a crisp
// antialiased step for hard cel bands.

float wind_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float wind_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = wind_hash(i);
	float b = wind_hash(i + vec2(1.0, 0.0));
	float c = wind_hash(i + vec2(0.0, 1.0));
	float d = wind_hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// 0 below `edge`, 1 above, with a one-pixel ramp so hard bands don't alias.
float wind_band(float edge, float x) {
	float w = max(fwidth(x), 0.0001);
	return smoothstep(edge - w, edge + w, x);
}

// Expands a line point sideways so its ribbon faces the camera around the
// line's own direction. `p` and `dir` are in view space.
vec3 wind_face_camera(vec3 p, vec3 dir, float offset) {
	vec3 side = cross(dir, p);
	float len = length(side);
	side = len > 0.00001 ? side / len : vec3(1.0, 0.0, 0.0);
	return p + side * offset;
}
