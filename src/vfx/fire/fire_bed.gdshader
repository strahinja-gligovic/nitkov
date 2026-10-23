shader_type spatial;
// The Flame Wall's bed of embers on a PlaneMesh exactly the size of the
// burning area: charred ground webbed with glowing cracks that pulse, ragged
// only inward so it never claims more ground than the fire does. `sweep`
// reveals it from the centre out to both ends with a white-hot front as the
// wall erupts; `intensity` dims it to dark coals as the wall dies.
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

#include "res://src/vfx/fire/fire_noise.gdshaderinc"

uniform vec2 size = vec2(8.0, 1.2);
uniform vec4 char_color : source_color = vec4(0.12, 0.05, 0.06, 1.0);
instance uniform float intensity = 1.0;
instance uniform float sweep = 1.0;

varying vec2 v_local;

void vertex() {
	v_local = VERTEX.xz;
}

void fragment() {
	vec2 p = v_local;
	vec2 half_size = size * 0.5;
	float t = TIME;
	float n = fire_fbm(vec3(p * 1.9, t * 0.3));
	// distance in from the edge of the area, frayed by noise (inward only)
	float edge = min(half_size.x - abs(p.x), half_size.y - abs(p.y));
	float frayed = edge - (0.5 + 0.5 * n) * 0.16;
	// the eruption front racing out from the centre, its leading edge torn
	// into licks so it reads as fire spreading, not a sliding tile
	float front = sweep * (half_size.x + 0.5) - abs(p.x) + n * 0.3;
	// glowing cracks: thin ridges of noise
	float ridge = 1.0 - abs(fire_noise(vec3(p * vec2(1.6, 2.6), 3.7 + t * 0.12)));
	float ridge2 = 1.0 - abs(fire_noise(vec3(p * 4.1 + 9.0, t * 0.2)));
	float crack = max(smoothstep(0.82, 0.97, ridge), smoothstep(0.88, 0.98, ridge2) * 0.7);
	float pulse = 0.85 + 0.15 * sin(t * 6.0 + p.x * 1.7 + n * 3.0);
	float live = clamp(intensity, 0.0, 1.0);
	float h = crack * (0.55 + 0.35 * live) * pulse + n * 0.12 + live * 0.18;
	// a hot band just behind the front while it sweeps out: yellow with
	// white-hot flecks, cooling behind it (all white read as a flat slab)
	float behind = 1.0 - smoothstep(0.0, 0.45 + 0.25 * n, front);
	h += behind * (1.0 - smoothstep(0.85, 1.0, sweep)) * (0.42 + 0.3 * crack + 0.15 * n);
	float aa = max(fwidth(h), 0.002);
	float edge_aa = max(fwidth(frayed), 0.002);
	if (frayed < 0.0 || front < 0.0) {
		discard;
	}
	vec3 fire = fire_ramp(h, aa);
	vec3 color = mix(char_color.rgb, fire, smoothstep(FIRE_T_RED - aa, FIRE_T_RED + aa, h));
	ALBEDO = color;
	ALPHA = smoothstep(0.0, edge_aa * 2.0 + 0.04, frayed) * (0.6 + 0.4 * live);
}
