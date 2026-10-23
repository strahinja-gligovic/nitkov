shader_type spatial;
// The same fireball (see fire_ball_body.gdshaderinc), drawn in the
// transparent pass so the screen-space ink outline never sees it. Burning-out
// fireballs switch to it: in the opaque pass every torn scrap of a dissolving
// ball got its own ink outline and read as a spray of black confetti. The
// depth prepass keeps the ball sorted against itself.
render_mode unshaded, cull_disabled, depth_prepass_alpha, shadows_disabled, fog_disabled;

#define FIRE_BALL_SOFT
#include "res://src/vfx/fire/fire_ball_body.gdshaderinc"
