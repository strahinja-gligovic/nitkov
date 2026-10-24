class_name AnimDirector
extends RefCounted
## The animation brain of one fighter. Every frame it reads the fighter's
## simulation state and drives an AnimationTree. It never writes state.
##
##   locomotion   forward loops blended by speed, each placed at the speed
##                its planted feet match (no skating), phase-synced. Other
##                directions turn the legs toward the travel and twist the
##                spine back to the aim (StrideTwistModifier); backpedalling
##                plays the runs in reverse.
##   full body    swings, casts, dashes, reactions, leaps and death, in two
##                crossfading slots. Simulation-timed moves are remapped pose
##                to pose (TimeRemap), so key poses land on the simulation's
##                beats.
##   upper body   the guard, guard impacts and parries over the legs; casts
##                on the move take the left arm only, so the sword arm runs.
##                A cast on a layer keeps its own clip's chest (LayerAim), so
##                it aims the same over a run, a crouch or a leap.
## Lightning's stun twitches (stagger_shock, with ShockJitter shaking the
## body on top); a fighter shoved off the ground
## by a wind burst is shown blown away.
## Presentation-only moves (parry deflect, block impact, combo recoveries,
## landings, the respawn entrance, the kill taunt) run on their own clock
## via play_overlay().

enum Layer { FULL, UPPER }

## Locomotion loops, slowest to fastest.
const LOCO: Array[StringName] = [&"walk", &"run", &"jog", &"sprint"]
## Legs turn at most this far from the facing; past it the feet crab a bit.
const MAX_LEG_YAW := deg_to_rad(75.0)
## A cast starting at this ground speed plays on the upper body only.
const CAST_ON_THE_MOVE_SPEED := 1.0
## A stagger at least this long uses the long stagger move.
const LONG_STAGGER := 1.3
## Off the ground and shoved at least this fast (a wind burst): blown away.
const BLOWN_SPEED := 4.0

var tree: AnimationTree
var moves: MoveSet
## Turns the legs toward the travel direction (set up by FighterVisual).
var stride: StrideTwistModifier
## Debug: move id -> the move shown in its place (AnimGallery compares
## candidates this way). Empty in play.
var stand_ins := {}

var _player: AnimationPlayer
var _full: SlotPair
var _upper: SlotPair
var _left: SlotPair
## Holds a layered cast's chest where its clip has it (see LayerAim).
var _aim: LayerAim
var _aim_fade := 0.0
var _aim_pair: SlotPair
## clip name -> rotation tracks of the bones LayerAim follows (-1 = none)
var _aim_tracks := {}
## Shakes the body while a lightning stun lasts (see ShockJitter).
var _shock: ShockJitter
var _speeds := PackedFloat32Array()
var _moving := 0.0
var _backward := false
var _cast_serial := -1
var _cast_on_the_move := false
var _death: AnimMove
var _death_serial := -1
var _block_time := 0.0
var _air_time := 0.0
var _last_action := FighterState.Action.IDLE
var _last_attack: AttackData
var _overlay: AnimMove
var _overlay_layer := Layer.UPPER
var _overlay_time := 0.0
var _overlay_serial := 0


