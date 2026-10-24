class_name CombatFeedback
extends Node3D
## Cosmetic reactions to combat events: the comic accents where blows land,
## and, for the local player (`focus`) only, the camera's shake, kicks and FOV
## punches and the full-screen effects (ScreenFx). Each spell lands with its
## own weight (primaries light, signatures heavy), and its element gives the
## camera its character:
##   fire       a rolling rumble
##   frost      a crisp jolt
##   lightning  a short, high-frequency buzz; a Lightning Strike landing near
##              you, even a miss, is a big sharp jolt and a flash that fall
##              off with distance
##   wind       the view pushed away from the blast, and a ripple through the
##              screen from a burst nearby
## While you're Chilled, frost grows in from the screen's edges; while
## stunned, arcs crackle along them. Listens to CombatEvents only; never
## touches simulation state.

const HIT_COLOR := Color(1.0, 0.94, 0.7)
const BLOCK_COLOR := Color(0.55, 0.8, 1.0)
const BREAK_COLOR := Color(1.0, 0.3, 0.25)
const PARRY_COLOR := Color(1.0, 0.85, 0.2)
const SHATTER_COLOR := Color(0.85, 0.55, 1.0)
const STRIKE_FLASH := Color(1.0, 0.97, 0.82)
const STUN_PULSE := Color(1.0, 0.86, 0.3)
const FROST_PULSE := Color(0.45, 0.82, 1.0)

## How hard each spell lands, 0..1: primaries light, signatures heavy.
const WEIGHT := {
	&"firebolt": 0.45, &"ice_spike": 0.42, &"lightning_bolt": 0.42, &"wind_slash": 0.38,
	&"flame_wall": 0.55, &"frost_nova": 0.75, &"lightning_strike": 1.0, &"wind_spear": 0.85,
}
## A Lightning Strike is felt this far away (m); a Wind Spear's burst this far.
const STRIKE_FELT := 22.0
const BURST_FELT := 14.0

var camera_rig: CameraRig
## The local player: the camera and screen react only to what involves them.
var focus: Fighter
var screen: ScreenFx

var _frost := 0.0
var _shock := 0.0
## The physics frame in which a spell last hit the focus (its impact then
## needs no extra "nearby" shake).
var _focus_hit_frame := -1


func _ready() -> void:
	screen = ScreenFx.new()
	screen.name = "ScreenFx"
	add_child(screen)
	CombatEvents.hit_resolved.connect(_on_hit_resolved)
	CombatEvents.landed.connect(_on_landed)
	CombatEvents.spell_cast.connect(_on_spell_cast)
	CombatEvents.spell_impact.connect(_on_spell_impact)


## The steady edge looks follow the focus's state: frost with the Chill
## stacks, crackling arcs through a stun (fading over its last part).
func _process(delta: float) -> void:
	var chill := 0.0
	var shock := 0.0
	if _has_focus():
		var s := focus.state
		chill = float(s.chill_stacks) / maxf(float(focus.tuning.chill_max_stacks), 1.0)
		if s.action == FighterState.Action.STAGGER and s.stagger_kind == &"shock":
			shock = clampf((1.0 - s.action_time / maxf(s.action_duration, 0.01)) * 2.5, 0.0, 1.0)
	_frost = move_toward(_frost, chill, delta / (0.15 if chill > _frost else 0.6))
	_shock = move_toward(_shock, shock, delta / (0.04 if shock > _shock else 0.15))
	screen.frost = _frost
	screen.shock = _shock


func _on_landed(fighter: Node) -> void:
	Vfx.ring(self, (fighter as Fighter).global_position, Color(0.75, 0.95, 1.0), 1.8, 0.3)
	if camera_rig and fighter == focus:
		camera_rig.add_trauma(0.18)
		camera_rig.kick(Vector3.DOWN, 0.35)


func _on_hit_resolved(attacker: Node, defender: Node, result: HitResult, at: Vector3) -> void:
	if result.periodic and result.reaction == &"":
		# ground-fire ticks: the burning look on the body says enough, and a
		# low rumble while you stand in it
		if camera_rig and defender == focus:
			camera_rig.rumble(0.16, 0.3)
		return
	var involved := camera_rig != null and (attacker == focus or defender == focus)
	if defender == focus:
		_focus_hit_frame = Engine.get_physics_frames()
	if result.reaction == &"shatter":
		_shatter(attacker, defender, at, involved)
	elif result.element != SpellData.Element.NONE:
		_spell_accent(result, at, defender == focus)
		if involved:
			_spell_feel(attacker, defender, result, at)
	else:
		_melee(attacker, defender, result, at, involved)


