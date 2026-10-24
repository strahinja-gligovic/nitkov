// Shared by the fire shaders: 3D simplex noise, a small fbm, and the toon
// fire palette. Heat maps onto hard-edged bands, from an ink-dark rim through
// red, orange and yellow to a white-hot core, so every fire effect cools the
// same way and reads as one element.

vec3 fire_mod289_3(vec3 x) {
	return x - floor(x * (1.0 / 289.0)) * 289.0;
}

vec4 fire_mod289_4(vec4 x) {
	return x - floor(x * (1.0 / 289.0)) * 289.0;
}

vec4 fire_permute(vec4 x) {
	return fire_mod289_4(((x * 34.0) + 10.0) * x);
}

// 3D simplex noise (after Ashima Arts and Stefan Gustavson, MIT), about -1..1.
float fire_noise(vec3 v) {
	const vec2 C = vec2(1.0 / 6.0, 1.0 / 3.0);
	vec3 i = floor(v + dot(v, C.yyy));
	vec3 x0 = v - i + dot(i, C.xxx);
	vec3 g = step(x0.yzx, x0.xyz);
	vec3 l = 1.0 - g;
	vec3 i1 = min(g.xyz, l.zxy);
	vec3 i2 = max(g.xyz, l.zxy);
	vec3 x1 = x0 - i1 + C.xxx;
	vec3 x2 = x0 - i2 + C.yyy;
	vec3 x3 = x0 - 0.5;
	i = fire_mod289_3(i);
	vec4 p = fire_permute(fire_permute(fire_permute(
			i.z + vec4(0.0, i1.z, i2.z, 1.0))
			+ i.y + vec4(0.0, i1.y, i2.y, 1.0))
			+ i.x + vec4(0.0, i1.x, i2.x, 1.0));
	vec4 j = p - 49.0 * floor(p * (1.0 / 49.0));
	vec4 gx_ = floor(j * (1.0 / 7.0));
	vec4 gy_ = floor(j - 7.0 * gx_);
	vec4 gx = (gx_ * 2.0 + 0.5) / 7.0 - 1.0;
	vec4 gy = (gy_ * 2.0 + 0.5) / 7.0 - 1.0;
	vec4 h = 1.0 - abs(gx) - abs(gy);
	vec4 b0 = vec4(gx.xy, gy.xy);
	vec4 b1 = vec4(gx.zw, gy.zw);
	vec4 s0 = floor(b0) * 2.0 + 1.0;
	vec4 s1 = floor(b1) * 2.0 + 1.0;
	vec4 sh = -step(h, vec4(0.0));
	vec4 a0 = b0.xzyw + s0.xzyw * sh.xxyy;
	vec4 a1 = b1.xzyw + s1.xzyw * sh.zzww;
	vec3 g0 = vec3(a0.xy, h.x);
	vec3 g1 = vec3(a0.zw, h.y);
	vec3 g2 = vec3(a1.xy, h.z);
	vec3 g3 = vec3(a1.zw, h.w);
	vec4 norm = inversesqrt(vec4(dot(g0, g0), dot(g1, g1), dot(g2, g2), dot(g3, g3)));
	g0 *= norm.x;
	g1 *= norm.y;
	g2 *= norm.z;
	g3 *= norm.w;
	vec4 m = max(0.5 - vec4(dot(x0, x0), dot(x1, x1), dot(x2, x2), dot(x3, x3)), 0.0);
	m = m * m;
	return 105.0 * dot(m * m, vec4(dot(g0, x0), dot(g1, x1), dot(g2, x2), dot(g3, x3)));
}

// Two octaves: enough boil for flames that are drawn in hard bands anyway.
float fire_fbm(vec3 p) {
	return fire_noise(p) * 0.68 + fire_noise(p * 2.13 + vec3(17.1, 3.3, 8.7)) * 0.32;
}

// The palette, in linear HDR. Bloom starts at 1.1, so only yellow and the
// core glow; orange and red stay crisp.
const vec3 FIRE_INK = vec3(0.075, 0.008, 0.016);
const vec3 FIRE_RED = vec3(0.58, 0.035, 0.012);
const vec3 FIRE_ORANGE = vec3(1.05, 0.25, 0.025);
const vec3 FIRE_YELLOW = vec3(1.3, 0.74, 0.11);
const vec3 FIRE_CORE = vec3(1.95, 1.72, 1.08);

// Band thresholds on the heat scale (below FIRE_T_INK is not fire at all).
const float FIRE_T_INK = 0.08;
const float FIRE_T_RED = 0.22;
const float FIRE_T_ORANGE = 0.42;
const float FIRE_T_YELLOW = 0.63;
const float FIRE_T_CORE = 0.83;

// Stepped fire color for `heat`; `aa` softens the band edges by about a
// pixel (pass fwidth(heat)).
vec3 fire_ramp(float heat, float aa) {
	vec3 c = FIRE_INK;
	c = mix(c, FIRE_RED, smoothstep(FIRE_T_RED - aa, FIRE_T_RED + aa, heat));
	c = mix(c, FIRE_ORANGE, smoothstep(FIRE_T_ORANGE - aa, FIRE_T_ORANGE + aa, heat));
	c = mix(c, FIRE_YELLOW, smoothstep(FIRE_T_YELLOW - aa, FIRE_T_YELLOW + aa, heat));
	c = mix(c, FIRE_CORE, smoothstep(FIRE_T_CORE - aa, FIRE_T_CORE + aa, heat));
	return c;
}