## Builds the tree under `model` (the node the clips' track paths start
## from). The filters list the "Skeleton:bone" paths each upper layer owns;
## `grip_filter` the sword hand's fingers, which always hold the sword fist
## (clips made without a sword open that hand).
func build(model: Node3D, player: AnimationPlayer, upper_filter: Array[NodePath], left_arm_filter: Array[NodePath],
		grip_filter: Array[NodePath], move_set: MoveSet) -> void:
	moves = move_set
	var root := AnimationNodeBlendTree.new()

	root.add_node(&"idle", _animation(_move(&"idle")))
	var space := AnimationNodeBlendSpace1D.new()
	space.sync_mode = AnimationNodeBlendSpace1D.SYNC_MODE_CYCLIC_MUTABLE
	space.min_space = 0.0
	space.max_space = 14.0
	for id in LOCO:
		var move := moves.get_move(id)
		if move == null or move.ground_speed <= 0.0 or not player.has_animation(clip_name(move)):
			continue
		var at := _loop_speed(move)
		space.add_blend_point(_loop_node(move, player.get_animation(clip_name(move)).length), at, -1, id)
		_speeds.append(at)
	root.add_node(&"space", space)
	root.add_node(&"space_speed", AnimationNodeTimeScale.new())
	root.connect_node(&"space_speed", 0, &"space")
	root.add_node(&"loco", AnimationNodeBlend2.new())
	root.connect_node(&"loco", 0, &"idle")
	root.connect_node(&"loco", 1, &"space_speed")

	_full = SlotPair.new(root, "full", _move(&"idle"))
	root.add_node(&"full", AnimationNodeBlend2.new())
	root.connect_node(&"full", 0, &"loco")
	root.connect_node(&"full", 1, &"full_mix")
	_upper = SlotPair.new(root, "upper", _move(&"idle"))
	root.add_node(&"upper", _filtered(upper_filter))
	root.connect_node(&"upper", 0, &"full")
	root.connect_node(&"upper", 1, &"upper_mix")
	_left = SlotPair.new(root, "left", _move(&"idle"))
	root.add_node(&"left", _filtered(left_arm_filter))
	root.connect_node(&"left", 0, &"upper")
	root.connect_node(&"left", 1, &"left_mix")
	root.add_node(&"fist", _animation(_move(&"idle")))
	root.add_node(&"grip", _filtered(grip_filter))
	root.connect_node(&"grip", 0, &"left")
	root.connect_node(&"grip", 1, &"fist")
	root.connect_node(&"output", 0, &"grip")

	tree = AnimationTree.new()
	tree.name = "AnimationTree"
	tree.tree_root = root
	model.add_child(tree)
	tree.anim_player = tree.get_path_to(player)
	# clips that travel carry it on the root bone; the simulation moves the
	# body, so any root motion is cancelled and the body stays centred
	tree.root_motion_track = NodePath("%s:root" % AnimLibrary.SKELETON_PATH)
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	tree.active = true
	for pair: SlotPair in [_full, _upper, _left]:
		pair.tree = tree
	_player = player
	# added before FighterVisual's procedural layers, so it runs first and
	# they lean, twist and look on top of the steadied chest
	var skeleton := model.get_node_or_null(NodePath(AnimLibrary.SKELETON_PATH)) as Skeleton3D
	if skeleton and skeleton.find_bone(String(LayerAim.CHAIN[LayerAim.CHAIN.size() - 1])) >= 0:
		_aim = LayerAim.new()
		_aim.name = "CastAim"
		skeleton.add_child(_aim)
		_shock = ShockJitter.new()
		_shock.name = "ShockJitter"
		skeleton.add_child(_shock)


## The library name of a move's clip: spliced chains and mirrored copies
## are baked under their own names (see AnimLibrary).
static func clip_name(move: AnimMove) -> StringName:
	return StringName("%s/%s" % [String(move.clip).get_base_dir(), move.baked_name()])


## A presentation-only move on its own clock: the parry deflect, a blocked
## hit's recoil, a combo's recovery, a landing, the respawn entrance, a
## taunt. Simulation actions take precedence on the same layer.
func play_overlay(id: StringName, layer: Layer) -> void:
	var move := moves.get_move(id)
	if move == null or move.keys.size() < 2:
		return
	_overlay = move
	_overlay_layer = layer
	_overlay_time = 0.0
	_overlay_serial += 1


