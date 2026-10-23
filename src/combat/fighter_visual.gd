class_name FighterVisual
extends Node3D
## Displays a fighter: an assembled character (CharacterRig) animated by an
## AnimDirector, procedural layers on top, and the combat effects that ride
## on the body. Every frame it reads Fighter.state; it never writes it.
##
##   body      drawn between physics ticks (TickSmoother); turns through a
##             spring instead of snapping, squashes and stretches on
##             landings, take-offs, dashes and hits, shakes through hit-stop
##             (BodyDynamics);
##   skeleton  the director's clips, then legs turned toward the travel
##             (StrideTwistModifier), a spine lean into acceleration
##             (LeanModifier), a head look-at, breathing, and a spring-driven
##             bend away from each blow (HitReactModifier);
##   effects   blade trail and slash arc on swings, the heavy's ready flash,
##             afterimages on dashes and blinks, the gauntlet's glow and
##             each spell's charge-up and release (SpellFx), status tints,
##             shock arcs and hit flashes.

const TRAIL_STEEL := [Color(0.92, 0.97, 1.0), Color(0.45, 0.68, 1.0)]
const TRAIL_HEAVY := [Color(1.0, 0.9, 0.62), Color(1.0, 0.42, 0.1)]
const GHOST_DASH := Color(0.55, 0.8, 1.0)
const GHOST_BLINK := Color(0.8, 0.6, 1.0)
## The heavy flashes this long before it lands: the last call to parry.
const READY_FLASH_LEAD := 0.12
const GHOST_INTERVAL := 0.04
## The slash arc's outer radius around the chest: about arm plus blade.
const SLASH_RADIUS := 1.5
## Seconds after a kill in which the taunt can still start.
const TAUNT_WINDOW := 1.5

var fighter: Fighter
var rig: CharacterRig
var director: AnimDirector
var materials: Array[ShaderMaterial] = []
var sword_materials: Array[ShaderMaterial] = []

var _pivot: Node3D
var _dynamics := BodyDynamics.new()
var _smoother: TickSmoother
var _trail: WeaponTrail
var _ghosts: Afterimages
var _hit_react: HitReactModifier
var _stride: StrideTwistModifier
var _lean: LeanModifier
var _breath: BreathModifier
var _look: LookAtModifier3D
var _look_target: Node3D
var _look_weight := 0.0
var _shake_dir := Vector3.ZERO
var _shake_strength := 0.0
var _shake_time := 1.0
var _swing_serial := -1
var _contact_shown := false
var _ready_shown := false
var _ready_glow := 0.0
var _ghost_timer := 0.0
var _dash_serial := -1
var _cast_serial := -1
var _shock_serial := -1
var _was_leaping := false
var _taunt_until := -1.0
var _flash := 0.0
var _last_hp := -1.0
var _time := 0.0
var _gauntlet_root: Node3D
var _gauntlet_core: MeshInstance3D
var _gauntlet_light: OmniLight3D
var _built_character: CharacterData
## World-space sword tip and feet (ball bones) as last drawn, procedural
## layers included (read by the trail, the ready flash and debug probes).
var drawn_tip := Vector3.ZERO
var drawn_feet: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]


func _ready() -> void:
	fighter = get_parent() as Fighter
	top_level = true
	process_physics_priority = 100  # sample the body after it has moved this tick
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)
	_look_target = Node3D.new()
	_look_target.name = "LookTarget"
	_look_target.top_level = true
	add_child(_look_target)
	_trail = WeaponTrail.new()
	_trail.name = "BladeTrail"
	add_child(_trail)
	_ghosts = Afterimages.new()
	_ghosts.name = "Afterimages"
	add_child(_ghosts)
	_smoother = TickSmoother.new(fighter)
	_dynamics.reset(fighter.state.facing_yaw)
	_build_model()
	fighter.loadout_changed.connect(_on_loadout_changed)
	CombatEvents.hit_resolved.connect(_on_hit_resolved)
	CombatEvents.fighter_respawned.connect(_on_respawned)
	CombatEvents.landed.connect(_on_landed)
	CombatEvents.fighter_died.connect(_on_died)
	CombatEvents.spell_cast.connect(_on_spell_cast)
	_place(0.0)


