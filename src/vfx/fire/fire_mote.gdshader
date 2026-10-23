shader_type spatial;
// Embers and sparks, for GPU particles and FireMotes alike: camera-facing
// quads that cool through the toon fire bands as they age and shrink away
// instead of fading (crisp, comic). With `streak` > 0 the quad is a spark
// stretched back along the instance's Y axis (the velocity; GPU particles
// need particle_flag_align_y), `streak` times as long as it is wide.
// INSTANCE_CUSTOM.y is the age as a fraction of the life.
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

#include "res://src/vfx/fire/fire_noise.gdshaderinc"

uniform float streak = 0.0;
uniform float heat_start = 1.0;
uniform float heat_end = 0.15;
uniform float flicker = 0.25;

varying float v_age;
varying float v_seed;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 to_cam = normalize(INV_VIEW_MATRIX[3].xyz - origin);
	float size = length(MODEL_MATRIX[0].xyz);
	mat4 world;
	if (streak > 0.0) {
		vec3 axis = MODEL_MATRIX[1].xyz;
		float len = length(axis);
		vec3 dir = axis / max(len, 0.00001);
		vec3 side = cross(dir, to_cam);
		float side_len = length(side);
		side = side_len > 0.0001 ? side / side_len : INV_VIEW_MATRIX[0].xyz;
		// the particle sits at the head; the streak trails behind it
		VERTEX.y -= 0.5;
		world = mat4(vec4(side * size, 0.0), vec4(dir * len * streak, 0.0), vec4(to_cam, 0.0), vec4(origin, 1.0));
	} else {
		world = mat4(INV_VIEW_MATRIX[0] * size, INV_VIEW_MATRIX[1] * size, INV_VIEW_MATRIX[2], vec4(origin, 1.0));
	}
	MODELVIEW_MATRIX = VIEW_MATRIX * world;
	v_age = clamp(INSTANCE_CUSTOM.y, 0.0, 1.0);
	v_seed = fract(float(INSTANCE_ID) * 0.6180339 + INSTANCE_CUSTOM.x * 0.1713);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float shrink = 1.0 - v_age * v_age * v_age;
	float twinkle = fire_noise(vec3(v_seed * 31.0, TIME * 9.0, v_seed * 7.0));
	float h = mix(heat_start, heat_end, v_age) + twinkle * flicker;
	float r;
	if (streak > 0.0) {
		// UV.y: 0 at the head, 1 at the tail; thins toward the tail
		float along = UV.y;
		float half_width = (1.0 - along * 0.75) * shrink;
		r = abs(p.x) / max(half_width, 0.001);
		r = max(r, smoothstep(1.0 - 0.6 * shrink, 1.0, along) * 1.2);
		h += (1.0 - along) * 0.25 - along * 0.25;
	} else {
		r = length(p) / max(shrink, 0.001);
	}
	h += (1.0 - r) * 0.3;
	float aa = max(fwidth(h), 0.002);
	if (r > 1.0) {
		discard;
	}
	ALBEDO = fire_ramp(h, aa);
	ALPHA = 1.0;
}