func update(fighter: Fighter, delta: float) -> void:
	var s := fighter.state
	# hit-stop freezes the whole pose; procedural layers keep moving on top
	var dt := 0.0 if s.hitstop > 0.0 else delta
	_note_action_change(s)
	_overlay_time += dt
	if _overlay and _overlay_time >= _overlay.length():
		_overlay = null
	var planar_speed := Vector2(fighter.velocity.x, fighter.velocity.z).length()
	if _overlay and _overlay_layer == Layer.FULL and not _overlay.keep_while_moving and planar_speed > 1.5:
		_overlay = null  # a flourish gives way as soon as you move
	_air_time = _air_time + dt if s.leaping or not s.on_floor else 0.0
	_block_time = _block_time + dt if s.blocking else 0.0
	_show(_full, _full_body(fighter), dt)
	var upper := _upper_body(fighter)
	var left_only := not upper.is_empty() and (upper[0] as AnimMove).left_arm_only
	_show(_upper, [] if left_only else upper, dt)
	_show(_left, upper if left_only else [], dt)
	_update_aim(s, upper, left_only, dt)
	_update_shock(s, delta)
	_update_locomotion(fighter, dt)
	tree.set(&"parameters/full/blend_amount", _full.weight)
	tree.set(&"parameters/upper/blend_amount", _upper.weight)
	tree.set(&"parameters/left/blend_amount", _left.weight)
	tree.set(&"parameters/grip/blend_amount", 1.0)
	tree.advance(dt)


## A swing that ends without another action following plays its recovery,
## so the body flows back to guard instead of snapping.
func _note_action_change(s: FighterState) -> void:
	if _last_action == FighterState.Action.ATTACK and s.action == FighterState.Action.IDLE and _last_attack:
		var move := moves.get_move(_last_attack.animation)
		if move and move.recover != &"":
			play_overlay(move.recover, Layer.FULL)
	if s.action != FighterState.Action.IDLE and _overlay and _overlay_layer == Layer.FULL:
		_overlay = null
	_last_action = s.action
	_last_attack = s.attack if s.action == FighterState.Action.ATTACK else _last_attack


static func _show(pair: SlotPair, pose: Array, dt: float) -> void:
	if pose.is_empty():
		pair.hide(dt)
	else:
		pair.show(pose[0], pose[1], pose[2], dt)


## The full-body move showing now as [AnimMove, clip time, key], or [] for
## locomotion. `key` changes whenever a new move starts.
func _full_body(fighter: Fighter) -> Array:
	var s := fighter.state
	match s.action:
		FighterState.Action.ATTACK:
			var a := s.attack
			var move := _move(a.animation)
			return [move, _swing_time(move, s.action_time, a.windup, a.active, a.recovery), s.action_serial]
		FighterState.Action.CAST:
			if s.action_serial != _cast_serial:
				_cast_serial = s.action_serial
				var planar := Vector2(fighter.velocity.x, fighter.velocity.z).length()
				_cast_on_the_move = planar >= CAST_ON_THE_MOVE_SPEED or not s.on_floor 						or _move(s.spell.animation).left_arm_only
			if not _cast_on_the_move:
				var move := _move(s.spell.animation)
				return [move, _swing_time(move, s.action_time, s.spell.windup, 0.0, s.spell.recovery), s.action_serial]
		FighterState.Action.DASH:
			var move := _move(_dash_move(s))
			return [move, _keyed_time(move, s.action_time, s.action_duration), s.action_serial]
		FighterState.Action.FLINCH:
			var move := _move(&"flinch_heavy" if s.action_duration >= 0.35 else &"flinch")
			return [move, _keyed_time(move, s.action_time, s.action_duration), s.action_serial]
		FighterState.Action.STAGGER:
			var move := _move(_stagger_move(s))
			return [move, _keyed_time(move, s.action_time, s.action_duration), s.action_serial]
		FighterState.Action.DEAD:
			if s.action_serial != _death_serial:
				_death_serial = s.action_serial
				_death = _pick_death(fighter)
			return [_death, _keyed_time(_death, s.action_time, _death.length()), s.action_serial]
	if not s.on_floor and not s.leaping and s.knockback.length() > BLOWN_SPEED and moves.has_move(&"blown"):
		# flung backward or aside: legs swept up; flung forward (a burst behind you): a tuck
		if s.knockback.normalized().dot(fighter.forward()) > 0.5:
			var tuck := _move(&"leap_air")
			return [tuck, _loop_time(tuck, _air_time), "blown_forward"]
		var blown := _move(&"blown")
		return [blown, _keyed_time(blown, _air_time, blown.length()), "blown"]
	if s.leaping or (not s.on_floor and fighter.velocity.y < -3.0):
		var start := _move(&"leap_start")
		if s.leaping and _air_time < start.length() and fighter.velocity.y > 0.0:
			return [start, _keyed_time(start, _air_time, start.length()), "leap"]
		if fighter.velocity.y < -1.5:
			var fall := _move(&"leap_fall")
			return [fall, _loop_time(fall, _air_time), "fall"]
		var air := _move(&"leap_air")
		return [air, _loop_time(air, _air_time), "air"]
	if _overlay and _overlay_layer == Layer.FULL:
		return [_overlay, _keyed_time(_overlay, _overlay_time, _overlay.length()), "overlay%d" % _overlay_serial]
	return []


