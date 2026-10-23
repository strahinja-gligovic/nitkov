class_name DamageNumbers
extends Node3D
## Floating comic text for hits, drawn flat on the screen over the world so it
## stays crisp and readable at any range. Damage numbers wear their element's
## colors (a bright fill, a saturated rim, an ink outline), pop in with an
## overshoot, float up and fade; big hits come out larger, white-hot and with
## a burst of speed lines. Shouts mark the moments that matter: SHATTER!,
## SHOCKED! (a Lightning Strike stun, trembling while it lasts), BLOCKED,
## PARRY! and GUARD BREAK!. Repeating damage (burn and flame-wall ticks) adds
## up in one number instead of a stream. Listens to CombatEvents and never
## touches the simulation.

const INK := Color(0.06, 0.03, 0.09)
## Over the HUD (layer 5): a SHATTER! matters more than the enemy's bar
## behind it for the second it's up. (The loadout menu, layer 10, covers both.)
const LAYER := 6
## A hit at least this big gets the white-hot, extra-large treatment.
const BIG_HIT := 20.0
## Melee has no element: warm white with a dark plum rim.
const PHYSICAL_FILL := Color(1.0, 0.96, 0.88)
const PHYSICAL_RIM := Color(0.36, 0.2, 0.32)

enum Kind { NUMBER, TICK, CALLOUT }

## One piece of floating text.
class Floater:
	extends RefCounted
	var kind := 0
	var anchor := Vector3.ZERO
	var text := ""
	var value := 0.0
	var fill := Color.WHITE
	var rim := Color.BLACK
	var size := 32
	var age := 0.0
	var life := 0.9
	## Screen offset at spawn, and how far it travels while it rises.
	var offset := Vector2.ZERO
	var drift := Vector2.ZERO
	## Which side of the target's body it bursts out to (-1, 0, 1): numbers
	## clear the body within a few frames instead of covering it.
	var side := 0.0
	var half_width := 0.0
	var tilt := 0.0
	## Scale at the top of the pop-in.
	var punch := 1.25
	## Pixels of tremble (SHOCKED!).
	var shake := 0.0
	var burst := false
	## Ticks with the same key add up into one number.
	var key := ""
	var victim := 0

var _popups: Array[Floater] = []
var _canvas: Control
var _font: Font


func _ready() -> void:
	_font = UiTheme.impact_font()
	var layer := CanvasLayer.new()
	layer.layer = LAYER
	add_child(layer)
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_popups)
	layer.add_child(_canvas)
	CombatEvents.hit_resolved.connect(_on_hit)
	CombatEvents.status_damage.connect(_on_status_damage)


func _process(delta: float) -> void:
	if _popups.is_empty():
		return
	for i in range(_popups.size() - 1, -1, -1):
		_popups[i].age += delta
		if _popups[i].age >= _popups[i].life:
			_popups.remove_at(i)
	_canvas.queue_redraw()


# --- events -------------------------------------------------------------------------

func _on_hit(_attacker: Node, defender: Node, result: HitResult, at: Vector3) -> void:
	var victim := defender.get_instance_id() if defender else 0
	match result.outcome:
		HitResult.Outcome.PARRIED:
			_callout(at, "PARRY!", Color(1.0, 0.9, 0.35), Color(0.62, 0.33, 0.04), 46, victim)
			return
		HitResult.Outcome.BLOCKED:
			_callout(at, "BLOCKED", Color(0.84, 0.92, 1.0), Color(0.22, 0.34, 0.58), 34, victim, 0.8)
			if result.damage >= 0.5:
				_number(at, result.damage, result.element, victim, 0.62)
			return
		HitResult.Outcome.GUARD_BREAK:
			_callout(at, "GUARD BREAK!", Color(1.0, 0.55, 0.42), Color(0.6, 0.06, 0.08), 42, victim)
	if result.reaction == &"shatter":
		# fire meeting frost: icy letters in a fiery rim
		_callout(at, "SHATTER!", Color(0.82, 0.97, 1.0), Color(0.86, 0.3, 0.06), 52, victim, 1.15)
	elif _shocked(defender, result):
		var stun := (defender as Fighter).state.action_duration
		var shout := _callout(at, "SHOCKED!", Color(1.0, 0.98, 0.62), Color(0.44, 0.2, 0.78), 46, victim, maxf(stun, 0.9))
		shout.shake = 2.5
	if result.damage < 0.5:
		return
	if result.periodic:
		_tick(at + Vector3.UP * 0.25, result.damage, result.element, victim)
	else:
		_number(at, result.damage, result.element, victim)


