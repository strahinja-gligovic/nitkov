shader_type spatial;
// Lightning Strike's warning circle on the ground (LightningWarningFx), on a
// flat quad `extent` metres from the centre to each side. Inside `radius`:
// the storm's shadow, a countdown fill growing from the centre that reaches
// the rim exactly when the bolt lands (`progress` 0..1), a zigzag sigil
// turning inside the rim, and the rim itself: a solid band ending exactly at
// `radius` with a crackling line and sparks of light running round it.
// Premultiplied alpha: the shadow darkens the ground, the glow adds to it.
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

instance uniform float radius = 2.5;
instance uniform float extent = 3.0;
instance uniform float progress = 0.0;
instance uniform float age = 0.0;
instance uniform float energy = 1.0;
instance uniform float seed = 0.0;
uniform vec4 tint : source_color = vec4(1.0, 0.86, 0.3, 1.0);
uniform vec4 core_color : source_color = vec4(1.0, 0.98, 0.9, 1.0);
uniform vec4 shadow_color : source_color = vec4(0.06, 0.02, 0.12, 1.0);

float hash(float n) {
	return fract(sin(n * 12.9898 + 4.1414) * 43758.5453);
}

float noise1(float x) {
	float i = floor(x);
	float f = fract(x);
	return mix(hash(i), hash(i + 1.0), f * f * (3.0 - 2.0 * f));
}

float band(float edge, float x) {
	float w = max(fwidth(x), 1e-4);
	return clamp((edge - x) / w + 0.5, 0.0, 1.0);
}

void fragment() {
	vec2 p = (UV * 2.0 - 1.0) * extent;
	float r = length(p);
	float turn = atan(p.y, p.x) / 6.2831853 + 0.5;
	float t = clamp(progress, 0.0, 1.0);
	float beat = floor(age * 20.0);

	float inside = band(radius, r);
	float shade = inside * (0.2 + 0.25 * t);
	vec3 glow = vec3(0.0);

	// the countdown: a fill from the centre, its front a bright line
	float fill_r = radius * t;
	glow += tint.rgb * band(fill_r, r) * (0.1 + 0.12 * t) * (0.6 + 0.4 * step(0.5, fract(r * 2.5 - age * 3.0)));
	glow += core_color.rgb * band(0.05 + 0.03 * t, abs(r - fill_r)) * step(0.02, t) * 1.8;

	// a zigzag sigil turning inside the rim
	float zig = abs(fract(turn * 22.0 + age * 0.35) * 2.0 - 1.0);
	float zig_r = radius * 0.8 + (zig - 0.5) * 0.22;
	glow += tint.rgb * band(0.03, abs(r - zig_r)) * (0.5 + 1.1 * t);

	// the rim: a solid band whose outer edge is exactly the radius
	float rim = inside * (1.0 - band(radius - 0.16, r));
	glow += tint.rgb * rim * (1.0 + 0.8 * t);
	// a crackling line along it, re-drawn every beat
	float crackle = radius - 0.08 + (noise1(turn * 46.0 + beat * 5.3 + seed * 31.0) - 0.5) * 0.2;
	glow += core_color.rgb * band(0.022, abs(r - crackle)) * (1.6 + 1.6 * t);
	// light running round the rim, faster as the strike nears
	float run = pow(fract(turn * 3.0 - age * (1.2 + 2.0 * t)), 8.0);
	glow += core_color.rgb * run * rim * 2.2;
	// a thin outer halo just outside the rim
	glow += tint.rgb * (1.0 - inside) * band(0.12, r - radius) * 0.35;

	ALBEDO = shadow_color.rgb * shade + glow * energy;
	ALPHA = shade;
}