func _upper_body(fighter: Fighter) -> Array:
	var s := fighter.state
	if s.action == FighterState.Action.CAST and _cast_on_the_move:
		var move := _move(s.spell.animation)
		return [move, _swing_time(move, s.action_time, s.spell.windup, 0.0, s.spell.recovery), s.action_serial]
	if s.action != FighterState.Action.IDLE:
		return []
	if _overlay and _overlay_layer == Layer.UPPER:
		return [_overlay, _keyed_time(_overlay, _overlay_time, _overlay.length()), "overlay%d" % _overlay_serial]
	if s.blocking:
		var guard := _move(&"block")
		return [guard, _enter_then_loop(guard, _block_time), "guard"]
	return []


## A cast showing as a layer keeps its clip's chest (LayerAim). The hold lets
## go over a blend-out once the cast is over, even if the layer moves on to
## the guard.
func _update_aim(s: FighterState, layer_pose: Array, left_only: bool, dt: float) -> void:
	if _aim == null:
		return
	var casting := s.action == FighterState.Action.CAST and not layer_pose.is_empty()
	if casting:
		_aim_pair = _left if left_only else _upper
		_aim.locals = _clip_chest(layer_pose[0], layer_pose[1])
		_aim_fade = 1.0
	else:
		_aim_fade = move_toward(_aim_fade, 0.0, dt / 0.15)
	_aim.weight = _aim_fade * (_aim_pair.weight if _aim_pair else 0.0)


## A lightning stun shakes hard at first and dies down; it keeps shaking
## through hit-stop (real time, not the frozen clip clock).
func _update_shock(s: FighterState, delta: float) -> void:
	if _shock == null:
		return
	if s.action == FighterState.Action.STAGGER and s.stagger_kind == &"shock":
		var t := clampf(s.action_time / maxf(s.action_duration, 0.01), 0.0, 1.0)
		var tail := clampf((s.action_duration - s.action_time) / 0.12, 0.0, 1.0)
		_shock.weight = lerpf(1.0, 0.45, t) * tail
	else:
		_shock.weight = move_toward(_shock.weight, 0.0, delta / 0.08)


## 0..1: how hard a lightning stun is shaking the skeleton right now.
func shock_weight() -> float:
	return _shock.weight if _shock else 0.0


## Local rotations of LayerAim's bones in `move`'s clip at `time`.
func _clip_chest(move: AnimMove, time: float) -> Array[Quaternion]:
	var clip_id := clip_name(move)
	var clip := _player.get_animation(clip_id) if _player.has_animation(clip_id) else null
	if not _aim_tracks.has(clip_id):
		var found := PackedInt32Array()
		for bone_name in LayerAim.CHAIN:
			var path := NodePath("%s:%s" % [AnimLibrary.SKELETON_PATH, bone_name])
			found.append(clip.find_track(path, Animation.TYPE_ROTATION_3D) if clip else -1)
		_aim_tracks[clip_id] = found
	var tracks: PackedInt32Array = _aim_tracks[clip_id]
	var skeleton := _aim.get_skeleton()
	var out: Array[Quaternion] = []
	for i in LayerAim.CHAIN.size():
		if tracks[i] >= 0:
			out.append(clip.rotation_track_interpolate(tracks[i], time))
		else:
			out.append(skeleton.get_bone_rest(skeleton.find_bone(LayerAim.CHAIN[i])).basis.get_rotation_quaternion())
	return out


