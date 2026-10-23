shader_type spatial;
// Toon look for open, double-sided models (sleeves, collars, hoods): no back-face culling.
render_mode cull_disabled;
#include "res://src/render/toon.gdshaderinc"