# --- melee ----------------------------------------------------------------------

## Blades meeting bodies and guards: the classic comic star, a shake, a kick
## along the blow, and an FOV punch on the big ones.
func _melee(attacker: Node, defender: Node, result: HitResult, at: Vector3, involved: bool) -> void:
	var color := HIT_COLOR
	var size := 0.8 + result.damage / 25.0
	var trauma := 0.22 + result.damage / 70.0
	var kick := 0.25 + result.damage / 40.0
	var punch := 2.5 if result.source == &"heavy" else 0.0
	match result.outcome:
		HitResult.Outcome.BLOCKED:
			color = BLOCK_COLOR
			size = 0.8
			trauma = 0.15
			kick = 0.3
			punch = 0.0
		HitResult.Outcome.GUARD_BREAK:
			color = BREAK_COLOR
			size = 1.6
			trauma = 0.5
			kick = 0.9
			punch = 4.0
		HitResult.Outcome.PARRIED:
			color = PARRY_COLOR
			size = 1.8
			trauma = 0.4
			kick = 0.6
			punch = 3.5
	Vfx.impact(self, at, color, size)
	if not involved:
		return
	camera_rig.add_trauma(trauma)
	var push := _push_direction(attacker, defender, at)
	if defender == focus:
		camera_rig.kick(push, kick)  # shoved the way the blow travels
	else:
		camera_rig.kick(push, kick * 0.45)  # a smaller lean into your own hit
	if punch > 0.0:
		camera_rig.fov_punch(punch)


# --- spells -----------------------------------------------------------------------

## The element modules draw each spell's own impact; this only adds a small
## comic accent in the element's shape where it struck the body (a guard's
## star where it was blocked), nudged toward the camera so it reads on top.
## On your own body it stays smaller and isn't nudged: it sits right under
## the camera, where a full-size accent would cover the view (and the enemy).
func _spell_accent(result: HitResult, at: Vector3, on_focus: bool) -> void:
	var weight: float = WEIGHT.get(result.source, 0.5)
	var scale := 0.6 if on_focus else _range_scale(at)
	var where := at if on_focus else _toward_view(at, 0.35)
	match result.outcome:
		HitResult.Outcome.HIT:
			Vfx.accent(self, where, result.element, (0.42 + 0.38 * weight) * scale)
		HitResult.Outcome.BLOCKED:
			Vfx.impact(self, where, BLOCK_COLOR, 0.6 * scale, 0.18)
		HitResult.Outcome.GUARD_BREAK:
			Vfx.impact(self, where, BREAK_COLOR, 1.1 * scale)


## A spell hit on or by the local player: the spell's weight in shake and
## kick, its element's flavor, and the screen for the big moments.
func _spell_feel(attacker: Node, defender: Node, result: HitResult, at: Vector3) -> void:
	var weight: float = WEIGHT.get(result.source, 0.5)
	var push := _push_direction(attacker, defender, at)
	var shove := (defender as Fighter).state.knockback
	if result.element == SpellData.Element.WIND and Vector2(shove.x, shove.z).length() > 0.5:
		push = Vector3(shove.x, 0.0, shove.z).normalized()  # away from the burst, not the caster
	var landed := result.outcome == HitResult.Outcome.HIT
	if defender == focus:
		var scale := 1.0 if landed else 0.5
		camera_rig.add_trauma((0.1 + 0.28 * weight) * scale)
		camera_rig.kick(push, (0.25 + 0.75 * weight) * scale)
		_element_shake(result.element, weight * scale, push)
		if landed and weight >= 0.7:
			camera_rig.fov_punch(1.5 + 2.5 * weight)
		if landed and _is_shocked(focus):
			# stunned: a yellow pulse at the edges (the strike itself flashed)
			screen.pulse(STUN_PULSE, 0.6, 0.45)
		elif landed and result.element == SpellData.Element.FROST and weight >= 0.7:
			screen.pulse(FROST_PULSE, 0.45, 0.4)
	else:
		# your spell landing: a small confirmation in the element's own manner
		camera_rig.add_trauma(0.04 + 0.1 * weight)
		_element_shake(result.element, weight * 0.3, push)
		if landed and weight >= 0.7:
			# a heavy spell landing far away still lands in your hands
			camera_rig.fov_punch(0.9 * weight)


