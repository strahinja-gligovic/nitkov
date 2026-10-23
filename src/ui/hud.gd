class_name Hud
extends CanvasLayer
## The in-fight HUD, drawn by hand each frame: health and stamina bars,
## status chips, ability slots with cooldowns, crosshair and hit-markers, the
## enemy's bar over their head, the respawn overlay and kill banners. Reads
## simulation state only.
##
## The ability slots show each spell's own icon (UiIcons). A cooling slot is
## veiled by a sweep that unwinds clockwise from 12 o'clock with a bright
## hand on its edge and a countdown; when it comes back it flashes. A slot
## lights up white while you cast its spell, and greys out when you can't.

const INK := Color(0.06, 0.03, 0.09)
const HEALTH := Color(0.95, 0.27, 0.32)
const TRAIL := Color(1.0, 0.95, 0.85)
const STAMINA := Color(1.0, 0.84, 0.3)
const EXHAUSTED := Color(1.0, 0.3, 0.22)
const SLOT := Color(0.13, 0.08, 0.18, 0.94)
const VEIL := Color(0.03, 0.01, 0.06, 0.66)
const SPELL_SLOT := 76.0
const RUNE_SLOT := 62.0
const SLOT_GAP := 30.0
const SLOT_RADIUS := 8
## Seconds a slot flashes when it's ready again.
const READY_FLASH := 0.45

var player: Fighter
var bot: Fighter
var bot_brain: BotBrain
var player_input: PlayerInput
var camera: Camera3D

var _canvas: Control
var _font: Font
var _bold: Font
var _hp_trail := 100.0
var _bot_trail := 100.0
var _hit_marker := 0.0
var _kill_marker := false
var _banner := ""
var _banner_time := 0.0
var _controls: Control
var _time := 0.0
## Per slot (primary, signature, rune): usable last frame, and the ready flash left.
var _was_ready: Array[bool] = [true, true, true]
var _ready_flash: Array[float] = [0.0, 0.0, 0.0]
## "<text>@<width>" -> [lines, font size] for slot names that must fit their slot.
var _name_fits := {}
var _fill_box := StyleBoxFlat.new()
var _frame_box := StyleBoxFlat.new()


func _ready() -> void:
	layer = 5
	_font = ThemeDB.fallback_font
	_bold = UiTheme.bold_font()
	_fill_box.anti_aliasing = true
	_frame_box.anti_aliasing = true
	_frame_box.draw_center = false
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_hud)
	add_child(_canvas)
	_controls = _build_controls_panel()
	add_child(_controls)
	CombatEvents.hit_resolved.connect(_on_hit)
	CombatEvents.fighter_died.connect(_on_died)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"show_controls"):
		_controls.visible = not _controls.visible


func _process(delta: float) -> void:
	_time += delta
	_hit_marker = maxf(_hit_marker - delta, 0.0)
	_banner_time = maxf(_banner_time - delta, 0.0)
	_hp_trail = _chase(_hp_trail, player.state.hp, delta)
	_bot_trail = _chase(_bot_trail, bot.state.hp, delta)
	for i in 3:
		var ready := _slot_ready(i)
		if ready and not _was_ready[i]:
			_ready_flash[i] = READY_FLASH
		_was_ready[i] = ready
		_ready_flash[i] = maxf(_ready_flash[i] - delta, 0.0)
	_canvas.queue_redraw()


## The white "damage taken" trail waits a moment, then drains to the real value.
static func _chase(trail: float, actual: float, delta: float) -> float:
	if actual >= trail:
		return actual
	return move_toward(trail, actual, 40.0 * delta)


func _on_hit(attacker: Node, _defender: Node, result: HitResult, _at: Vector3) -> void:
	if attacker == player and result.outcome in [HitResult.Outcome.HIT, HitResult.Outcome.GUARD_BREAK] and not result.periodic:
		_hit_marker = 0.18
		_kill_marker = result.killed


func _on_died(fighter: Node, _killer: Node) -> void:
	_banner = "BOT DOWN!" if fighter == bot else "YOU'RE DOWN!"
	_banner_time = 1.8


# --- slot state -------------------------------------------------------------------

## Seconds of cooldown left on slot `i` (0 primary, 1 signature, 2 rune).
func _slot_remaining(i: int) -> float:
	match i:
		1:
			return player.state.signature_cd
		2:
			return player.state.rune_cd
	return 0.0


## Whether pressing slot `i` would work right now (cooldown aside, for the primary).
func _slot_usable(i: int) -> bool:
	var s := player.state
	if s.is_dead():
		return false
	if i == 0:
		return s.can_spend()
	return s.exhausted <= 0.0


