shader_type spatial;
// Screen-space ink outlines, drawn by a full-screen quad parked in front of
// the camera. Edges come from depth discontinuities (the Laplacian, so floors
// seen at grazing angles stay clean) and from normal creases. The shader only
// paints ink and never resamples the screen, so transparent VFX drawn after
// it stay visible.
render_mode unshaded, fog_disabled, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled;

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D normal_texture : hint_normal_roughness_texture, repeat_disable, filter_nearest;
uniform vec4 ink_color : source_color = vec4(0.06, 0.03, 0.09, 1.0);
uniform float thickness = 1.6;
uniform float depth_sensitivity = 9.0;
uniform float normal_sensitivity = 1.4;
uniform float fade_start = 40.0;
uniform float fade_end = 110.0;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float linear_depth(vec2 uv, mat4 inv_projection) {
	float raw = texture(depth_texture, uv).r;
	vec4 view = inv_projection * vec4(uv * 2.0 - 1.0, raw, 1.0);
	return -view.z / view.w;
}

vec3 view_normal(vec2 uv) {
	return texture(normal_texture, uv).xyz * 2.0 - 1.0;
}

void fragment() {
	vec2 o = thickness / VIEWPORT_SIZE;
	float d = linear_depth(SCREEN_UV, INV_PROJECTION_MATRIX);
	float d_l = linear_depth(SCREEN_UV - vec2(o.x, 0.0), INV_PROJECTION_MATRIX);
	float d_r = linear_depth(SCREEN_UV + vec2(o.x, 0.0), INV_PROJECTION_MATRIX);
	float d_u = linear_depth(SCREEN_UV - vec2(0.0, o.y), INV_PROJECTION_MATRIX);
	float d_d = linear_depth(SCREEN_UV + vec2(0.0, o.y), INV_PROJECTION_MATRIX);
	float laplacian = abs(d_l + d_r - 2.0 * d) + abs(d_u + d_d - 2.0 * d);
	float depth_edge = clamp(laplacian / max(d, 0.1) * depth_sensitivity - 0.2, 0.0, 1.0);

	vec3 n = view_normal(SCREEN_UV);
	float crease = distance(n, view_normal(SCREEN_UV - vec2(o.x, 0.0)))
			+ distance(n, view_normal(SCREEN_UV + vec2(o.x, 0.0)))
			+ distance(n, view_normal(SCREEN_UV - vec2(0.0, o.y)))
			+ distance(n, view_normal(SCREEN_UV + vec2(0.0, o.y)));
	float normal_edge = clamp(crease * normal_sensitivity - 0.6, 0.0, 1.0);

	float edge = max(depth_edge, normal_edge) * (1.0 - smoothstep(fade_start, fade_end, d));
	ALBEDO = ink_color.rgb;
	ALPHA = edge * ink_color.a;
}
