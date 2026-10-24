shader_type spatial;
// Glitter and glints: a camera-facing four-point star with a white-hot core,
// added on top of the scene. FrostBits passes (brightness, roll, violet, seed)
// per instance in INSTANCE_CUSTOM; a lone glint uses the instance uniforms.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled, blend_add;

uniform vec4 core_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 ray_color : source_color = vec4(0.45, 0.88, 1.0, 1.0);
uniform vec4 violet_color : source_color = vec4(0.82, 0.62, 1.0, 1.0);
uniform float energy = 3.0;
uniform bool use_custom = true;

instance uniform float brightness = 1.0;
instance uniform float roll = 0.0;

varying vec4 v_data;

void vertex() {
	v_data = use_custom ? INSTANCE_CUSTOM : vec4(brightness, roll, 0.0, 0.0);
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	float c = cos(v_data.y);
	float s = sin(v_data.y);
	vec3 right = INV_VIEW_MATRIX[0].xyz * c + INV_VIEW_MATRIX[1].xyz * s;
	vec3 up = INV_VIEW_MATRIX[1].xyz * c - INV_VIEW_MATRIX[0].xyz * s;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(right * scale.x, 0.0), vec4(up * scale.y, 0.0),
			vec4(INV_VIEW_MATRIX[2].xyz * scale.z, 0.0), MODEL_MATRIX[3]);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ray_x = max(0.0, 1.0 - abs(p.y) * 9.0) * (1.0 - abs(p.x));
	float ray_y = max(0.0, 1.0 - abs(p.x) * 9.0) * (1.0 - abs(p.y));
	float rays = max(ray_x, ray_y);
	float core = 1.0 - smoothstep(0.1, 0.28, r);
	float shape = max(rays * rays, core);
	vec3 color = mix(mix(ray_color.rgb, violet_color.rgb, v_data.z), core_color.rgb, core);
	ALBEDO = color * energy * shape * v_data.x;
}
