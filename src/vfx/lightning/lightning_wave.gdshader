shader_type spatial;
// A flat shockwave on the ground (LightningStrikeFx): a hard white leading
// edge with an element-coloured band behind it, expanding to `reach`
// (metres) on a quad `extent` metres from the centre to each side, plus a
// white flash filling the circle for the first moment (`flash`, 0..1).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

instance uniform float reach = 1.0;
instance uniform float extent = 3.0;
instance uniform float thickness = 0.5;
instance uniform float energy = 1.0;
instance uniform float flash = 0.0;
instance uniform float limit = 2.5;
uniform vec4 tint : source_color = vec4(1.0, 0.86, 0.3, 1.0);
uniform vec4 core_color : source_color = vec4(1.0, 0.98, 0.9, 1.0);

float band(float edge, float x) {
	float w = max(fwidth(x), 1e-4);
	return clamp((edge - x) / w + 0.5, 0.0, 1.0);
}

void fragment() {
	vec2 p = (UV * 2.0 - 1.0) * extent;
	float r = length(p);
	float behind = reach - r;
	float wave = band(thickness, behind) * (1.0 - band(0.0, behind));
	float lead = band(thickness * 0.3, behind) * (1.0 - band(0.0, behind));
	vec3 color = tint.rgb * wave * 1.4 + core_color.rgb * lead * 1.6;
	color *= energy;
	color += core_color.rgb * flash * band(limit, r) * (1.4 - 0.6 * r / max(limit, 0.01));
	ALBEDO = color;
	ALPHA = 1.0;
}
