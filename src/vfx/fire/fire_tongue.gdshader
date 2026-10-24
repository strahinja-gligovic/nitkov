shader_type spatial;
// Flame Wall tongues: upright quads that turn about their vertical axis to
// face the camera (one MultiMesh, base at the instance origin). Each is a
// teardrop of heat whose outline is pushed around by noise rising through
// it, cut into the toon heat bands with a thin ink outline. Each instance's
// custom data is (seed 0..1, eruption delay in seconds, unused, kind: 0 a
// main tongue, 1 a lick at the edge). The wall's look drives `intensity`
// (0 out .. 1 blazing) and `age` (seconds since it rose).
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

#include "res://src/vfx/fire/fire_noise.gdshaderinc"

instance uniform float intensity = 1.0;
instance uniform float age = 10.0;
// Opacity of the outer (red and orange) bands; yellow and the core are
// solid. Below 1 so a fighter behind the wall still reads through it.
uniform float opacity = 0.5;
// Opacity of the yellow band; only the white core is solid.
uniform float yellow_opacity = 0.8;

varying vec4 v_custom;
varying float v_boost;

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	float t = age - INSTANCE_CUSTOM.y;
	// erupt: shoot up past full height in a blink, then settle
	float rise = clamp(t / 0.1, 0.0, 1.0);
	float settle = clamp((t - 0.1) / 0.4, 0.0, 1.0);
	settle = settle * settle * (3.0 - 2.0 * settle);
	float erupt = (1.0 - pow(1.0 - rise, 3.0)) * mix(1.18, 1.0, settle);
	// dying down: each tongue sinks at its own pace
	float life = pow(clamp(intensity, 0.0, 1.0), 0.5 + INSTANCE_CUSTOM.x * 1.2);
	vec3 origin = MODEL_MATRIX[3].xyz;
	// each tongue leaps on its own, and surges roll along the wall, so the
	// top edge roars instead of standing like a picket fence
	float flick = 1.0 + 0.12 * fire_noise(vec3(INSTANCE_CUSTOM.x * 17.0, TIME * 2.6, INSTANCE_CUSTOM.w));
	float along = origin.x * 0.83 + origin.z * 0.57;
	flick += 0.08 * sin(along * 1.6 - TIME * 5.5 + INSTANCE_CUSTOM.x) * (1.0 - INSTANCE_CUSTOM.w * 0.5);
	float grow = erupt * life * flick;
	// freshly erupted flames flash white-hot for a beat; dying ones cool
	float flash = clamp(1.0 - (t - 0.05) / 0.2, 0.0, 1.0);
	v_boost = flash * rise * 0.14 - (1.0 - clamp(intensity, 0.0, 1.0)) * 0.3;

	float width = length(MODEL_MATRIX[0].xyz);
	vec3 up = MODEL_MATRIX[1].xyz;
	vec3 up_dir = normalize(up);
	vec3 right = cross(up_dir, INV_VIEW_MATRIX[3].xyz - origin);
	float right_len = length(right);
	right = right_len > 0.0001 ? right / right_len : INV_VIEW_MATRIX[0].xyz;
	vec3 facing = cross(right, up_dir);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(right * width, 0.0), vec4(up * grow, 0.0), vec4(facing, 0.0), vec4(origin, 1.0));
}

void fragment() {
	float seed = v_custom.x * 37.0;
	float lick = v_custom.w;
	float x = UV.x * 2.0 - 1.0;
	float y = 1.0 - UV.y;
	float t = TIME * (1.0 + lick * 0.3);
	// noise rising through the flame pushes its outline about, more toward
	// the tip, so the tongue waves and tears
	float n = fire_noise(vec3(x * 1.3 + seed, y * 1.9 - t * 2.6, t * 0.5 + seed));
	float n2 = fire_noise(vec3(x * 3.2 - seed, y * 4.2 - t * 4.4, t * 0.9));
	float sway = fire_noise(vec3(seed, y * 0.7 - t * 0.8, t * 0.3)) * 0.28 * y;
	float xs = x - sway - (n * 0.6 + n2 * 0.4) * 0.3 * y;
	// teardrop of heat: round-bellied, pointed, hottest low in the middle
	float below = max(1.0 - y, 0.0);
	float half_width = 0.85 * pow(below, 0.6);
	float core = 1.27 * pow(below, 0.8);
	float g = core * (1.0 - abs(xs) / max(half_width, 0.001));
	// torn tips and stray licks, kept inside the quad
	g += n2 * 0.16 * y + n * 0.08 - smoothstep(0.82, 1.0, y) * 0.5;
	g += v_boost;
	// never reach the quad's sides: a flame cut there shows a straight edge
	g -= smoothstep(0.78, 0.98, abs(x)) * 1.6;
	float aa = max(fwidth(g), 0.002);
	if (g < 0.0) {
		discard;
	}
	// a thin ink outline, then red, orange, yellow and the white core
	float h = FIRE_T_RED + g * 0.62;
	vec3 color = fire_ramp(h, aa * 0.62);
	color = mix(FIRE_INK, color, smoothstep(0.035, 0.035 + aa, g));
	ALBEDO = color;
	float yellow = smoothstep(FIRE_T_YELLOW - aa, FIRE_T_YELLOW + aa, h);
	float solid = smoothstep(FIRE_T_CORE - aa, FIRE_T_CORE + aa, h);
	ALPHA = mix(mix(opacity, yellow_opacity, yellow), 1.0, solid) * smoothstep(0.0, aa * 1.5, g);
}
