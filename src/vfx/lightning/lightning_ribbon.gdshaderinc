// Shared by the lightning ribbon shaders (LightningArc). Every vertex sits
// on its arc (VERTEX) and carries the arc's direction there (NORMAL), which
// edge of the strip it is (UV.y = -1 or 1), and the strip's half-width and
// brightness (UV2.x, UV2.y). ribbon_position() turns the strip edge-on to the
// camera ray, so an arc faces the camera from any side, and never lets it get
// thinner than min_pixels, so far bolts still read as bolts.

uniform float min_pixels = 1.3;

varying float v_side;
varying float v_bright;

// View-space position of a ribbon vertex. `pad_pixels` widens the strip by a
// fixed number of pixels (the ink backing's outline).
vec3 ribbon_position(vec3 vertex, vec3 normal, float side, float half_width, float pad_pixels,
		mat4 modelview, mat4 projection, vec2 viewport) {
	vec3 centre = (modelview * vec4(vertex, 1.0)).xyz;
	vec3 along = (modelview * vec4(normal, 0.0)).xyz;
	vec3 across = cross(along, centre);
	float n = length(across);
	across = n > 1e-6 ? across / n : vec3(1.0, 0.0, 0.0);
	float pixel = 2.0 * max(-centre.z, 0.05) / (projection[1][1] * viewport.y);
	return centre + across * side * (max(half_width, min_pixels * pixel) + pad_pixels * pixel);
}

// 1 inside `edge`, 0 outside, antialiased over about a pixel.
float band(float edge, float x) {
	float w = max(fwidth(x), 1e-4);
	return clamp((edge - x) / w + 0.5, 0.0, 1.0);
}
