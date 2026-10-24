shader_type spatial;
// Faceted frost ice drawn after the ink outline pass, so small bits stay
// bright ice instead of turning into black specks of ink. Still writes depth,
// so the bits hide each other properly. See frost_crystal.gdshaderinc.
render_mode unshaded, cull_back, shadows_disabled, depth_draw_always;

#define GLASS
#include "res://src/vfx/frost/frost_crystal.gdshaderinc"