func _update_locomotion(fighter: Fighter, dt: float) -> void:
	var forward := fighter.forward()
	var right := Vector3(-forward.z, 0.0, forward.x)
	var v := Vector2(fighter.velocity.dot(right), fighter.velocity.dot(forward))
	var speed := v.length()
	# the body reaches running speed in about a tenth of a second: keep up
	_moving = move_toward(_moving, smoothstep(0.2, 1.2, speed), dt / 0.07)
	var scale := 1.0
	if speed > 0.3:
		var angle := atan2(v.x, v.y)  # 0 = ahead, + = to the right
		if _backward and absf(angle) < deg_to_rad(80.0):
			_backward = false
		elif not _backward and absf(angle) > deg_to_rad(100.0):
			_backward = true
		var leg := wrapf(angle - PI, -PI, PI) if _backward else angle
		if stride:
			stride.leg_yaw = clampf(leg, -MAX_LEG_YAW, MAX_LEG_YAW)
	if not _speeds.is_empty():
		var at := clampf(speed, _speeds[0], _speeds[_speeds.size() - 1])
		tree.set(&"parameters/space/blend_position", at)
		scale = clampf(speed / at, 0.4, 1.6) if speed > 0.05 else 1.0
	tree.set(&"parameters/space_speed/scale", -scale if _backward else scale)
	tree.set(&"parameters/loco/blend_amount", _moving)
	if stride:
		# swings, dashes and reactions bring their own footwork
		stride.amount = _moving * (1.0 - _full.weight)


## Distance from the origin along `dir` to the edge of a convex polygon that
## contains the origin (0 if it doesn't reach).
static func ray_to_polygon(dir: Vector2, polygon: PackedVector2Array) -> float:
	var best := 0.0
	var far := dir * 1000.0
	for i in polygon.size():
		var hit: Variant = Geometry2D.segment_intersects_segment(Vector2.ZERO, far, polygon[i], polygon[(i + 1) % polygon.size()])
		if hit != null:
			best = maxf(best, (hit as Vector2).length())
	return best


# --- clip time for each kind of move ------------------------------------------

func _swing_time(move: AnimMove, t: float, windup: float, active: float, recovery: float) -> float:
	if move.keys.size() != 6:
		return _keyed_time(move, t, windup + active + recovery)
	var sim := TimeRemap.swing_keys(windup, active, recovery, move.strike, move.hold, move.settle_fraction)
	return TimeRemap.map(t, sim, move.keys)


func _keyed_time(move: AnimMove, t: float, duration: float) -> float:
	return TimeRemap.timed(t, duration, move.keys, move.sim_keys)


## Plays the entry once, then loops from loop_from to the last key.
func _enter_then_loop(move: AnimMove, t: float) -> float:
	var start := move.keys[0]
	var end := move.keys[move.keys.size() - 1]
	if move.loop_from <= start or move.loop_from >= end or start + t < move.loop_from:
		return minf(start + t, end)
	return move.loop_from + fposmod(start + t - move.loop_from, end - move.loop_from)


func _loop_time(move: AnimMove, t: float) -> float:
	var first := move.keys[0]
	return first + fposmod(t, maxf(move.keys[move.keys.size() - 1] - first, 0.001))


# --- picking moves ------------------------------------------------------------

func _dash_move(s: FighterState) -> StringName:
	var forward := CombatRules.yaw_to_dir(s.facing_yaw)
	var right := Vector3(-forward.z, 0.0, forward.x)
	var f := s.dash_dir.dot(forward)
	var r := s.dash_dir.dot(right)
	if absf(f) >= absf(r):
		return &"dash_f" if f >= 0.0 else &"dash_b"
	return &"dash_r" if r > 0.0 else &"dash_l"


