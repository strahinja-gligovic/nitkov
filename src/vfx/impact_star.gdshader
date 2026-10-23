shader_type spatial;
// Comic-book impact accents on a camera-facing quad, each with an ink rim.
// `progress` runs 0..1 over its short life, in held beats like hand-drawn
// effects. `shape` picks the drawing:
//   0 star   a spiky burst that grows and fades (melee, guards, breaks)
//   1 flame  rounded, uneven flame lobes that hollow out and break apart (fire)
//   2 glint  a four-point crystal sparkle that pops full size and shrinks away (frost)
//   3 spark  jagged zigzag spikes, re-drawn every beat and strobing (lightning)
//   4 swirl  three gust strokes spinning outward and thinning (wind)
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.92, 0.6, 1.0);
uniform vec4 ink : source_color = vec4(0.06, 0.03, 0.09, 1.0);
uniform float points = 8.0;
uniform float progress = 0.0;
uniform float energy = 2.5;
uniform float spin = 0.0;
// Effects animate in held beats (~15-20 fps), like hand-drawn effects.
uniform float steps = 5.0;
uniform int shape = 0;
uniform float seed = 0.0;

void vertex() {
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			INV_VIEW_MATRIX[0] * scale.x, INV_VIEW_MATRIX[1] * scale.y, INV_VIEW_MATRIX[2] * scale.z, MODEL_MATRIX[3]);
}

float hash(float n) {
	return fract(sin(n * 12.9898 + 78.233) * 43758.5453);
}

float star(vec2 p, float radius) {
	float a = atan(p.y, p.x) + spin;
	float spikes = 0.38 + 0.62 * pow(abs(cos(a * points * 0.5)), 5.0);
	return 1.0 - smoothstep(radius * spikes - 0.03, radius * spikes, length(p));
}

// Rounded lobes of uneven length (the valleys sit between sectors, so the
// outline stays continuous).
float flame(vec2 p, float radius) {
	float a = atan(p.y, p.x) + spin;
	float sector = floor(a / 6.2832 * points + 0.5);
	float reach = 0.55 + 0.45 * hash(sector + seed);
	float lobe = pow(abs(cos(a * points * 0.5)), 1.3);
	float r = radius * (0.42 + 0.58 * lobe * reach);
	return 1.0 - smoothstep(r - 0.03, r, length(p));
}

// A four-point astroid with long thin spikes, plus shorter diagonals.
float glint(vec2 p, float radius) {
	vec2 q = abs(p) / radius;
	float main_star = sqrt(q.x) + sqrt(q.y);
	vec2 r = abs(vec2(p.x + p.y, p.y - p.x) * 0.7071) / (radius * 0.5);
	float diagonal = sqrt(r.x) + sqrt(r.y);
	return 1.0 - smoothstep(0.93, 1.0, min(main_star, diagonal));
}

// Jagged spikes from the centre; `grow` fattens them for the ink rim.
float spark(vec2 p, float radius, float beat_seed, float grow) {
	float m = 1.0 - smoothstep(radius * 0.16 + grow - 0.02, radius * 0.16 + grow, length(p));
	for (int i = 0; i < 6; i++) {
		float fi = float(i);
		float ang = (fi + hash(fi + beat_seed) * 0.7) * 1.0472 + spin;
		vec2 dir = vec2(cos(ang), sin(ang));
		float u = dot(p, dir);
		float v = dot(p, vec2(-dir.y, dir.x));
		float len = radius * (0.5 + 0.5 * hash(fi * 3.1 + beat_seed));
		if (u < 0.0 || u > len + grow) {
			continue;
		}
		float zig = (abs(fract(u * 4.0 + hash(fi + beat_seed * 1.7)) - 0.5) - 0.25) * 0.24;
		float w = 0.065 * (1.0 - u / (len + grow)) + 0.012 + grow;
		m = max(m, 1.0 - smoothstep(w - 0.012, w, abs(v - zig)));
	}
	return m;
}

