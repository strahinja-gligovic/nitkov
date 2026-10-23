shader_type spatial;
// Stylized flame tongue for cone meshes: wobbles, flickers and fades toward
// the tip. Additive, so overlapping tongues bloom together.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 base_color : source_color = vec4(1.0, 0.8, 0.25, 1.0);
uniform vec4 tip_color : source_color = vec4(1.0, 0.22, 0.05, 1.0);
uniform float energy = 2.5;
uniform float flame_height = 2.0;
uniform float seed = 0.0;
// 0..1, for growing in and dying out.
uniform float intensity = 1.0;

varying float height01;

void vertex() {
	height01 = clamp(VERTEX.y / flame_height + 0.5, 0.0, 1.0);
	float t = TIME * 7.0 + seed * 13.0;
	VERTEX.x += sin(t + VERTEX.y * 3.0) * 0.14 * height01;
	VERTEX.z += cos(t * 1.3 + VERTEX.y * 2.0) * 0.1 * height01;
	VERTEX.y *= (0.8 + 0.2 * sin(t * 1.7)) * intensity;
}

void fragment() {
	vec3 color = mix(base_color.rgb, tip_color.rgb, height01);
	ALBEDO = color * energy;
	ALPHA = (1.0 - height01 * 0.85) * intensity;
}