func _on_status_damage(fighter: Node, amount: float, element: int) -> void:
	var target := fighter as Fighter
	if target and amount > 0.0:
		_tick(target.chest_position() + Vector3.UP * 0.35, amount, element, target.get_instance_id())


## A Lightning Strike's stun (or any shock stagger) that this very hit started.
static func _shocked(defender: Node, result: HitResult) -> bool:
	var fighter := defender as Fighter
	if fighter == null or result.outcome != HitResult.Outcome.HIT:
		return false
	var s := fighter.state
	return s.action == FighterState.Action.STAGGER and s.stagger_kind == &"shock" and s.action_time == 0.0


# --- spawning -----------------------------------------------------------------------

func _number(at: Vector3, damage: float, element: int, victim: int, shrink := 1.0) -> void:
	var p := Floater.new()
	p.kind = Kind.NUMBER
	p.anchor = at
	p.value = damage
	p.text = "%d" % maxi(roundi(damage), 1)
	var big := damage >= BIG_HIT and shrink >= 1.0
	var colors := _colors(element, big)
	p.fill = colors[0]
	p.rim = colors[1]
	p.size = roundi(lerpf(30.0, 56.0, clampf((damage - 6.0) / 26.0, 0.0, 1.0)) * shrink)
	p.punch = 1.38 if big else 1.26
	p.burst = big
	p.life = 1.0 if big else 0.85
	p.victim = victim
	# spread numbers that land on the same target close together
	var crowd := _recent(victim, Kind.NUMBER)
	p.side = 1.0 if randf() < 0.5 else -1.0
	p.half_width = _font.get_string_size(p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, p.size).x * 0.5
	p.offset = Vector2(p.side * 18.0 * crowd, -14.0 * crowd)
	p.drift = Vector2(p.side * randf_range(6.0, 18.0), -randf_range(40.0, 52.0))
	if _recent(victim, Kind.CALLOUT) > 0:
		# a shout is already rising above this hit: stay under it
		p.offset.y += 14.0
		p.drift.y = -18.0
	p.tilt = deg_to_rad(randf_range(-7.0, 7.0))
	_popups.append(p)


## Repeating damage: adds into a young number on the same target, which
## re-pops a little each time, or starts a new small one.
func _tick(at: Vector3, damage: float, element: int, victim: int) -> void:
	var key := "%d:%d" % [victim, element]
	for p in _popups:
		if p.kind == Kind.TICK and p.key == key and p.age < 0.55:
			p.value += damage
			p.text = "%d" % maxi(roundi(p.value), 1)
			p.age = minf(p.age, 0.05)
			p.anchor = at
			return
	var p := Floater.new()
	p.kind = Kind.TICK
	p.key = key
	p.anchor = at
	p.value = damage
	p.text = "%d" % maxi(roundi(damage), 1)
	var colors := _colors(element, false)
	p.fill = colors[0]
	p.rim = colors[1]
	p.size = 24
	p.punch = 1.18
	p.life = 0.8
	p.victim = victim
	# out to one side of the body, lower than the hits' numbers
	p.side = 1.0 if randf() < 0.5 else -1.0
	p.half_width = 14.0
	p.offset = Vector2(0.0, 22.0)
	p.drift = Vector2(0.0, -30.0)
	_popups.append(p)


func _callout(at: Vector3, text: String, fill: Color, rim: Color, size: int, victim: int, life := 1.0) -> Floater:
	var p := Floater.new()
	p.kind = Kind.CALLOUT
	p.anchor = at + Vector3.UP * 0.6
	p.text = text
	p.fill = fill
	p.rim = rim
	p.size = size
	p.punch = 1.4
	p.burst = true
	p.life = life
	p.victim = victim
	p.offset = Vector2(0.0, -34.0 - 34.0 * _recent(victim, Kind.CALLOUT))
	p.drift = Vector2(0.0, -20.0)
	p.tilt = deg_to_rad(randf_range(-5.0, 5.0))
	_popups.append(p)
	return p