## Each element's shake at `weight` (0..1), for a blow travelling along `push`.
func _element_shake(element: int, weight: float, push: Vector3) -> void:
	match element:
		SpellData.Element.FIRE:
			camera_rig.rumble(0.2 + 0.65 * weight, 0.22 + 0.4 * weight)
		SpellData.Element.FROST:
			camera_rig.jolt(push + Vector3.DOWN * 0.6, 0.3 + 0.9 * weight)
		SpellData.Element.LIGHTNING:
			camera_rig.buzz(0.3 + 0.65 * weight, 0.1 + 0.18 * weight)
		SpellData.Element.WIND:
			camera_rig.push(push, 0.35 + 1.0 * weight)


## Fire meeting frost: the biggest single moment. The ice bursts (SpellFx),
## a violet star marks it, and whoever's involved gets a hard jolt, a punch
## and a flash.
func _shatter(attacker: Node, defender: Node, at: Vector3, involved: bool) -> void:
	SpellFx.shatter(self, at)
	var scale := 1.0 if defender == focus else _range_scale(at)
	Vfx.impact(self, _toward_view(at, 0.4), SHATTER_COLOR, 1.3 * scale, 0.26, 10.0)
	Vfx.accent(self, _toward_view(at, 0.5), SpellData.Element.FROST, 0.9 * scale, 0.3)
	if not involved:
		return
	var push := _push_direction(attacker, defender, at)
	var mine := defender == focus
	camera_rig.add_trauma(0.6 if mine else 0.45)
	camera_rig.kick(push, 1.0 if mine else 0.45)
	camera_rig.jolt(push + Vector3.DOWN, 1.1 if mine else 0.7)
	camera_rig.rumble(0.5, 0.4)
	camera_rig.fov_punch(5.0 if mine else 3.0)
	screen.flash(Color(0.92, 0.85, 1.0), 0.75 if mine else 0.45, 0.12)
	screen.pulse(SHATTER_COLOR, 0.7 if mine else 0.4, 0.5)


## Your own cast leaving the hand: a small recoil in the element's manner,
## heavier for the signatures. (A Nova and a Flame Wall are felt where they
## go off, in _on_spell_impact.)
func _on_spell_cast(who: Node, spell: Resource) -> void:
	if who != focus or camera_rig == null:
		return
	var data := spell as SpellData
	if data is NovaSpell or data is FlameWallSpell:
		return
	var forward := focus.forward()
	var signature := data.slot == SpellData.Slot.SIGNATURE
	camera_rig.kick(-forward, 0.3 if signature else 0.14)
	match data.element:
		SpellData.Element.FIRE:
			camera_rig.rumble(0.14, 0.14)
		SpellData.Element.FROST:
			camera_rig.jolt(-forward, 0.18)
		SpellData.Element.LIGHTNING:
			if signature:
				camera_rig.buzz(0.35, 0.16)
				camera_rig.kick(Vector3.UP, 0.25)  # the bolt called from the raised hand
			else:
				camera_rig.buzz(0.2, 0.07)
		SpellData.Element.WIND:
			camera_rig.push(-forward, 0.8 if signature else 0.25)
			if signature:
				camera_rig.fov_punch(-1.5)


## Where a spell lands, hit or not: the big ones are felt by the local
## player nearby (and, more faintly, by the caster from afar).
func _on_spell_impact(caster: Node, spell: Resource, at: Vector3) -> void:
	if camera_rig == null or not _has_focus():
		return
	var data := spell as SpellData
	var distance := focus.global_position.distance_to(at)
	if data is LightningStrikeSpell:
		_strike_nearby(at, distance, (data as LightningStrikeSpell).radius)
	elif data is NovaSpell:
		_nova_nearby(caster, at, distance, (data as NovaSpell).radius)
	elif data is FlameWallSpell:
		var f := _falloff(distance, 4.0, 14.0)
		if caster == focus:
			f = maxf(f, 0.4)
		camera_rig.rumble(0.55 * f, 0.4 + 0.3 * f)
	elif data is ProjectileSpell and (data as ProjectileSpell).burst_radius > 0.0:
		_burst_nearby(at, distance, (data as ProjectileSpell).burst_radius)
	elif data is ProjectileSpell and _focus_hit_frame != Engine.get_physics_frames():
		# a near miss: a smaller dose of the element's shake
		var away := focus.global_position - at
		_element_shake(data.element, 0.35 * _falloff(distance, 1.0, 6.0), Vector3(away.x, 0.0, away.z))


