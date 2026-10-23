shader_type spatial;
// Slash crescent. UV.x runs along the swing (0 = start, 1 = end), UV.y from
// the inner to the outer radius. A bright head sweeps along the arc, the tail
// follows, and the shape erodes away instead of fading, with time stepped at
// ~15 fps for a hand-drawn feel.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 core_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 edge_color : source_color = vec4(1.0, 0.75, 0.35, 1.0);
uniform float energy = 2.4;
uniform float progress = 0.0;
uniform float steps = 4.0;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	float p = floor(progress * steps) / steps;
	float head = smoothstep(0.0, 0.45, p) * 1.15;
	float tail = smoothstep(0.25, 1.0, p);
	float along = UV.x;
	float across = UV.y;
	float body = step(tail, along) * step(along, head);
	// thicker toward the outer edge and the leading head: a crescent, not a band
	float thickness = smoothstep(0.0, 0.35, across) * (1.0 - smoothstep(0.92, 1.0, across));
	float lead = smoothstep(head - 0.5, head, along);
	float erode = step(hash(floor(UV * vec2(40.0, 6.0))), 1.0 - tail * 0.9);
	float mask = body * thickness * mix(0.45, 1.0, lead) * erode;
	vec3 color = mix(edge_color.rgb, core_color.rgb, smoothstep(0.6, 1.0, across) * lead);
	ALBEDO = color * energy;
	ALPHA = clamp(mask, 0.0, 1.0);
}