func _slot_ready(i: int) -> bool:
	return _slot_usable(i) and _slot_remaining(i) <= 0.0


# --- drawing ----------------------------------------------------------------------

func _draw_hud() -> void:
	var size := _canvas.size
	_draw_crosshair(size * 0.5)
	_draw_player_panel(Vector2(36, size.y - 118))
	_draw_slots(Vector2(size.x * 0.5, size.y - 46))
	_draw_enemy_bar()
	_draw_overlays(size)
	_text(Vector2(size.x - 24, 32), "H controls · Tab loadout · F1-F4 debug", 15, Color(1, 1, 1, 0.65), HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_crosshair(center: Vector2) -> void:
	var color := Color(1, 1, 1, 0.9)
	for dir in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		_canvas.draw_line(center + dir * 6.0, center + dir * 13.0, INK, 4.0)
		_canvas.draw_line(center + dir * 6.0, center + dir * 13.0, color, 2.0)
	_canvas.draw_circle(center, 2.0, color)
	if _hit_marker > 0.0:
		var marker := (Color(1.0, 0.25, 0.2) if _kill_marker else Color.WHITE)
		marker.a = _hit_marker / 0.18
		for dir in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
			_canvas.draw_line(center + dir * 9.0, center + dir * 18.0, marker, 3.0)


func _draw_player_panel(at: Vector2) -> void:
	var s := player.state
	_bar(Rect2(at, Vector2(380, 28)), s.hp / s.max_hp, _hp_trail / s.max_hp, HEALTH)
	_text(at + Vector2(12, 21), "%d / %d" % [ceili(s.hp), roundi(s.max_hp)], 18, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, true, _bold)
	var stamina_color := STAMINA
	if s.exhausted > 0.0:
		stamina_color = EXHAUSTED.lerp(Color.WHITE, 0.35 * (0.5 + 0.5 * sin(_time * 18.0)))
	elif s.regen_delay > 0.0:
		stamina_color = STAMINA.darkened(0.25)
	_bar(Rect2(at + Vector2(0, 36), Vector2(320, 16)), s.stamina / s.max_stamina, -1.0, stamina_color)
	var chips: Array = []
	if s.exhausted > 0.0:
		chips.append(["EXHAUSTED", EXHAUSTED])
	if s.burn_time > 0.0:
		chips.append(["BURNING", SpellData.element_color(SpellData.Element.FIRE)])
	if s.chill_stacks > 0:
		chips.append(["CHILL x%d" % s.chill_stacks, SpellData.element_color(SpellData.Element.FROST)])
	if CombatRules.move_speed_mult(s, player.tuning) < 1.0:
		chips.append(["SLOWED", Color(0.6, 0.75, 1.0)])
	if s.action == FighterState.Action.STAGGER and s.stagger_kind == &"shock":
		chips.append(["SHOCKED", SpellData.element_color(SpellData.Element.LIGHTNING)])
	if s.heal_time > 0.0:
		chips.append(["HEALING", HealthOrb.COLOR])
	var x := at.x
	for chip: Array in chips:
		x += _chip(Vector2(x, at.y + 62), chip[0], chip[1]) + 8.0


## Primary, signature and rune slots side by side, bottoms aligned on `base`.
func _draw_slots(base: Vector2) -> void:
	var s := player.state
	var pad := player_input != null and player_input.using_gamepad
	var widths := [SPELL_SLOT, SPELL_SLOT, RUNE_SLOT]
	var left := base.x - (SPELL_SLOT * 2.0 + RUNE_SLOT + SLOT_GAP * 2.0) * 0.5
	var casting: SpellData = s.spell if s.action == FighterState.Action.CAST and not s.spell_released else null
	for i in 3:
		var side: float = widths[i]
		var rect := Rect2(Vector2(left, base.y - side), Vector2(side, side))
		left += side + SLOT_GAP
		match i:
			0:
				var cost := player.primary.stamina_cost
				_draw_slot(i, rect, player.primary.id, player.primary.display_name, "LT" if pad else "E",
						0.0, 0.0, casting == player.primary, "%d" % roundi(cost) if cost > 0.0 else "", s.stamina < cost)
			1:
				_draw_slot(i, rect, player.signature.id, player.signature.display_name, "Y" if pad else "Q",
						s.signature_cd, player.signature.cooldown, casting == player.signature)
			2:
				_draw_slot(i, rect, player.rune.id, player.rune.display_name, "B" if pad else "R",
						s.rune_cd, player.rune.cooldown, false)


func _draw_slot(i: int, rect: Rect2, id: StringName, title: String, key: String, remaining: float, total: float,
		casting: bool, cost := "", cost_short := false) -> void:
	var accent := UiIcons.accent_of(id)
	var usable := _slot_usable(i)
	var ready := usable and remaining <= 0.0
	var flash := _ready_flash[i] / READY_FLASH
	var center := rect.get_center()
	_round_rect(rect.grow(3.0), INK, SLOT_RADIUS + 3)
	_round_rect(rect, SLOT.lerp(accent.darkened(0.72), 0.3) if ready else SLOT, SLOT_RADIUS)
	if ready:
		_canvas.draw_circle(center, rect.size.x * 0.38, Color(accent, 0.13), true, -1.0, true)
	# a cooling slot is darkened by its veil alone, so the swept part shows the icon lit
	var dim := 0.0 if usable else 0.8
	var zoom := 1.0 + 0.14 * flash * flash + (0.06 if casting else 0.0)
	UiIcons.draw(_canvas, id, center, rect.size.x - 12.0, dim, zoom)
	if remaining > 0.0 and total > 0.0:
		_sweep(rect, clampf(remaining / total, 0.0, 1.0), accent)
	var frame := accent if ready else accent.darkened(0.55)
	if casting:
		frame = Color.WHITE
	_round_frame(rect, frame, 3, SLOT_RADIUS)
	if remaining > 0.0:
		var count := "%.1f" % remaining if remaining < 1.0 else "%d" % ceili(remaining)
		_text(center + Vector2(0, 10), count, 28 if rect.size.x > 70.0 else 24, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, true, _bold)
	if flash > 0.0:
		_round_rect(rect, Color(1, 1, 1, 0.6 * flash * flash), SLOT_RADIUS)
		_round_frame(rect.grow(3.0 + 12.0 * (1.0 - flash)), Color(accent.lightened(0.5), flash), 3, SLOT_RADIUS + 4)
	if cost != "":
		_cost_badge(Vector2(rect.end.x - 2.0, rect.position.y + 2.0), cost, cost_short or not usable)
	_key_hint(Vector2(center.x, rect.end.y + 7.0), key)
	_slot_name(title, center.x, rect.position.y - 14.0, rect.size.x + SLOT_GAP - 8.0, ready)


## The cooldown sweep: a dark veil over the part of the slot still cooling,
## unwinding clockwise from 12 o'clock, with a bright hand on its edge.
func _sweep(rect: Rect2, left: float, accent: Color) -> void:
	var center := rect.get_center()
	var start := -PI * 0.5 + TAU * (1.0 - left)
	var half := rect.size * 0.5
	var veil := PackedVector2Array([center, center + _to_edge(half, start)])
	# the square's corners clockwise from top-right, then back to 12 o'clock
	for corner in [atan2(-half.y, half.x), atan2(half.y, half.x), atan2(half.y, -half.x), atan2(-half.y, -half.x) + TAU]:
		if corner > start:
			veil.append(center + _to_edge(half, corner))
	veil.append(center + Vector2(0.0, -half.y))
	for piece: PackedVector2Array in Geometry2D.intersect_polygons(veil, _rounded(rect, SLOT_RADIUS)):
		_canvas.draw_colored_polygon(piece, VEIL)
	var tip := center + _to_edge(half, start)
	_canvas.draw_line(center, tip, INK, 5.0, true)
	_canvas.draw_line(center, tip, accent.lightened(0.6), 2.5, true)


## From a rect's centre to its edge along `angle`.
static func _to_edge(half: Vector2, angle: float) -> Vector2:
	var dir := Vector2.from_angle(angle)
	var reach := INF
	if absf(dir.x) > 0.0001:
		reach = half.x / absf(dir.x)
	if absf(dir.y) > 0.0001:
		reach = minf(reach, half.y / absf(dir.y))
	return dir * reach


## A rounded rect as a polygon (to clip the cooldown veil to the slot's shape).
static func _rounded(rect: Rect2, radius: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var corners := [rect.position + Vector2(rect.size.x - radius, radius), rect.end - Vector2(radius, radius),
			rect.position + Vector2(radius, rect.size.y - radius), rect.position + Vector2(radius, radius)]
	for k in 4:
		for step in 4:
			out.append(corners[k] + Vector2.from_angle(-PI * 0.5 + PI * 0.5 * k + PI / 6.0 * step) * radius)
	return out


## The stamina a primary costs, as a sticker on the slot's corner (red when
## casting it now would overdraw you).
func _cost_badge(corner: Vector2, text: String, short: bool) -> void:
	var width := maxf(_bold.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 12.0, 26.0)
	var rect := Rect2(corner - Vector2(width * 0.75, 10.0), Vector2(width, 20.0))
	_round_rect(rect.grow(2.0), INK, 8)
	_round_rect(rect, EXHAUSTED if short else STAMINA, 6)
	_text(rect.get_center() + Vector2(0, 5), text, 14, INK, HORIZONTAL_ALIGNMENT_CENTER, false, _bold)


## A slot's name above it, shrunk (then split onto two lines) to fit its width.
func _slot_name(text: String, x: float, bottom: float, width: float, ready: bool) -> void:
	var key := "%s@%d" % [text, roundi(width)]
	if not _name_fits.has(key):
		_name_fits[key] = _fit_name(text, width)
	var fit: Array = _name_fits[key]
	var lines: PackedStringArray = fit[0]
	var size: int = fit[1]
	var color := Color(1, 1, 1, 0.92) if ready else Color(0.8, 0.76, 0.84, 0.85)
	for k in lines.size():
		_text(Vector2(x, bottom - (lines.size() - 1 - k) * (size + 2)), lines[k], size, color, HORIZONTAL_ALIGNMENT_CENTER)


func _fit_name(text: String, width: float) -> Array:
	for size in [15, 14, 13]:
		if _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= width:
			return [PackedStringArray([text]), size]
	var words := text.split(" ")
	if words.size() < 2:
		return [PackedStringArray([text]), 13]
	# break at the space that leaves the two lines most even
	var best := 1
	var best_gap := INF
	for cut in range(1, words.size()):
		var gap := absf(" ".join(words.slice(0, cut)).length() - " ".join(words.slice(cut)).length())
		if gap < best_gap:
			best_gap = gap
			best = cut
	return [PackedStringArray([" ".join(words.slice(0, best)), " ".join(words.slice(best))]), 14]


func _draw_enemy_bar() -> void:
	if camera == null or bot.state.is_dead():
		return
	# well above the head, so rising damage numbers don't cover it
	var head := bot.global_position + Vector3.UP * 2.8
	if camera.is_position_behind(head):
		return
	var point := camera.unproject_position(head)
	var rect := Rect2(point - Vector2(70, 0), Vector2(140, 12))
	_bar(rect, bot.state.hp / bot.state.max_hp, _bot_trail / bot.state.max_hp, HEALTH)
	var label := bot.display_name
	if bot_brain and bot.controller == bot_brain:
		label += " · %s" % BotBrain.MODE_NAMES[bot_brain.mode]
	_text(point + Vector2(0, -8), label, 15, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	var pips: Array = []
	var s := bot.state
	if s.burn_time > 0.0:
		pips.append(["BURN", SpellData.element_color(SpellData.Element.FIRE)])
	if s.chill_stacks > 0:
		pips.append(["CHILL x%d" % s.chill_stacks, SpellData.element_color(SpellData.Element.FROST)])
	if s.action == FighterState.Action.STAGGER and s.stagger_kind == &"shock":
		pips.append(["SHOCKED", SpellData.element_color(SpellData.Element.LIGHTNING)])
	if pips.is_empty():
		return
	var widths: Array[float] = []
	var total := -6.0
	for pip: Array in pips:
		widths.append(_font.get_string_size(pip[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 12.0)
		total += widths[-1] + 6.0
	var x := point.x - total * 0.5
	for k in pips.size():
		var pip: Array = pips[k]
		var chip := Rect2(Vector2(x, point.y - 46), Vector2(widths[k], 17))
		_round_rect(chip.grow(2.0), INK, 5)
		_round_rect(chip, (pip[1] as Color).darkened(0.55), 4)
		_text(Vector2(chip.get_center().x, chip.end.y - 4), pip[0], 12, (pip[1] as Color).lightened(0.35), HORIZONTAL_ALIGNMENT_CENTER, false)
		x += widths[k] + 6.0


func _draw_overlays(size: Vector2) -> void:
	if player.state.is_dead():
		_canvas.draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.02, 0.06, 0.45))
		var left := maxf(player.tuning.respawn_time - player.state.dead_time, 0.0)
		_text(size * 0.5 + Vector2(0, -20), "DOWN!", 64, EXHAUSTED, HORIZONTAL_ALIGNMENT_CENTER, true, _bold)
		_text(size * 0.5 + Vector2(0, 30), "back in %.1f" % left, 26, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	if _banner_time > 0.0:
		var pop := 1.0 + 0.25 * maxf(_banner_time - 1.6, 0.0) / 0.2
		var color := Color(1.0, 0.85, 0.3, minf(_banner_time / 0.4, 1.0))
		_text(Vector2(size.x * 0.5, 150), _banner, int(52 * pop), color, HORIZONTAL_ALIGNMENT_CENTER, true, _bold)


# --- primitives -------------------------------------------------------------------

## A comic bar: ink border, dark trough, optional white damage trail, fill.
func _bar(rect: Rect2, fill: float, trail: float, color: Color) -> void:
	_canvas.draw_rect(rect.grow(3), INK)
	_canvas.draw_rect(rect, Color(0.18, 0.12, 0.22))
	if trail > fill:
		_canvas.draw_rect(Rect2(rect.position, Vector2(rect.size.x * clampf(trail, 0, 1), rect.size.y)), TRAIL)
	_canvas.draw_rect(Rect2(rect.position, Vector2(rect.size.x * clampf(fill, 0, 1), rect.size.y)), color)
	_canvas.draw_rect(Rect2(rect.position, Vector2(rect.size.x * clampf(fill, 0, 1), rect.size.y * 0.3)), Color(1, 1, 1, 0.18))


func _chip(at: Vector2, label: String, color: Color) -> float:
	var width := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 16.0
	var rect := Rect2(at, Vector2(width, 22))
	_canvas.draw_rect(rect.grow(2), INK)
	_canvas.draw_rect(rect, color.darkened(0.55))
	_text(at + Vector2(8, 16), label, 14, color.lightened(0.3))
	return width


func _key_hint(top_center: Vector2, key: String) -> void:
	var width := maxf(_bold.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 12.0, 24.0)
	var rect := Rect2(top_center - Vector2(width * 0.5, 0), Vector2(width, 20))
	_round_rect(rect.grow(2.0), INK, 6)
	_round_rect(rect, Color(1, 1, 1, 0.92), 4)
	_text(rect.get_center() + Vector2(0, 5), key, 14, INK, HORIZONTAL_ALIGNMENT_CENTER, false, _bold)


func _round_rect(rect: Rect2, color: Color, radius: int) -> void:
	_fill_box.bg_color = color
	_fill_box.set_corner_radius_all(radius)
	_canvas.draw_style_box(_fill_box, rect)


func _round_frame(rect: Rect2, color: Color, width: int, radius: int) -> void:
	_frame_box.border_color = color
	_frame_box.set_border_width_all(width)
	_frame_box.set_corner_radius_all(radius)
	_canvas.draw_style_box(_frame_box, rect)


func _text(at: Vector2, text: String, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT, outline := true, font: Font = null) -> void:
	var face := font if font else _font
	var origin := at
	if align != HORIZONTAL_ALIGNMENT_LEFT:
		var width := face.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		origin.x -= width * (0.5 if align == HORIZONTAL_ALIGNMENT_CENTER else 1.0)
	if outline:
		_canvas.draw_string_outline(face, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, maxi(size / 5, 3), INK)
	_canvas.draw_string(face, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _build_controls_panel() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiTheme.make()
	root.visible = false
	var panel := PanelContainer.new()
	panel.position = Vector2(24, 60)
	root.add_child(panel)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override(&"h_separation", 22)
	grid.add_theme_constant_override(&"v_separation", 4)
	panel.add_child(grid)
	var rows := [
		["", "Keyboard / mouse", "Controller"],
		["Move / look", "WASD / mouse", "Left / right stick"],
		["Light attack", "Left mouse", "RB"],
		["Heavy attack", "F or mouse thumb", "RT"],
		["Block (hold) / parry (tap)", "Right mouse", "LB"],
		["Dash-step", "Space", "A"],
		["Sprint", "Shift (hold)", "L3 (click)"],
		["Primary spell", "E", "LT"],
		["Signature spell", "Q", "Y"],
		["Mobility rune", "R", "B"],
		["Loadout menu", "Tab", "Start"],
		["Quick-swap primary spell", "T", "D-pad right"],
		["Tuning / hitboxes / slow-mo / log", "F1 / F2 / F3 / F4", "Back / D-pad up / down / left"],
		["Free the mouse", "Esc", ""],
	]
	for r in rows.size():
		for cell: String in rows[r]:
			var label := Label.new()
			label.text = cell
			label.add_theme_font_size_override(&"font_size", 17)
			if r == 0:
				label.add_theme_color_override(&"font_color", UiTheme.GOLD)
			grid.add_child(label)
	return root
