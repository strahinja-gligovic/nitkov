shader_type spatial;
// The dark ink backing behind a big bolt (the first pass of LightningArc's
// inked material; the glowing ribbon is drawn over it). A comic-book outline
// that keeps a yellow bolt readable against a bright sky or a lit wall.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, skip_vertex_transform;

#include "res://src/vfx/lightning/lightning_ribbon.gdshaderinc"

instance uniform float brightness : instance_index(1) = 1.0;
uniform vec4 ink : source_color = vec4(0.07, 0.03, 0.11, 0.85);
// The outline: the glowing strip's width times this, plus a few pixels.
uniform float width_scale = 1.25;
uniform float pad_pixels = 1.6;

void vertex() {
	VERTEX = ribbon_position(VERTEX, NORMAL, UV.y, UV2.x * width_scale, pad_pixels,
			MODELVIEW_MATRIX, PROJECTION_MATRIX, VIEWPORT_SIZE);
	NORMAL = vec3(0.0, 0.0, 1.0);
	v_side = UV.y;
	v_bright = UV2.y;
}

void fragment() {
	ALBEDO = ink.rgb;
	ALPHA = ink.a * clamp(v_bright * brightness * 1.5, 0.0, 1.0);
}
