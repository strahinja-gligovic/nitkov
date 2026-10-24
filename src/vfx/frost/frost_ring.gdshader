shader_type spatial;
// A frost shock ring, drawn on a 2x2 plane in local XZ that the owner scales
// to radius_m: a crisp band whose leading edge is a row of ice teeth (the
// tips touch radius_m exactly): a bright edge with a fainter band behind
// it. It thins and fades as `fade` goes 0 -> 1.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 pale_color : source_color = vec4(0.88, 0.98, 1.0, 1.0);
uniform vec4 mid_color : source_color = vec4(0.42, 0.83, 1.0, 1.0);
uniform vec4 violet_color : source_color = vec4(0.8, 0.62, 1.0, 1.0);

instance uniform float radius_m = 1.0;
instance uniform float width_m = 0.4;
instance uniform float fade = 0.0;
instance uniform float teeth = 24.0;
instance uniform float tooth_m = 0.15;
instance uniform float violet = 0.0;
instance uniform float energy = 1.8;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p) * radius_m;
	float a = atan(p.y, p.x) / TAU;
	float saw = abs(fract(a * teeth) - 0.5) * 2.0;
	float outer = radius_m - saw * tooth_m;
	float width = max(width_m * (1.0 - 0.75 * fade), 0.015);
	float inner = outer - width;
	float aa = fwidth(r) + 1e-4;
	float band = smoothstep(inner - aa, inner + aa, r) * (1.0 - smoothstep(outer - aa, outer + aa, r));
	if (band <= 0.0) {
		discard;
	}
	float t = (r - inner) / width;
	float bright = step(0.62, t);
	vec3 color = mix(mid_color.rgb * 1.2, pale_color.rgb * energy, bright);
	color = mix(color, mix(color, violet_color.rgb * (1.0 + bright * energy * 0.6), 0.6), violet);
	ALBEDO = color;
	ALPHA = band * mix(t > 0.25 ? 0.42 : 0.18, 0.95, bright) * (1.0 - fade * fade);
}