func _stagger_move(s: FighterState) -> StringName:
	match s.stagger_kind:
		&"guard_break":
			return &"guard_break"
		&"shatter":
			return &"knockdown"
		&"shock":
			if moves.has_move(&"stagger_shock"):
				return &"stagger_shock"
	return &"stagger_long" if s.action_duration >= LONG_STAGGER and moves.has_move(&"stagger_long") else &"stagger"


func _pick_death(fighter: Fighter) -> AnimMove:
	var options: Array[AnimMove] = []
	for id: StringName in moves.moves:
		if String(id).begins_with("death"):
			options.append(moves.moves[id])
	if options.is_empty():
		return _move(&"idle")
	return options[(fighter.get_instance_id() + fighter.state.action_serial) % options.size()]


## A move by id; a missing one falls back to idle so a gap shows as a pose, not a crash.
func _move(id: StringName) -> AnimMove:
	var move := moves.get_move(stand_ins.get(id, id))
	return move if move != null else moves.get_move(&"idle")


static func _loop_speed(move: AnimMove) -> float:
	return move.play_at if move.play_at > 0.0 else move.ground_speed


## A locomotion loop stretched so its feet match the speed it's placed at,
## starting on its left-foot plant so every loop's stride lines up.
static func _loop_node(move: AnimMove, clip_length: float) -> AnimationNodeAnimation:
	var node := _animation(move)
	node.use_custom_timeline = true
	node.timeline_length = clip_length * move.ground_speed / _loop_speed(move)
	node.stretch_time_scale = true
	node.start_offset = move.keys[0] if move.keys.size() > 0 else 0.0
	node.loop_mode = Animation.LOOP_LINEAR
	return node


static func _animation(move: AnimMove) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	if move:
		node.animation = clip_name(move)
	return node


static func _filtered(paths: Array[NodePath]) -> AnimationNodeBlend2:
	var blend := AnimationNodeBlend2.new()
	blend.filter_enabled = true
	for path in paths:
		blend.set_filter_path(path, true)
	return blend


## Two animation slots that crossfade: a new move starts in the idle slot and
## fades in over its blend_in while the old one fades out where it was.
class SlotPair:
	## Moves blending in this fast cut straight to their pose.
	const SNAP := 0.03

	var tree: AnimationTree
	## 0..1: how much of this layer shows over what's beneath it.
	var weight := 0.0

	var _prefix := ""
	var _slots: Array[AnimationNodeAnimation] = []
	var _active := 0
	var _key := ""
	var _mix := 0.0
	var _blend_in := 0.08
	var _blend_out := 0.0

	func _init(root: AnimationNodeBlendTree, prefix: String, placeholder: AnimMove) -> void:
		_prefix = prefix
		for i in 2:
			var slot := AnimDirector._animation(placeholder)
			_slots.append(slot)
			root.add_node(StringName("%s_%d" % [prefix, i]), slot)
			var seek := AnimationNodeTimeSeek.new()
			seek.explicit_elapse = false
			root.add_node(StringName("%s_%d_seek" % [prefix, i]), seek)
			root.connect_node(StringName("%s_%d_seek" % [prefix, i]), 0, StringName("%s_%d" % [prefix, i]))
		root.add_node(StringName("%s_mix" % prefix), AnimationNodeBlend2.new())
		root.connect_node(StringName("%s_mix" % prefix), 0, StringName("%s_0_seek" % prefix))
		root.connect_node(StringName("%s_mix" % prefix), 1, StringName("%s_1_seek" % prefix))

	func show(move: AnimMove, time: float, key: Variant, dt: float) -> void:
		var clip := AnimDirector.clip_name(move)
		var key_text := str(key)
		if key_text != _key or _slots[_active].animation != clip:
			# a move that ends far from what follows asks for a longer crossfade,
			# but a blow still snaps the body into its reaction
			_blend_in = move.blend_in if move.blend_in <= SNAP else maxf(move.blend_in, _blend_out if weight > 0.05 else 0.0)
			_blend_out = move.blend_out
			if weight > 0.05:
				_active = 1 - _active  # crossfade from the other slot
			_slots[_active].animation = clip
			_key = key_text
			if weight <= 0.05 or _blend_in <= SNAP:
				_mix = float(_active)
			if _blend_in <= SNAP:
				weight = 1.0  # a blow snaps the body into its pose, even through hit-stop
		tree.set("parameters/%s_%d_seek/seek_request" % [_prefix, _active], time)
		var rate := dt / maxf(_blend_in, 0.001)
		weight = move_toward(weight, 1.0, rate) if _blend_in > SNAP else 1.0
		_mix = move_toward(_mix, float(_active), rate)
		tree.set("parameters/%s_mix/blend_amount" % _prefix, _mix)

	func hide(dt: float) -> void:
		_key = ""
		weight = move_toward(weight, 0.0, dt / maxf(_blend_out, 0.12))