func _on_loadout_changed() -> void:
	if fighter.character != _built_character:
		_build_model()
	else:
		_build_gauntlet()


## Assembles the character, hands it the shared clips, and builds the
## animation tree, the procedural layers and the blade trail around it.
func _build_model() -> void:
	if rig:
		_pivot.remove_child(rig)
		rig.queue_free()
		_gauntlet_root = null
		_gauntlet_core = null
	_built_character = fighter.character
	rig = CharacterRig.build(fighter.character)
	_pivot.add_child(rig)
	materials = rig.materials
	sword_materials = rig.sword_materials
	AnimLibrary.attach(rig.anim_player, rig.skeleton, GameData.moves)
	director = AnimDirector.new()
	director.build(rig.model, rig.anim_player, rig.upper_body_filter(), rig.left_arm_filter(), rig.grip_filter(),
			GameData.moves)
	_build_modifiers()
	director.stride = _stride
	_trail.setup(rig.sword, rig.sword_hilt, rig.sword_tip)
	_trail.clear()
	rig.skeleton.skeleton_updated.connect(_on_pose_final)
	_ghosts.setup(rig, rig.skeleton, GHOST_DASH, 8)
	_build_gauntlet()


## Directional legs, lean, head look-at, breathing and hit reactions, applied
## in that order on top of the animation. The skeleton runs them when we say so
## (after the clips).
func _build_modifiers() -> void:
	var skeleton := rig.skeleton
	skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	_stride = StrideTwistModifier.new()
	_stride.name = "StrideTwist"
	skeleton.add_child(_stride)
	_lean = LeanModifier.new()
	_lean.name = "Lean"
	_lean.spine_bones = rig.spine_bones
	skeleton.add_child(_lean)
	_look = LookAtModifier3D.new()
	_look.name = "LookAt"
	_look.bone_name = rig.head_bone
	_look.forward_axis = rig.head_forward_axis
	_look.primary_rotation_axis = rig.head_up_axis
	_look.use_secondary_rotation = true
	_look.relative = true
	_look.use_angle_limitation = true
	_look.symmetry_limitation = true
	_look.primary_limit_angle = deg_to_rad(130.0)
	_look.primary_damp_threshold = 0.7
	_look.secondary_limit_angle = deg_to_rad(70.0)
	_look.secondary_damp_threshold = 0.7
	_look.duration = 0.18
	_look.transition_type = Tween.TRANS_SINE
	_look.ease_type = Tween.EASE_OUT
	_look.influence = 0.0
	skeleton.add_child(_look)
	_look.target_node = _look.get_path_to(_look_target)
	_breath = BreathModifier.new()
	_breath.name = "Breath"
	_breath.chest_bone = rig.chest_bone
	_breath.head_bone = rig.neck_bone
	skeleton.add_child(_breath)
	_hit_react = HitReactModifier.new()
	_hit_react.name = "HitReact"
	_hit_react.setup(rig.spine_bones, [0.3, 0.35, 0.35], rig.head_bone)
	skeleton.add_child(_hit_react)


func _physics_process(_delta: float) -> void:
	if _smoother.tick() and _just_blinked():
		_leave_blink_trail(_smoother.jumped_from, fighter.global_position)


func _process(delta: float) -> void:
	if rig == null:
		return
	_time += delta
	var s := fighter.state
	_place(delta)
	director.update(fighter, delta)
	_update_procedural(s, delta)
	rig.skeleton.advance(delta)
	_update_swing_effects(s, delta)
	_update_ghosts(s, delta)
	_update_taunt(s)
	_update_gauntlet(s)
	_update_status_tint(s)
	_update_shock(s)
	_update_flash(s, delta)
	_update_tells(s)


