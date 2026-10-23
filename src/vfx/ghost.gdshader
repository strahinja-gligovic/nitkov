shader_type spatial;
// Afterimage: a glowing rim silhouette with a faint fill, fading out in a
// few stepped beats (comic timing rather than a smooth fade).
render_mode unshaded, blend_add, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(0.6, 0.8, 1.0, 1.0);
uniform float fade = 1.0;

void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	float stepped = ceil(fade * 4.0) / 4.0;
	ALBEDO = color.rgb * (0.3 + rim * 1.8) * 1.5;
	ALPHA = clamp(stepped * (0.2 + rim * 0.8), 0.0, 1.0);
}
