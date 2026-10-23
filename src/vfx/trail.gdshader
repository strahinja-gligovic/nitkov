shader_type spatial;
// Blade trail ribbon. UV.x is age (0 = newest, 1 = about to vanish), UV.y
// runs hilt (0) to tip (1). Bright and sharp at the tip edge, fading toward
// the hilt and with age, so swings read as a crisp crescent smear.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 core_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 edge_color : source_color = vec4(1.0, 0.8, 0.45, 1.0);
uniform float energy = 2.2;
uniform float intensity = 1.0;

void fragment() {
	float age = clamp(UV.x, 0.0, 1.0);
	float span = clamp(UV.y, 0.0, 1.0);
	float fade = pow(1.0 - age, 2.0) * smoothstep(0.0, 0.3, span);
	// a hot rim right at the tip edge, like a comic speed line
	float rim = smoothstep(0.82, 1.0, span);
	vec3 color = mix(edge_color.rgb, core_color.rgb, rim * (1.0 - age));
	ALBEDO = color * energy;
	ALPHA = clamp(fade * (0.55 + 0.45 * rim) * intensity, 0.0, 1.0);
}