## How many young popups of this kind are already on this target.
func _recent(victim: int, kind: int) -> int:
	var count := 0
	for p in _popups:
		if p.victim == victim and p.kind == kind and p.age < 0.4:
			count += 1
	return count


## [fill, rim] for an element; big hits burn white-hot inside a vivid rim.
static func _colors(element: int, big: bool) -> Array[Color]:
	var out: Array[Color] = []
	if element == SpellData.Element.NONE:
		out.append(Color.WHITE if big else PHYSICAL_FILL)
		out.append(Color(0.62, 0.22, 0.32) if big else PHYSICAL_RIM)
		return out
	var palette := UiIcons.palette(element as SpellData.Element)
	out.append(palette[UiIcons.Tone.CORE] if big else palette[UiIcons.Tone.LIGHT])
	out.append(palette[UiIcons.Tone.BASE].darkened(0.1) if big else palette[UiIcons.Tone.SHADE])
	return out


# --- drawing ------------------------------------------------------------------------

func _draw_popups() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	for p in _popups:
		if camera.is_position_behind(p.anchor):
			continue
		var t := p.age
		var fade := clampf((p.life - t) / 0.28, 0.0, 1.0)
		var travel := 1.0 - pow(1.0 - clampf(t / 0.75, 0.0, 1.0), 3.0)
		var at := camera.unproject_position(p.anchor) + p.offset + p.drift * travel
		if p.side != 0.0:
			# burst out past the body's edge (about 0.45 m from its middle) in ~0.12 s
			var metre := (camera.unproject_position(p.anchor + camera.global_basis.x) - camera.unproject_position(p.anchor)).length()
			var out := 1.0 - pow(1.0 - clampf(t / 0.12, 0.0, 1.0), 3.0)
			at.x += p.side * (0.45 * metre + p.half_width + 4.0) * out
		if p.shake > 0.0:
			at += Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * p.shake
		var distance := camera.global_position.distance_to(p.anchor)
		var scale := _pop(t, p.punch) * clampf(remap(distance, 6.0, 26.0, 1.0, 0.72), 0.72, 1.0) * lerpf(0.82, 1.0, fade)
		_canvas.draw_set_transform(at, p.tilt, Vector2(scale, scale))
		if p.burst and t < 0.22:
			_speed_lines(p, t / 0.22)
		var width := _font.get_string_size(p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, p.size).x
		var origin := Vector2(-width * 0.5, p.size * 0.36)
		var ink := Color(INK, fade)
		var fill := Color.WHITE if t < 0.05 else p.fill  # one white-hot frame or three as it lands
		_canvas.draw_string_outline(_font, origin, p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, p.size, maxi(roundi(p.size * 0.32), 6), ink)
		_canvas.draw_string_outline(_font, origin, p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, p.size, maxi(roundi(p.size * 0.15), 3), Color(p.rim, fade))
		_canvas.draw_string(_font, origin, p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, p.size, Color(fill, fade))
	_canvas.draw_set_transform_matrix(Transform2D.IDENTITY)


## Short ink-edged strokes flying out from the text as it lands (`k` 0..1).
func _speed_lines(p: Floater, k: float) -> void:
	var width := _font.get_string_size(p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, p.size).x
	# an ellipse hugging the text, so long shouts don't fling lines far out sideways
	var reach := Vector2(width * 0.5 + 8.0, p.size * 0.6 + 8.0)
	var color := Color(p.fill, 1.0 - k)
	var ink := Color(INK, 1.0 - k)
	for i in 12:
		var dir := Vector2.from_angle(TAU * i / 12.0 + 0.26)
		var from := dir * reach * (1.0 + 0.35 * k)
		var to := from + dir * (10.0 + 12.0 * (1.0 - k))
		_canvas.draw_line(from, to, ink, 5.5, true)
		_canvas.draw_line(from, to, color, 2.5, true)


## Scale over a popup's life: a fast swell past full size, a settle, then steady.
static func _pop(t: float, punch: float) -> float:
	if t < 0.07:
		return lerpf(0.3, punch, 1.0 - pow(1.0 - t / 0.07, 2.0))
	if t < 0.18:
		return lerpf(punch, 1.0, smoothstep(0.0, 1.0, (t - 0.07) / 0.11))
	return 1.0