## Turns the spine of a cast playing as a layer (left arm, or the upper body
## on the move or in the air) so the chest faces where it faces in the cast's
## own clip, relative to the character, whatever the legs below are doing.
## The layer copies the clip's spine rotations, but they hang off another
## pelvis: a run leans forward and twists, the sword idle crouches, so a jab
## that is level in its clip would punch the floor on the run. Half the turn
## goes to spine_01 and half to spine_02, so the waist doesn't kink.
class LayerAim extends SkeletonModifier3D:
	const CHAIN: Array[StringName] = [&"pelvis", &"spine_01", &"spine_02"]

	## Local rotations of CHAIN in the cast's clip, this frame.
	var locals: Array[Quaternion] = []
	## 0..1: how far the chest turns to the clip's.
	var weight := 0.0

	var _bones := PackedInt32Array()

	func _process_modification_with_delta(_delta: float) -> void:
		if weight <= 0.001 or locals.size() != CHAIN.size():
			return
		var skeleton := get_skeleton()
		if skeleton == null:
			return
		if _bones.is_empty():
			for bone_name in CHAIN:
				_bones.append(skeleton.find_bone(bone_name))
		if -1 in _bones:
			return
		var above := skeleton.get_bone_parent(_bones[0])
		var base := _global_rotation(skeleton, above) if above >= 0 else Quaternion.IDENTITY
		var target := base * locals[0] * locals[1] * locals[2]
		var pelvis_now := _global_rotation(skeleton, _bones[0])
		var lower_now := _global_rotation(skeleton, _bones[1])
		var chest_now := _global_rotation(skeleton, _bones[2])
		var turn := chest_now.slerp(target, weight) * chest_now.inverse()
		var lower := Quaternion.IDENTITY.slerp(turn, 0.5) * lower_now
		skeleton.set_bone_pose_rotation(_bones[1], (pelvis_now.inverse() * lower).normalized())
		skeleton.set_bone_pose_rotation(_bones[2], (lower.inverse() * turn * chest_now).normalized())

	static func _global_rotation(skeleton: Skeleton3D, bone: int) -> Quaternion:
		return skeleton.get_bone_global_pose(bone).basis.orthonormalized().get_rotation_quaternion()


