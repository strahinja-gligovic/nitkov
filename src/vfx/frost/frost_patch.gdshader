shader_type spatial;
// Frost on the ground or a wall, as a screen-space decal: a unit box whose
// local +Y is the surface normal. Each pixel rebuilds the surface behind it
// from the depth buffer and keeps it only if it lies inside the box and faces
// along +Y. There it paints frost: a crisp bright rim (never past radius_m),
// patchy rime, crystalline cracks and glitter, spreading out to `grow` and
// melting into holes as `melt` rises.
render_mode unshaded, cull_front, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D normal_texture : hint_normal_roughness_texture, repeat_disable, filter_nearest;
uniform vec4 rime_color : source_color = vec4(0.5, 0.78, 1.0, 1.0);
uniform vec4 vein_color : source_color = vec4(0.88, 0.98, 1.0, 1.0);
uniform vec4 violet_color : source_color = vec4(0.82, 0.66, 1.0, 1.0);

instance uniform float radius_m = 1.0;
instance uniform float grow = 1.0;
instance uniform float melt = 0.0;
instance uniform float glow = 1.0;
instance uniform float seed = 0.0;
// 0: frost densest at the centre (an impact); 1: piled up at the rim (the Nova).
instance uniform float rim_heavy = 0.0;
instance uniform float violet = 0.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
			mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

// Distance to the nearest Voronoi cell border (crystalline cracks).
float cracks(vec2 x) {
	vec2 n = floor(x);
	vec2 f = fract(x);
	vec2 mg = vec2(0.0);
	vec2 mr = vec2(0.0);
	float md = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 r = g + hash22(n + g) - f;
			float d = dot(r, r);
			if (d < md) {
				md = d;
				mr = r;
				mg = g;
			}
		}
	}
	md = 8.0;
	for (int j = -2; j <= 2; j++) {
		for (int i = -2; i <= 2; i++) {
			vec2 g = mg + vec2(float(i), float(j));
			vec2 r = g + hash22(n + g) - f;
			if (dot(mr - r, mr - r) > 0.00001) {
				md = min(md, dot(0.5 * (mr + r), normalize(r - mr)));
			}
		}
	}
	return md;
}

void fragment() {
	float depth = texture(depth_texture, SCREEN_UV).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	view.xyz /= view.w;
	vec3 world = (INV_VIEW_MATRIX * vec4(view.xyz, 1.0)).xyz;
	vec3 local = (inverse(MODEL_MATRIX) * vec4(world, 1.0)).xyz;
	if (abs(local.x) > 0.5 || abs(local.y) > 0.5 || abs(local.z) > 0.5) {
		discard;
	}
	vec3 normal = normalize((INV_VIEW_MATRIX * vec4(texture(normal_texture, SCREEN_UV).xyz * 2.0 - 1.0, 0.0)).xyz);
	if (dot(normal, normalize(MODEL_MATRIX[1].xyz)) < 0.6) {
		discard;
	}
	vec2 q = local.xz * 2.0;
	float r = length(q);
	vec2 m = q * radius_m;
	float angle = atan(q.y, q.x);

	// a ragged outline (pulled inward only, so it never passes the radius)
	float rag = noise(vec2(angle * 2.6 + seed * 7.0, seed * 3.0)) * 0.6
			+ noise(vec2(angle * 7.0 - seed * 5.0, seed)) * 0.4;
	float edge = grow * (1.0 - rag * mix(0.34, 0.012, rim_heavy));
	float aa = fwidth(r) + 1e-4;
	float inside = 1.0 - smoothstep(edge - aa, edge + aa, r);
	if (inside <= 0.0) {
		discard;
	}
	// melting: holes open up and spread
	float holes = noise(m * 1.3 + seed * 11.0) * 0.7 + noise(m * 3.1 - seed * 4.0) * 0.3;
	float hole_edge = holes - melt * 1.15;
	if (hole_edge < 0.0) {
		discard;
	}

	float rel = r / max(grow, 1e-3);
	float rim_w = mix(0.06, 0.22, rim_heavy) / radius_m;
	float rim = 1.0 - smoothstep(rim_w - aa, rim_w + aa, edge - r);
	float density = mix(1.0 - rel * rel * 0.7, 0.3 + 0.7 * smoothstep(0.25, 0.95, rel), rim_heavy);
	float grain = noise(m * 1.7 + seed * 5.0) * 0.6 + noise(m * 4.3 + seed) * 0.4;
	float rime = density + (grain - 0.5) * 0.8;
	float crack = 1.0 - smoothstep(0.02, 0.045, cracks(m * 2.2 + seed * 19.0));
	crack *= smoothstep(0.15, 0.45, rime);
	// a big patch (the Nova) keeps its cracks to the outer band, so the
	// fighters standing in it stay readable against a quiet frost
	crack *= mix(1.0, smoothstep(0.55, 0.9, rel), rim_heavy);
	// the cracks blaze while the frost is fresh, then settle to faint lines
	crack *= 0.35 + 0.65 * glow;
	vec2 cell = floor(m * 9.0);
	float sparkle = step(0.9, hash12(cell + seed)) * step(0.5, fract(TIME * 2.3 + hash12(cell) * 7.0))
			* (1.0 - smoothstep(0.08, 0.16, length(fract(m * 9.0) - 0.5)));
	sparkle *= step(0.3, rime);

	vec3 color = rime_color.rgb;
	// two hard rime tones; the Nova's wide interior is a thinner veil
	float veil = mix(1.0, 0.6, rim_heavy);
	float alpha = (rime > 0.62 ? 0.36 : (rime > 0.32 ? 0.15 : 0.0)) * veil;
	float bright = max(max(crack * 0.9, rim), sparkle);
	color = mix(color, vein_color.rgb * (1.0 + glow * 1.1), bright);
	alpha = max(alpha, max(crack * 0.6, max(rim * 0.8, sparkle * 0.75)));
	// melt holes get a thin bright lip (no dark halo around them)
	float lip = (1.0 - smoothstep(0.0, 0.04, hole_edge)) * step(0.001, melt);
	color = mix(color, vein_color.rgb, lip);
	alpha = max(alpha, lip * 0.3 * veil);
	color = mix(color, color * violet_color.rgb * 1.2, violet);
	ALBEDO = color;
	ALPHA = alpha * inside * (1.0 - 0.55 * melt) * (1.0 - smoothstep(0.8, 1.0, melt));
}
