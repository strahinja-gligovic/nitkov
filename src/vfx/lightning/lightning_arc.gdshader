shader_type spatial;
// Lightning arcs (LightningArc): camera-facing ribbons in hard cel bands, a
// white-hot core, an element-coloured rim and a faint outer glow. Additive,
// so they light up whatever is behind them; `brightness` (per instance) and
// the per-vertex brightness drive flicker, strobes and fades.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, skip_vertex_transform;

#include "res://src/vfx/lightning/lightning_ribbon.gdshaderinc"

instance uniform vec4 tint : source_color, instance_index(0) = vec4(1.0, 0.86, 0.3, 1.0);
instance uniform float brightness : instance_index(1) = 1.0;
uniform vec4 core_color : source_color = vec4(1.0, 0.98, 0.9, 1.0);
uniform float core_energy = 2.6;
uniform float rim_energy = 1.35;
uniform float glow_energy = 0.32;
// Where the bands change, as a fraction of the half-width.
uniform float core_edge = 0.3;
uniform float rim_edge = 0.64;

void vertex() {
	VERTEX = ribbon_position(VERTEX, NORMAL, UV.y, UV2.x, 0.0, MODELVIEW_MATRIX, PROJECTION_MATRIX, VIEWPORT_SIZE);
	NORMAL = vec3(0.0, 0.0, 1.0);
	v_side = UV.y;
	v_bright = UV2.y;
}

void fragment() {
	float d = abs(v_side);
	vec3 color = tint.rgb * glow_energy;
	color = mix(color, tint.rgb * rim_energy, band(rim_edge, d));
	color = mix(color, core_color.rgb * core_energy, band(core_edge, d));
	ALBEDO = color * max(v_bright * brightness, 0.0);
	ALPHA = 1.0;
}