## A bolt from the sky: a big, sharp jolt, a buzz, a flash and an FOV punch,
## all falling off with distance (full strength inside the circle).
func _strike_nearby(at: Vector3, distance: float, radius: float) -> void:
	var f := _falloff(distance, radius, STRIKE_FELT)
	if f <= 0.02:
		return
	camera_rig.jolt(Vector3.DOWN + (focus.global_position - at).normalized() * 0.4, 2.0 * f)
	camera_rig.buzz(0.95 * f, 0.12 + 0.2 * f)
	camera_rig.add_trauma(0.35 * f)
	camera_rig.fov_punch(4.5 * f)
	screen.flash(STRIKE_FLASH, 0.6 * f, 0.05 + 0.05 * f)
	if f > 0.45:
		screen.pulse(STUN_PULSE, 0.4 * f, 0.3)


## A Wind Spear bursting: the view blown away from it and a ripple through
## the screen from where it went off.
func _burst_nearby(at: Vector3, distance: float, radius: float) -> void:
	var f := _falloff(distance, radius * 0.5, BURST_FELT)
	if f <= 0.02:
		return
	camera_rig.push_from(at, 1.6 * f)
	camera_rig.add_trauma(0.22 * f)
	# the camera that draws the screen (a --spectate camera replaces the rig's)
	var camera := get_viewport().get_camera_3d() if get_viewport() else null
	if camera and not camera.is_position_behind(at):
		var size := camera.get_viewport().get_visible_rect().size if camera.get_viewport() else Vector2.ZERO
		if size.x > 0.0 and size.y > 0.0:
			screen.warp(camera.unproject_position(at) / size, f, 0.45)


## A Frost Nova: a crisp jolt for its caster, and for anyone near it.
func _nova_nearby(caster: Node, at: Vector3, distance: float, radius: float) -> void:
	if caster == focus:
		camera_rig.jolt(Vector3.DOWN, 0.8)
		camera_rig.fov_punch(2.5)
		screen.pulse(FROST_PULSE, 0.3, 0.3)
		return
	var f := _falloff(distance, radius, radius + 8.0)
	if f > 0.02:
		camera_rig.jolt(focus.global_position - at, 1.0 * f)


# --- helpers --------------------------------------------------------------------

func _has_focus() -> bool:
	return focus != null and is_instance_valid(focus) and not focus.state.is_dead()


static func _is_shocked(fighter: Fighter) -> bool:
	return fighter.state.action == FighterState.Action.STAGGER and fighter.state.stagger_kind == &"shock"


## 1 within `near`, falling off steeply to 0 at `far`.
static func _falloff(distance: float, near: float, far: float) -> float:
	var t := clampf(1.0 - (distance - near) / maxf(far - near, 0.01), 0.0, 1.0)
	return pow(t, 1.5)


## Grows an accent with its distance from the camera past about 7 m (up to
## 2.2x), so a hit on a far enemy still shows its element's shape instead of
## a speck; close up it keeps its own size.
func _range_scale(at: Vector3) -> float:
	var viewer := get_viewport().get_camera_3d() if get_viewport() else null
	if viewer == null:
		return 1.0
	return clampf(viewer.global_position.distance_to(at) / 7.0, 1.0, 2.2)


## A little toward the camera from `at`, so an accent reads in front of the
## body and the element's own impact.
func _toward_view(at: Vector3, amount: float) -> Vector3:
	var viewer := get_viewport().get_camera_3d() if get_viewport() else null
	if viewer == null:
		return at
	var to := viewer.global_position - at
	return at + to.normalized() * minf(amount, to.length() * 0.5) if to.length() > 0.01 else at


## The way a blow travels: attacker to defender, flattened; spells without a
## living attacker fall back to "away from the impact point".
func _push_direction(attacker: Node, defender: Node, at: Vector3) -> Vector3:
	var to := (defender as Node3D).global_position
	var from := at
	if attacker is Node3D and attacker != defender:
		from = (attacker as Node3D).global_position
	var dir := Vector3(to.x - from.x, 0.0, to.z - from.z)
	return dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
