shader_type spatial;
// A gust ring: a flat ring of swirling comet arcs that grows from
// `radius_from` to `radius_to` and thins out as `progress` runs 0..1. The
// mesh is an annulus in the XZ plane (WindMeshes.annulus: UV.x around, UV.y
// inner to outer edge). Arcs have a white head and a mint tail, and an
// optional ink line runs along their inside edge.
render_mode unshaded, blend_premul_alpha, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

#include "res://src/vfx/wind/wind_common.gdshaderinc"

uniform vec4 core_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 edge_color : source_color = vec4(0.5, 1.0, 0.72, 1.0);
uniform vec4 ink_color : source_color = vec4(0.03, 0.17, 0.19, 1.0);
uniform float energy = 1.7;
uniform float arcs = 3.0;
// Lit fraction of each arc's period (1 = an unbroken ring).
uniform float arc_fill = 0.7;
// How far the arcs twist from the inner to the outer edge (turns).
uniform float swirl = 0.15;
// Turns per second.
uniform float spin = 1.5;
uniform float ink = 0.5;
// The band's inner edge at the start and the end (fraction of the annulus).
uniform float band_from = 0.15;
uniform float band_to = 0.8;
// Fades out this close to the camera (metres), so a splash on you or a
// burst around you doesn't smear bars across the screen.
uniform float near_fade_from = 0.5;
uniform float near_fade_to = 2.0;
instance uniform float progress = 0.0;
instance uniform float fade = 1.0;
instance uniform float radius_from = 0.2;
instance uniform float radius_to = 1.0;
instance uniform float seed = 0.0;

void vertex() {
	float eased = 1.0 - pow(1.0 - clamp(progress, 0.0, 1.0), 3.0);
	VERTEX.xz *= mix(radius_from, radius_to, eased);
}

void fragment() {
	float t = clamp(progress, 0.0, 1.0);
	float r = UV.y;
	float inner = mix(band_from, band_to, t);
	float band = wind_band(inner, r) * (1.0 - wind_band(0.96, r));
	float spin_turns = spin * t * 0.6;
	float phase = fract(UV.x * arcs + r * swirl * arcs - spin_turns * arcs + seed);
	float lit = 1.0 - wind_band(arc_fill, phase);
	// each arc is a comet: bright head, fading tail
	float head = phase / max(arc_fill, 0.001);
	float hot = wind_band(0.72, head) * wind_band(0.55, r);
	float near = smoothstep(near_fade_from, near_fade_to, length(VERTEX));
	float a = band * lit * (0.35 + 0.65 * head) * fade * (1.0 - t * t) * near;
	vec3 color = mix(edge_color.rgb, core_color.rgb, hot) * energy;
	float inking = ink * band * lit * (1.0 - wind_band(inner + (1.0 - inner) * 0.3, r)) * fade * (1.0 - t) * near;
	ALBEDO = color * a * (1.0 - inking) + ink_color.rgb * inking;
	ALPHA = clamp(inking, 0.0, 1.0);
}
