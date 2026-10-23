shader_type spatial;
// A roiling ball of fire (see fire_ball_body.gdshaderinc): the Firebolt's
// head, the charge in the fist, muzzle jets and explosion fireballs at their
// peak. It renders in the opaque pass, so the edges stay crisp and the ink
// outline pass draws around it like everything else.
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;

#include "res://src/vfx/fire/fire_ball_body.gdshaderinc"