## Electrocution on top of the stagger_shock clip. The clip gives the braced
## legs and the flung-up arms; this locks them into a rigid star (arms pulled
## out wide, elbows and wrists clenched, back arched, head thrown back) and
## makes the body chatter: every couple of frames each bone flips to the other
## side of its own jolt axis, with no easing, so it strobes like the arcs.
## Presentation only. Turns are in skeleton space (about the character's right,
## up and forward), so they read the same whatever the bones' local axes are.
class ShockJitter extends SkeletonModifier3D:
	## bone -> chatter amplitude in degrees
	const JOLTS := {
		&"pelvis": 3.0, &"spine_01": 4.0, &"spine_02": 5.0, &"spine_03": 6.0, &"neck_01": 8.0, &"Head": 12.0,
		&"clavicle_l": 6.0, &"clavicle_r": 6.0, &"upperarm_l": 10.0, &"upperarm_r": 10.0,
		&"lowerarm_l": 16.0, &"lowerarm_r": 16.0, &"hand_l": 24.0, &"hand_r": 24.0,
		&"thigh_l": 3.0, &"thigh_r": 3.0, &"calf_l": 4.0, &"calf_r": 4.0,
	}
	## bone -> the held rigid pose: [degrees about right (+ arches back),
	## degrees about forward (+ tips toward the character's right)]
	const RIGID := {
		&"spine_02": [8.0, 0.0], &"spine_03": [10.0, 0.0], &"Head": [22.0, 0.0],
		&"upperarm_l": [0.0, -50.0], &"upperarm_r": [0.0, 50.0],
		&"lowerarm_l": [0.0, 45.0], &"lowerarm_r": [0.0, -45.0],
		&"hand_l": [-30.0, 0.0], &"hand_r": [-30.0, 0.0],
	}
	## the chatter flips about this often (seconds)
	const JOLT_EVERY := 0.04

	## 0..1: how hard it shakes (the director fades it in and out).
	var weight := 0.0

	var _bones := PackedInt32Array()
	var _amps := PackedFloat32Array()
	var _rigid: Array[Vector2] = []
	var _axes: Array[Vector3] = []
	var _sizes := PackedFloat32Array()
	var _side := 1.0
	var _clock := 0.0
	var _right := Vector3.RIGHT
	var _forward := Vector3.BACK

	func _process_modification_with_delta(delta: float) -> void:
		var skeleton := get_skeleton()
		if skeleton == null or weight <= 0.001:
			return
		if _bones.is_empty():
			_find_bones(skeleton)
		_clock -= delta
		if _clock <= 0.0:
			_clock = JOLT_EVERY * randf_range(0.6, 1.4)
			_side = -_side
			for i in _bones.size():
				if randf() < 0.3:  # now and then the current kicks another way
					_axes[i] = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
				_sizes[i] = randf_range(0.4, 1.0)
		var set_in := minf(weight * 2.5, 1.0)
		for i in _bones.size():
			var turn := Quaternion(_axes[i], deg_to_rad(_amps[i]) * _sizes[i] * _side * weight)
			var rigid := _rigid[i] * set_in
			if rigid != Vector2.ZERO:
				turn = Quaternion(_forward, deg_to_rad(rigid.y)) * Quaternion(_right, deg_to_rad(rigid.x)) * turn
			_turn(skeleton, _bones[i], turn)

	func _find_bones(skeleton: Skeleton3D) -> void:
		# parents before children, so each turn carries down the chain
		for bone_name: StringName in JOLTS:
			var bone := skeleton.find_bone(bone_name)
			if bone >= 0:
				_bones.append(bone)
				_amps.append(JOLTS[bone_name])
				var held: Array = RIGID.get(bone_name, [0.0, 0.0])
				_rigid.append(Vector2(held[0], held[1]))
				_axes.append(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized())
				_sizes.append(0.0)
		var left := skeleton.find_bone(&"upperarm_l")
		var right := skeleton.find_bone(&"upperarm_r")
		var pelvis := skeleton.find_bone(&"pelvis")
		var head := skeleton.find_bone(&"Head")
		if left >= 0 and right >= 0 and pelvis >= 0 and head >= 0:
			var across := skeleton.get_bone_global_rest(right).origin - skeleton.get_bone_global_rest(left).origin
			var up := skeleton.get_bone_global_rest(head).origin - skeleton.get_bone_global_rest(pelvis).origin
			if across.length() > 0.01 and up.length() > 0.01:
				_right = across.normalized()
				_forward = up.normalized().cross(_right).normalized()

	## Turns `bone` by `turn` given in skeleton space.
	static func _turn(skeleton: Skeleton3D, bone: int, turn: Quaternion) -> void:
		var parent := skeleton.get_bone_parent(bone)
		var above := Quaternion.IDENTITY
		if parent >= 0:
			above = skeleton.get_bone_global_pose(parent).basis.orthonormalized().get_rotation_quaternion()
		var local := skeleton.get_bone_pose_rotation(bone)
		skeleton.set_bone_pose_rotation(bone, (above.inverse() * turn * above * local).normalized())
