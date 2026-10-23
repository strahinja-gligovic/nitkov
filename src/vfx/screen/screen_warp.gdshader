shader_type canvas_item;
// A wind burst's shockwave seen through the screen: a ring of refraction
// racing out from the burst's place on screen, with a slight chromatic split
// on its front. Only the ring is drawn; the rest of the screen is untouched.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear, repeat_disable;
uniform vec2 center = vec2(0.5);
uniform float progress = 0.0;
uniform float strength = 0.0;
uniform float aspect = 1.7778;

void fragment() {
	vec2 d = SCREEN_UV - center;
	d.x *= aspect;
	float r = length(d);
	float eased = 1.0 - pow(1.0 - progress, 3.0);
	float radius = mix(0.05, 1.05, eased);
	float width = mix(0.05, 0.17, eased);
	float offset = r - radius;
	float band = 1.0 - smoothstep(0.0, width, abs(offset));
	float amount = band * strength * (1.0 - progress);
	if (amount < 0.002) {
		discard;
	}
	vec2 dir = d / max(r, 0.0001);
	dir.x /= aspect;
	// the front bulges outward like a lens: pull the picture toward the ring
	vec2 uv = SCREEN_UV - dir * amount * 0.028 * sign(offset);
	float split = amount * 0.008;
	vec3 c;
	c.r = texture(screen_texture, uv + dir * split).r;
	c.g = texture(screen_texture, uv).g;
	c.b = texture(screen_texture, uv - dir * split).b;
	// a faint mint sheen right on the wavefront
	c += vec3(0.05, 0.11, 0.08) * step(abs(offset), width * 0.3) * strength * (1.0 - progress);
	COLOR = vec4(c, 1.0);
}
