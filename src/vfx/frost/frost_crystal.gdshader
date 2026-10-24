shader_type spatial;
// Faceted frost ice, opaque: the ink outline pass draws its silhouette (big
// crystals). See frost_crystal.gdshaderinc.
render_mode unshaded, cull_back, shadows_disabled;

#include "res://src/vfx/frost/frost_crystal.gdshaderinc"