## The skeleton has its final pose for this frame (clips plus procedural
## layers; it is restored right after, so this is the moment to read it).
func _on_pose_final() -> void:
	var skeleton := rig.skeleton
	var blade := rig.sword_transform()
	drawn_tip = blade * rig.sword_tip
	for i in 2:
		var bone := skeleton.find_bone("ball_l" if i == 0 else "ball_r")
		drawn_feet[i] = skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
	_trail.push(blade)


# --- the body -------------------------------------------------------------------

func _place(delta: float) -> void:
	global_transform = Transform3D(Basis(), _smoother.position())
	var s := fighter.state
	_dynamics.update(delta, s.facing_yaw, fighter.velocity)
	var yaw := s.facing_yaw + _dynamics.yaw_offset(s.facing_yaw)
	_shake_time += delta
	var shake := Vector3.ZERO
	if _shake_strength > 0.0 and _shake_time < 0.3:
		shake = _shake_dir * _shake_strength * sin(_shake_time * 95.0) * exp(-_shake_time * 14.0)
	shake += _tremble(s)
	_pivot.transform = Transform3D(Basis(Vector3.UP, yaw) * _dynamics.squash_basis(), shake)
	if _lean:
		_lean.pitch = _dynamics.lean().x
		_lean.roll = _dynamics.lean().y


## A heavy's held wind-up trembles with strain, building toward the strike.
func _tremble(s: FighterState) -> Vector3:
	if s.action != FighterState.Action.ATTACK or not s.attack.hyperarmor or s.hitstop > 0.0:
		return Vector3.ZERO
	var move := GameData.moves.get_move(s.attack.animation)
	if move == null:
		return Vector3.ZERO
	var a := s.attack
	var keys := TimeRemap.swing_keys(a.windup, a.active, a.recovery, move.strike, move.hold, move.settle_fraction)
	if s.action_time < keys[1] or s.action_time >= keys[2]:
		return Vector3.ZERO
	var build := inverse_lerp(keys[1], keys[2], s.action_time)
	return Vector3(sin(_time * 251.0), sin(_time * 197.0 + 1.0) * 0.5, cos(_time * 223.0)) * 0.007 * (0.4 + build)


## A short, decaying shudder along `direction` (hit-stop sells the impact).
func _shake(direction: Vector3, strength: float) -> void:
	_shake_dir = direction.normalized() if direction.length() > 0.01 else Vector3.ZERO
	_shake_strength = strength
	_shake_time = 0.0


func _update_procedural(s: FighterState, delta: float) -> void:
	var calm := s.action == FighterState.Action.IDLE
	_breath.winded = 1.0 if s.exhausted > 0.0 else clampf(1.0 - s.stamina / maxf(s.max_stamina, 1.0), 0.0, 1.0) * 0.8
	var breathing := 0.0 if s.is_dead() else (1.0 if calm else 0.3)
	_breath.amount = move_toward(_breath.amount, breathing, delta / 0.25)
	var looking := calm or s.action == FighterState.Action.CAST
	_look_weight = move_toward(_look_weight, 1.0 if looking else 0.0, delta / 0.15)
	_look.influence = _look_weight
	_look_target.global_position = _look_point()


## The nearest enemy's face if one is roughly in front, else straight ahead.
func _look_point() -> Vector3:
	var head := fighter.global_position + Vector3.UP * 1.6
	var best: Fighter = null
	var best_distance := 30.0
	for enemy in fighter.enemies():
		var to := enemy.global_position - fighter.global_position
		var distance := to.length()
		if distance < best_distance and fighter.forward().dot(to.normalized()) > -0.3:
			best = enemy
			best_distance = distance
	if best:
		return best.global_position + Vector3.UP * 1.6
	return head + fighter.forward() * 10.0


# --- events -----------------------------------------------------------------------

