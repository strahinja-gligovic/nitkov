class_name AnimMove
extends Resource
## How one move looks: a clip (or a stretch of one, optionally spliced onto
## a second) and its key poses in clip seconds. The simulation decides when
## things happen; AnimDirector remaps the clip's time so these keys land on
## the simulation's beats (see TimeRemap). Presentation only.

## Clip in the shared library, e.g. &"ual2/Sword_Regular_A".
@export var clip := &""
## Seconds cut from the clip's start (e.g. a pose an importer holds before
## the first real key, which would stutter a loop). Keys count from the cut.
@export var clip_from := 0.0
## Key poses in clip seconds, ascending. Swings and casts use six: start,
## antic (wind-up extreme), go (strike begins), contact (blade at the target
## or spell leaving the hand), settle (follow-through stops), end.
## Other moves use as many as they need (at least start and end).
@export var keys := PackedFloat32Array()
## When each key lands, as fractions (0..1) of the move's duration. Empty =
## spaced like the clip. Swings and casts ignore this (their beats come from
## the simulation's wind-up, active and recovery).
@export var sim_keys := PackedFloat32Array()
## Seconds a presentation-only move lasts (overlays, death); 0 = as long as
## its keys span in the clip.
@export var duration := 0.0
## Play it left/right mirrored (a right-handed throw from the gauntlet hand).
@export var mirror := false
## Crossfade into this move, seconds.
@export var blend_in := 0.08
## Crossfade out of this move into whatever follows, seconds (moves that end
## far from the guard need longer); 0 = use what follows' blend_in.
@export var blend_out := 0.0
## A cast that only ever takes the left arm and the spine, standing or on
## the move (the sword arm keeps its pose, so its blade can't swing into
## the head).
@export var left_arm_only := false
## A full-body flourish normally gives way as soon as the fighter moves;
## this one plays out (e.g. the short blink arrival).
@export var keep_while_moving := false

@export_group("Swing timing")
## Game seconds from go to contact: the strike itself.
@export var strike := 0.07
## Game seconds the wind-up extreme is held before the strike.
@export var hold := 0.0
## How far into recovery the follow-through settles (0..1).
@export var settle_fraction := 0.5
## The move that eases back to guard when nothing follows this swing.
@export var recover := &""

@export_group("Loop")
## Ground speed in m/s this loop's planted feet cover at its authored rate,
## so playback can be matched to the body's speed (no skating). 0 = not a
## locomotion loop. Its first key is when the left foot plants (phase).
@export var ground_speed := 0.0
## The body speed this loop shows at, unblended (0 = its ground speed); it
## plays at play_at / ground_speed of its authored rate.
@export var play_at := 0.0
## Clip second where the loop part starts (after an entry), for moves that
## enter once and then hold a loop, like raising the guard. 0 = no loop.
@export var loop_from := 0.0

@export_group("Chain")
## A second clip spliced on at `chain_at` seconds into the first (a fall
## flowing into a get-up). Keys then count on the joined timeline.
@export var chain_clip := &""
@export var chain_at := 0.0
## The stretch of the second clip that follows.
@export var chain_from := 0.0
@export var chain_to := 0.0
## Play the second clip mirrored (`mirror` applies to the first only).
@export var chain_mirror := false
## Crossfade at the splice, seconds.
@export var chain_blend := 0.08

@export_group("Slash")
## The slash arc drawn at contact. Angles in degrees around the fighter
## (0 = straight ahead, + = to its right); tilt rolls the swing plane
## (0 = flat sweep, 90 = vertical chop). Equal angles = no arc.
@export var slash_from := 0.0
@export var slash_to := 0.0
@export var slash_tilt := 0.0
@export var slash_height := 1.2


func has_slash() -> bool:
	return not is_equal_approx(slash_from, slash_to)


func has_chain() -> bool:
	return chain_clip != &""


## The prepared clip's name inside its library: mirrored parts carry a
## suffix and spliced chains join their parts ("Hit_Knockback+LayToIdle").
func baked_name() -> String:
	var own := String(clip).get_file() + (AnimLibrary.MIRROR_SUFFIX if mirror else "")
	if clip_from > 0.0:
		own += "@%.3f" % clip_from
	if has_chain():
		own += "+" + String(chain_clip).get_file() + (AnimLibrary.MIRROR_SUFFIX if chain_mirror else "")
	return own


## Seconds the move lasts when it runs on its own clock.
func length() -> float:
	if duration > 0.0:
		return duration
	return keys[keys.size() - 1] - keys[0] if keys.size() > 1 else 0.0
