shader_type spatial;
// Smoke puffs, for GPU particles and FireMotes: camera-facing blobs with a
// boiling noise edge, toon-lit from above in two flat tones with an ink rim,
// and a fire glow on the underside while they're young. They erode away with
// age. INSTANCE_CUSTOM.x spins the puff (and seeds it), .y is the age as a
// fraction of the life.
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

#include "res://src/vfx/fire/fire_noise.gdshaderinc"

uniform vec4 light_color : source_color = vec4(0.34, 0.28, 0.31, 1.0);
uniform vec4 shade_color : source_color = vec4(0.22, 0.17, 0.2, 1.0);
uniform vec4 ink_color : source_color = vec4(0.07, 0.045, 0.08, 1.0);
uniform vec4 glow_color : source_color = vec4(1.0, 0.4, 0.1, 1.0);
uniform float opacity = 0.85;
// How long (as a fraction of the life) the underside keeps the fire's glow.
uniform float glow_time = 0.3;
// How much the puff swells over its life.
uniform float swell = 0.6;

varying float v_age;
varying float v_seed;
varying vec2 v_up;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float size = length(MODEL_MATRIX[0].xyz);
	v_age = clamp(INSTANCE_CUSTOM.y, 0.0, 1.0);
	size *= 1.0 + swell * (1.0 - (1.0 - v_age) * (1.0 - v_age));
	float spin = INSTANCE_CUSTOM.x;
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	vec3 r = right * cos(spin) + up * sin(spin);
	vec3 u = -right * sin(spin) + up * cos(spin);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(r * size, 0.0), vec4(u * size, 0.0), INV_VIEW_MATRIX[2], vec4(origin, 1.0));
	// world up in the quad's own (spun) frame, for the fake top light
	v_up = vec2(dot(vec3(0.0, 1.0, 0.0), r), dot(vec3(0.0, 1.0, 0.0), u));
	v_seed = fract(float(INSTANCE_ID) * 0.7548777 + spin * 0.1591);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	p.y = -p.y;
	float t = TIME * 0.5;
	float n = fire_fbm(vec3(p * 1.25, v_seed * 23.0 + t));
	float radius = 0.82 + 0.2 * n - v_age * 0.12;
	float r = length(p);
	float inside = radius - r;
	// erode into tatters as it ages, from the middle of its life, so a puff
	// thins out and frays rather than hanging as a solid lump
	float holes = fire_noise(vec3(p * 2.2, v_seed * 11.0 + t * 1.5)) * 0.5 + 0.5;
	holes += (1.0 - r / max(radius, 0.001)) * 0.15;
	float aa = max(fwidth(inside), 0.002);
	if (inside < 0.0 || holes < v_age * 1.25 - 0.3) {
		discard;
	}
	// a ball lit from above: two flat tones
	vec2 up = length(v_up) > 0.001 ? normalize(v_up) : vec2(0.0, 1.0);
	float z = sqrt(max(1.0 - (r * r) / (radius * radius), 0.0));
	vec3 normal = normalize(vec3(p / radius, z));
	float lit = dot(normal, normalize(vec3(up * 0.8 + vec2(-up.y, up.x) * 0.3, 0.55)));
	vec3 color = mix(shade_color.rgb, light_color.rgb, smoothstep(0.32 - aa * 4.0, 0.32 + aa * 4.0, lit + n * 0.15));
	// young smoke glows from the fire below
	float below = -dot(p, up) / radius;
	float glow = glow_time > 0.0 ? (1.0 - smoothstep(glow_time * 0.6, glow_time, v_age)) * smoothstep(0.05, 0.35, below + n * 0.2) : 0.0;
	// a warm tint, not a solid orange crescent (that reads as a lump of lava)
	color = mix(color, glow_color.rgb * 0.9, glow * 0.5);
	// a thin ink rim, only on the shaded underside: smoke, not a boulder
	float ink_w = 0.03 * smoothstep(-0.2, 0.4, below);
	color = mix(ink_color.rgb, color, smoothstep(ink_w, ink_w + aa * 2.0, inside));
	ALBEDO = color;
	ALPHA = opacity * (1.0 - smoothstep(0.35, 1.0, v_age) * 0.85) * (1.0 - smoothstep(0.85, 1.0, v_age));
}