func _on_hit_resolved(attacker: Node, defender: Node, result: HitResult, at: Vector3) -> void:
	if (defender != fighter and attacker != fighter) or rig == null:
		return
	if result.periodic and result.reaction == &"":
		return
	var source := at
	if attacker is Node3D and attacker != defender:
		source = (attacker as Node3D).global_position
	var push := (defender as Node3D).global_position - source
	push.y = 0.0
	push = push.normalized() if push.length() > 0.01 else -fighter.forward()
	var to_skeleton := rig.skeleton.global_basis.inverse()
	if defender == fighter:
		var strength := 0.35 + result.damage / 30.0
		match result.outcome:
			HitResult.Outcome.BLOCKED:
				strength = 0.3
				director.play_overlay(&"block_impact", AnimDirector.Layer.UPPER)
			HitResult.Outcome.PARRIED:
				strength = 0.2
				director.play_overlay(&"parry", AnimDirector.Layer.UPPER)
			HitResult.Outcome.GUARD_BREAK:
				strength = 1.0
		if result.reaction == &"shatter":
			strength = 1.3
		_hit_react.impulse(to_skeleton * push, strength)
		_shake(push, 0.035 * strength)
		_dynamics.squash(0.08 * strength)
	else:
		match result.outcome:
			HitResult.Outcome.BLOCKED, HitResult.Outcome.PARRIED:
				# the blade bounces off the guard
				_hit_react.impulse(to_skeleton * -push, 0.35)
				_shake(-push, 0.02)
			_:
				_shake(push, 0.012)


func _on_respawned(who: Node) -> void:
	if who != fighter or rig == null:
		return
	_smoother.reset()
	_dynamics.reset(fighter.state.facing_yaw)
	_hit_react.reset()
	_stride.reset()
	_trail.clear()
	director.play_overlay(&"entrance", AnimDirector.Layer.FULL)
	_place(0.0)


## A little celebration when you take someone down: once the killing blow
## has played out, if you're standing free within a moment of it.
func _on_died(_who: Node, killer: Node) -> void:
	if killer == fighter:
		_taunt_until = _time + TAUNT_WINDOW


func _update_taunt(s: FighterState) -> void:
	if _taunt_until < _time:
		return
	var free := s.action == FighterState.Action.IDLE and not s.blocking and s.on_floor \
			and Vector2(fighter.velocity.x, fighter.velocity.z).length() < 1.0
	if free:
		_taunt_until = -1.0
		director.play_overlay(&"taunt", AnimDirector.Layer.FULL)


func _on_landed(who: Node) -> void:
	if who != fighter or rig == null:
		return
	_dynamics.squash(0.28)
	if Vector2(fighter.velocity.x, fighter.velocity.z).length() < 2.5:
		director.play_overlay(&"leap_land", AnimDirector.Layer.FULL)


# --- swing effects ------------------------------------------------------------------

## Blade trail from the strike to the follow-through, the slash arc at
## contact, and the heavy's ready flash just before it lands.
func _update_swing_effects(s: FighterState, delta: float) -> void:
	_ready_glow = maxf(_ready_glow - delta / 0.25, 0.0)
	if s.action != FighterState.Action.ATTACK:
		_trail.emitting = false
		return
	var a := s.attack
	var move := GameData.moves.get_move(a.animation)
	if move == null:
		return
	var heavy := a.hyperarmor
	if s.action_serial != _swing_serial:
		_swing_serial = s.action_serial
		_contact_shown = false
		_ready_shown = false
		var colors: Array = TRAIL_HEAVY if heavy else TRAIL_STEEL
		_trail.set_colors(colors[0], colors[1], 2.8 if heavy else 2.0)
	var keys := TimeRemap.swing_keys(a.windup, a.active, a.recovery, move.strike, move.hold, move.settle_fraction)
	_trail.emitting = s.action_time >= keys[2] - 0.03 and s.action_time <= keys[4]
	if heavy and not _ready_shown and s.action_time >= a.windup - READY_FLASH_LEAD:
		_ready_shown = true
		_ready_glow = 1.0
		Vfx.impact(fighter.get_parent(), drawn_tip, Color(1.0, 0.86, 0.4), 0.9, 0.2, 4.0)
	if not _contact_shown and s.action_time >= a.windup:
		_contact_shown = true
		if move.has_slash():
			var color: Color = (TRAIL_HEAVY if heavy else TRAIL_STEEL)[1]
			Vfx.slash(fighter.get_parent(), global_position + Vector3.UP * move.slash_height, s.facing_yaw,
					move.slash_from, move.slash_to, move.slash_tilt, SLASH_RADIUS * (1.15 if heavy else 1.0), color,
					0.2 if heavy else 0.16)


