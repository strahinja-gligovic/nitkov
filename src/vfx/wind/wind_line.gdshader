shader_type spatial;
// Wind's streak lines and trails: thin ribbons that face the camera around
// their own direction, with a white core, element-colored edges and dashes
// that flow along them. Per vertex: VERTEX is the point on the line, NORMAL
// the line's direction, UV.x runs head (0) to tail (1), UV.y across,
// UV2.x is the width in metres, UV2.y the dash coordinate (one dash per
// unit) and COLOR.a fades it (a trail's age). Purely additive glow.
render_mode unshaded, blend_premul_alpha, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled, skip_vertex_transform;

#include "res://src/vfx/wind/wind_common.gdshaderinc"

uniform vec4 core_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 edge_color : source_color = vec4(0.5, 1.0, 0.72, 1.0);
uniform float energy = 1.6;
// Fraction of the width that's white core.
uniform float core_width = 0.35;
// 0 = solid; otherwise the lit fraction of each dash.
uniform float dash_fill = 0.0;
// Dashes travel this many units toward the tail per second.
uniform float scroll = 0.0;
uniform float head_fade = 0.08;
uniform float tail_fade = 0.6;
// Lines melt away this close to the camera (metres) instead of crossing the
// screen as thick bars.
uniform float near_fade_from = 0.4;
uniform float near_fade_to = 1.6;
instance uniform float anim_time = 0.0;
instance uniform float fade = 1.0;

varying float v_alpha;
varying float v_dash;

void vertex() {
	vec3 p = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 dir = (MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	VERTEX = wind_face_camera(p, dir, (UV.y - 0.5) * UV2.x);
	v_alpha = COLOR.a;
	v_dash = UV2.y;
}

void fragment() {
	float across = abs(UV.y * 2.0 - 1.0);
	float along = UV.x;
	float body = 1.0 - wind_band(0.82, across);
	float core = 1.0 - wind_band(core_width, across);
	float dash = 1.0;
	if (dash_fill > 0.0) {
		dash = 1.0 - wind_band(dash_fill, fract(v_dash - anim_time * scroll));
	}
	float a = body * dash * v_alpha * fade * smoothstep(near_fade_from, near_fade_to, length(VERTEX));
	a *= smoothstep(0.0, head_fade, along) * (1.0 - tail_fade * along);
	vec3 color = mix(edge_color.rgb, core_color.rgb, core) * energy;
	ALBEDO = color * clamp(a, 0.0, 1.0);
	ALPHA = 0.0;
}
