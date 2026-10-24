shader_type spatial;
// Sparks (LightningSparks, a MultiMesh of unit quads): each instance is
// drawn as a camera-facing streak trailing back along its velocity
// (INSTANCE_CUSTOM.xyz), white-hot at the head and cooling to the element
// colour as its life (INSTANCE_CUSTOM.w, 1 -> 0) runs out, with a flicker.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, skip_vertex_transform;

instance uniform vec4 tint : source_color = vec4(1.0, 0.86, 0.3, 1.0);
uniform vec4 hot_color : source_color = vec4(1.0, 0.97, 0.85, 1.0);
// Seconds of travel a streak covers: longer streaks for faster sparks.
uniform float stretch = 0.03;
uniform float min_pixels = 1.0;
uniform float energy = 2.2;

varying float v_life;
varying float v_along;
varying float v_flicker;

float hash(float n) {
	return fract(sin(n * 12.9898 + 4.1414) * 43758.5453);
}

void vertex() {
	vec3 centre = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float size = length(MODEL_MATRIX[0].xyz);
	vec3 velocity = (VIEW_MATRIX * vec4(INSTANCE_CUSTOM.xyz, 0.0)).xyz;
	float speed = length(velocity);
	vec3 dir = speed > 1e-3 ? velocity / speed : vec3(0.0, 1.0, 0.0);
	vec3 across = cross(dir, centre);
	float n = length(across);
	across = n > 1e-6 ? across / n : vec3(1.0, 0.0, 0.0);
	float pixel = 2.0 * max(-centre.z, 0.05) / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	float half_width = max(size * 0.5, min_pixels * pixel);
	float along = VERTEX.y + 0.5;  // 1 at the head, 0 at the tail
	float length_ = size + speed * stretch;
	VERTEX = centre - dir * (1.0 - along) * length_ + across * VERTEX.x * 2.0 * half_width;
	NORMAL = vec3(0.0, 0.0, 1.0);
	v_life = INSTANCE_CUSTOM.w;
	v_along = along;
	v_flicker = 0.55 + 0.45 * hash(float(INSTANCE_ID) * 7.13 + floor(TIME * 24.0));
}

void fragment() {
	float hot = step(0.45, v_life) * step(0.5, v_along);
	vec3 color = mix(tint.rgb, hot_color.rgb * 1.4, hot);
	float fade = clamp(v_life * 1.6, 0.0, 1.0) * (0.35 + 0.65 * v_along);
	ALBEDO = color * energy * fade * v_flicker;
	ALPHA = 1.0;
}