## Ghosts along dashes (which also stretch the body along the burst), and a
## string of them along a blink's path. A leap's take-off stretches upward.
func _update_ghosts(s: FighterState, delta: float) -> void:
	if s.leaping and not _was_leaping:
		_dynamics.stretch_along(Vector3.UP, 0.22)
	_was_leaping = s.leaping
	if s.action != FighterState.Action.DASH:
		_ghost_timer = 0.0
		return
	if s.action_serial != _dash_serial:
		_dash_serial = s.action_serial
		var local := Basis(Vector3.UP, s.facing_yaw).inverse() * s.dash_dir
		_dynamics.stretch_along(local, 0.16)
	_ghost_timer -= delta
	if _ghost_timer <= 0.0:
		_ghost_timer = GHOST_INTERVAL
		_ghosts.set_color(GHOST_DASH)
		_ghosts.snapshot()


func _just_blinked() -> bool:
	var rune := fighter.rune
	return rune is BlinkRune and not fighter.state.is_dead() and fighter.state.rune_cd >= rune.cooldown - 0.05


func _leave_blink_trail(from: Vector3, to: Vector3) -> void:
	_trail.clear()
	director.play_overlay(&"blink", AnimDirector.Layer.FULL)
	_ghosts.set_color(GHOST_BLINK)
	var skeleton := rig.skeleton.global_transform
	var offset := skeleton.origin - global_position
	for i in 4:
		var at := from.lerp(to, (i + 0.5) / 4.0)
		_ghosts.snapshot(Transform3D(skeleton.basis, at + offset), true, (3 - i) * 0.04)


# --- gauntlet -----------------------------------------------------------------------

## A glowing orb in front of the left knuckles (the primary spell's element),
## a bracer at the wrist (the signature's element) and a small light.
func _build_gauntlet() -> void:
	if _gauntlet_root:
		_gauntlet_root.queue_free()
		_gauntlet_root = null
	if rig == null or rig.left_hand == null:
		return
	var color := SpellData.element_color(fighter.primary.element)
	var accent := SpellData.element_color(fighter.signature.element)
	_gauntlet_root = Node3D.new()
	_gauntlet_root.name = "Gauntlet"
	rig.left_hand.add_child(_gauntlet_root)

	var bracer := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.042
	torus.outer_radius = 0.072
	bracer.mesh = torus
	bracer.position = Vector3(0.0, -0.03, 0.0)
	bracer.material_override = ToonMaterials.make(Color(0.24, 0.19, 0.3), {&"glow_color": accent, &"glow_energy": 0.9})
	_gauntlet_root.add_child(bracer)

	_gauntlet_core = MeshInstance3D.new()
	var orb := SphereMesh.new()
	orb.radius = 0.05
	orb.height = 0.1
	_gauntlet_core.mesh = orb
	_gauntlet_core.material_override = ToonMaterials.make_vfx(color.lightened(0.3), 3.5, false)
	_gauntlet_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_gauntlet_core.position = rig.knuckles_l
	_gauntlet_root.add_child(_gauntlet_core)

	var halo := MeshInstance3D.new()
	var halo_mesh := SphereMesh.new()
	halo_mesh.radius = 0.1
	halo_mesh.height = 0.2
	halo.mesh = halo_mesh
	var halo_material := ToonMaterials.make_vfx(color, 1.5)
	halo_material.albedo_color.a = 0.3
	halo.material_override = halo_material
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_gauntlet_core.add_child(halo)

	_gauntlet_light = OmniLight3D.new()
	_gauntlet_light.light_color = color
	_gauntlet_light.omni_range = 2.0
	_gauntlet_core.add_child(_gauntlet_light)


