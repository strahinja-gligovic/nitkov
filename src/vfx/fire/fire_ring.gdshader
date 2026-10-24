shader_type spatial;
// A shock ring of flame on a flat quad (local XZ, radius 1 at the edge): a
// band that races out with ease-out, thins, cools and breaks into flame
// segments. `progress` runs 0..1 over its life.
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

#include "res://src/vfx/fire/fire_noise.gdshaderinc"

instance uniform float progress = 0.0;
instance uniform float seed = 0.0;
// Band width at the start, as a fraction of the radius.
uniform float thickness = 0.2;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ease = 1.0 - pow(1.0 - progress, 3.0);
	float radius = mix(0.12, 0.9, ease);
	float width = thickness * (1.0 - progress * 0.8);
	vec2 dir = r > 0.0001 ? p / r : vec2(1.0, 0.0);
	float n = fire_noise(vec3(dir * 2.4, seed + progress * 4.0));
	// flame licks trail inward from the leading edge
	float d = r - radius;
	float band = d < 0.0 ? -d / (width * (0.75 + 0.6 * n)) : d / (width * 0.25);
	float h = 1.05 - progress * 0.9 - band * 0.55 + n * 0.25;
	float aa = max(fwidth(h), 0.002);
	if (band > 1.0 || h < FIRE_T_INK) {
		discard;
	}
	ALBEDO = fire_ramp(h, aa);
	ALPHA = 1.0 - smoothstep(0.75, 1.0, progress);
}