// Three tapered gust strokes on a spiral, sliding outward as `beat` grows.
float swirl(vec2 p, float radius, float beat, float grow) {
	float r = length(p) / radius;
	float a = atan(p.y, p.x);
	float inner = 0.2 + beat * 0.5;
	float outer = 0.72 + beat * 0.28;
	if (r < inner - grow * 2.0 || r > outer + grow * 2.0) {
		return 0.0;
	}
	float along = clamp((r - inner) / max(outer - inner, 0.01), 0.0, 1.0);
	float width = (0.5 * sin(along * 3.1416) + grow * 4.0) / max(r, 0.25);
	float m = 0.0;
	for (int i = 0; i < 3; i++) {
		float arm = float(i) * 2.0944 + spin + beat * 1.6 + r * 2.4;
		float da = abs(mod(a - arm + 3.1416, 6.2832) - 3.1416);
		m = max(m, 1.0 - smoothstep(width * 0.75, width, da));
	}
	return m;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float beat = floor(progress * steps + 0.5) / steps;
	float outer = 0.0;
	float inner = 0.0;
	float fade = 1.0 - smoothstep(0.55, 1.0, beat);
	vec3 fill = color.rgb * energy;
	if (shape == 1) {
		// flame: bursts out, then hollows from the middle and breaks up
		float grow = 0.5 + 0.5 * sqrt(beat);
		float hole = smoothstep(0.3, 1.0, beat) * 0.85 * grow;
		float body = flame(p, grow) * (1.0 - step(length(p), hole));
		outer = body;
		inner = flame(p, grow * 0.8) * (1.0 - step(length(p), hole + 0.07));
		float hot = flame(p, grow * 0.48) * (1.0 - step(length(p), hole + 0.12));
		fill = mix(color.rgb, vec3(1.0, 0.95, 0.7), hot) * energy;
		fade = 1.0 - smoothstep(0.7, 1.0, beat);
	} else if (shape == 2) {
		// glint: full size at once, then shrinks to nothing while turning a little
		float size = 1.0 - beat * beat * 0.85;
		vec2 q = mat2(vec2(cos(beat * 0.6), sin(beat * 0.6)), vec2(-sin(beat * 0.6), cos(beat * 0.6))) * p;
		outer = glint(q, size);
		inner = glint(q, size * 0.8);
		float core = glint(q, size * 0.45);
		fill = mix(color.rgb, vec3(1.0), 0.1 + 0.9 * core) * energy;
		fade = 1.0 - step(0.999, beat);
	} else if (shape == 3) {
		// spark: re-drawn on every beat, strobing between full and dim
		float flick = floor(progress * steps * 2.0);
		float beat_seed = seed + flick * 1.37;
		float grow = 0.75 + 0.25 * beat;
		outer = spark(p, grow, beat_seed, 0.035);
		inner = spark(p, grow, beat_seed, 0.0);
		float hot_core = 1.0 - smoothstep(0.12, 0.2, length(p));
		fill = mix(color.rgb, vec3(1.0, 1.0, 0.9), 0.15 + 0.85 * hot_core) * energy;
		fade = (mod(flick, 2.0) < 0.5 ? 1.0 : 0.45) * (1.0 - smoothstep(0.75, 1.0, beat));
	} else if (shape == 4) {
		// swirl: translucent gust strokes
		outer = swirl(p, 1.0, beat, 0.025);
		inner = swirl(p, 1.0, beat, 0.0);
		fill = mix(color.rgb, vec3(1.0), 0.15) * energy;
		fade = 0.9 * (1.0 - smoothstep(0.6, 1.0, beat));
	} else {
		float grow = 0.45 + 0.55 * sqrt(beat);
		outer = star(p, grow);
		inner = star(p, grow * 0.78);
	}
	ALBEDO = mix(ink.rgb, fill, inner);
	ALPHA = outer * fade;
}