## The orb swells while a spell winds up (with the element's own charge-up
## in the hand) and flares while guarding.
func _update_gauntlet(s: FighterState) -> void:
	if _gauntlet_core == null or not is_instance_valid(_gauntlet_core):
		return
	if s.action == FighterState.Action.CAST and s.action_serial != _cast_serial:
		_cast_serial = s.action_serial
		SpellFx.charge(s.spell, _gauntlet_core, s.spell.windup)
	var boost := 1.0
	if s.action == FighterState.Action.CAST and not s.spell_released:
		boost = 1.0 + 2.5 * clampf(s.action_time / maxf(s.spell.windup, 0.01), 0.0, 1.0)
	elif s.blocking:
		boost = 1.7
	_gauntlet_core.scale = Vector3.ONE * (1.0 + 0.3 * (boost - 1.0))
	_gauntlet_light.light_energy = 0.7 * boost


## The spell leaving the gauntlet.
func _on_spell_cast(who: Node, spell: Resource) -> void:
	if who != fighter or _gauntlet_core == null or not is_instance_valid(_gauntlet_core):
		return
	SpellFx.release(spell as SpellData, fighter.get_parent(), _gauntlet_core.global_position, fighter.forward())


# --- tints, flashes and tells -----------------------------------------------------

## Burning bodies flicker orange; chilled ones glow colder with each stack.
func _update_status_tint(s: FighterState) -> void:
	var energy := 0.0
	var color := Color.BLACK
	if s.chill_stacks > 0:
		color = SpellData.element_color(SpellData.Element.FROST)
		energy = 0.15 * s.chill_stacks
	if s.burn_time > 0.0:
		color = SpellData.element_color(SpellData.Element.FIRE)
		energy = maxf(energy, 0.45 + 0.3 * sin(_time * 26.0))
	for material in materials:
		material.set_shader_parameter(&"glow_color", color)
		material.set_shader_parameter(&"glow_energy", energy)


## A lightning stun crackles over the body while it lasts.
func _update_shock(s: FighterState) -> void:
	if s.action != FighterState.Action.STAGGER or s.stagger_kind != &"shock" or s.action_serial == _shock_serial:
		return
	_shock_serial = s.action_serial
	SpellFx.shock(_pivot, s.action_duration - s.action_time)


func _update_flash(s: FighterState, delta: float) -> void:
	if _last_hp >= 0.0 and s.hp < _last_hp:
		_flash = 1.0
	_last_hp = s.hp
	if _flash <= 0.0:
		return
	_flash = maxf(_flash - delta / 0.14, 0.0)
	for material in materials:
		material.set_shader_parameter(&"flash_amount", _flash * 0.85)


## Heavy wind-ups heat the blade until it swings, with a spike at the ready
## flash. (Runs after the status tint, so the blade's glow wins.)
func _update_tells(s: FighterState) -> void:
	var glow := _ready_glow * 6.0
	if s.action == FighterState.Action.ATTACK and s.attack.hyperarmor and s.action_time < s.attack.windup + s.attack.active:
		glow += 1.0 + 4.0 * clampf(s.action_time / s.attack.windup, 0.0, 1.0)
	elif glow <= 0.0:
		return
	for material in sword_materials:
		material.set_shader_parameter(&"glow_color", Color(1.0, 0.45, 0.1))
		material.set_shader_parameter(&"glow_energy", glow)
