class_name Hud
extends CanvasLayer
## The in-fight HUD, drawn by hand each frame: health and stamina bars,
## status chips, ability slots with cooldowns, crosshair and hit-markers, the
## enemy's bar over their head, the respawn overlay and kill banners. Reads
## simulation state only.

const INK := Color(0.06, 0.03, 0.09)
const HEALTH := Color(0.95, 0.27, 0.32)
const TRAIL := Color(1.0, 0.95, 0.85)
const STAMINA := Color(1.0, 0.84, 0.3)
const EXHAUSTED := Color(1.0, 0.3, 0.22)
const SLOT := Color(0.15, 0.1, 0.2, 0.92)

var player: Fighter
var bot: Fighter
var bot_brain: BotBrain
var player_input: PlayerInput
var camera: Camera3D

var _canvas: Control
var _font: Font
var _hp_trail := 100.0
var _bot_trail := 100.0
var _hit_marker := 0.0
var _kill_marker := false
var _banner := ""
var _banner_time := 0.0
var _controls: Control
var _time := 0.0


func _ready() -> void:
	layer = 5
	_font = ThemeDB.fallback_font
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


# --- drawing ----------------------------------------------------------------------

func _draw_hud() -> void:
	var size := _canvas.size
	_draw_crosshair(size * 0.5)
	_draw_player_panel(Vector2(36, size.y - 118))
	_draw_slots(Vector2(size.x * 0.5, size.y - 64))
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
	_text(at + Vector2(12, 21), "%d / %d" % [ceili(s.hp), roundi(s.max_hp)], 18, Color.WHITE)
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
	if s.heal_time > 0.0:
		chips.append(["HEALING", HealthOrb.COLOR])
	var x := at.x
	for chip: Array in chips:
		x += _chip(Vector2(x, at.y + 62), chip[0], chip[1]) + 8.0


func _draw_slots(center: Vector2) -> void:
	var s := player.state
	var pad := player_input != null and player_input.using_gamepad
	var gauntlet := player.gauntlet
	var color := SpellData.element_color(gauntlet.element)
	var slots := [
		[gauntlet.primary.display_name, "LT" if pad else "E", 0.0, 0.0, "%d" % roundi(gauntlet.primary.stamina_cost), s.can_spend()],
		[gauntlet.signature.display_name, "Y" if pad else "Q", s.signature_cd, gauntlet.signature.cooldown, "", true],
		[player.rune.display_name, "B" if pad else "R", s.rune_cd, player.rune.cooldown, "", s.exhausted <= 0.0],
	]
	var width := 76.0
	var gap := 14.0
	var left := center.x - (width * 3 + gap * 2) * 0.5
	for i in slots.size():
		var slot: Array = slots[i]
		var rect := Rect2(Vector2(left + i * (width + gap), center.y - width * 0.5 - 6), Vector2(width, width))
		_canvas.draw_rect(rect.grow(3), INK)
		_canvas.draw_rect(rect, SLOT)
		var icon_color: Color = color if i < 2 else Color(0.82, 0.68, 1.0)
		if not slot[5]:
			icon_color = icon_color.darkened(0.6)
		_draw_icon(rect.get_center(), i, icon_color)
		var remaining: float = slot[2]
		if remaining > 0.0:
			_pie(rect.get_center(), width * 0.5, remaining / maxf(slot[3], 0.01), Color(0, 0, 0, 0.62))
			_text(rect.get_center() + Vector2(0, 8), "%.0f" % ceilf(remaining), 24, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
		if slot[4] != "":
			_text(rect.position + Vector2(width - 6, 18), slot[4], 14, STAMINA, HORIZONTAL_ALIGNMENT_RIGHT)
		_key_hint(Vector2(rect.get_center().x, rect.end.y + 4), slot[1])
		_text(Vector2(rect.get_center().x, rect.position.y - 8), slot[0], 14, Color(1, 1, 1, 0.85), HORIZONTAL_ALIGNMENT_CENTER)


func _draw_icon(c: Vector2, slot: int, color: Color) -> void:
	if slot == 2:
		if player.rune is LeapRune:
			for k in 2:
				var y := c.y + 8.0 - k * 14.0
				_canvas.draw_polyline([Vector2(c.x - 14, y + 8), Vector2(c.x, y - 6), Vector2(c.x + 14, y + 8)], color, 5.0)
		else:
			for k in 2:
				var x := c.x - 8.0 + k * 14.0
				_canvas.draw_polyline([Vector2(x - 8, c.y - 14), Vector2(x + 6, c.y), Vector2(x - 8, c.y + 14)], color, 5.0)
		return
	if player.gauntlet.element == SpellData.Element.FROST:
		for k in 3:
			var dir := Vector2.from_angle(k * PI / 3.0) * (20.0 if slot == 0 else 24.0)
			_canvas.draw_line(c - dir, c + dir, color, 4.0)
		if slot == 1:
			_canvas.draw_arc(c, 26.0, 0, TAU, 32, color, 3.0)
	else:
		var flame := PackedVector2Array([c + Vector2(0, -24), c + Vector2(14, 6), c + Vector2(8, 18),
				c + Vector2(-8, 18), c + Vector2(-14, 6)])
		_canvas.draw_colored_polygon(flame, color)
		_canvas.draw_circle(c + Vector2(0, 8), 7.0, Color(1, 0.95, 0.7))
		if slot == 1:
			_canvas.draw_line(c + Vector2(-26, 24), c + Vector2(26, 24), color, 5.0)


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
	var pips := ""
	if bot.state.burn_time > 0.0:
		pips += "BURN  "
	if bot.state.chill_stacks > 0:
		pips += "CHILL x%d" % bot.state.chill_stacks
	if pips != "":
		_text(point + Vector2(0, -28), pips.strip_edges(), 13, Color(0.75, 0.9, 1.0), HORIZONTAL_ALIGNMENT_CENTER)


func _draw_overlays(size: Vector2) -> void:
	if player.state.is_dead():
		_canvas.draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.02, 0.06, 0.45))
		var left := maxf(player.tuning.respawn_time - player.state.dead_time, 0.0)
		_text(size * 0.5 + Vector2(0, -20), "DOWN!", 64, EXHAUSTED, HORIZONTAL_ALIGNMENT_CENTER)
		_text(size * 0.5 + Vector2(0, 30), "back in %.1f" % left, 26, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	if _banner_time > 0.0:
		var pop := 1.0 + 0.25 * maxf(_banner_time - 1.6, 0.0) / 0.2
		var color := Color(1.0, 0.85, 0.3, minf(_banner_time / 0.4, 1.0))
		_text(Vector2(size.x * 0.5, 150), _banner, int(52 * pop), color, HORIZONTAL_ALIGNMENT_CENTER)


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
	var width := maxf(_font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 12.0, 24.0)
	var rect := Rect2(top_center - Vector2(width * 0.5, 0), Vector2(width, 20))
	_canvas.draw_rect(rect, Color(1, 1, 1, 0.9))
	_text(rect.get_center() + Vector2(0, 5), key, 14, INK, HORIZONTAL_ALIGNMENT_CENTER, false)


## A pie slice from 12 o'clock covering `fraction` of the circle (cooldowns).
func _pie(center: Vector2, radius: float, fraction: float, color: Color) -> void:
	var points := PackedVector2Array([center])
	var steps := 32
	for i in steps + 1:
		var angle := -PI * 0.5 + TAU * fraction * float(i) / steps
		points.append(center + Vector2.from_angle(angle) * radius)
	if points.size() >= 3:
		_canvas.draw_colored_polygon(points, color)


func _text(at: Vector2, text: String, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT, outline := true) -> void:
	var width := -1.0
	var origin := at
	if align != HORIZONTAL_ALIGNMENT_LEFT:
		width = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		origin.x -= width * (0.5 if align == HORIZONTAL_ALIGNMENT_CENTER else 1.0)
	if outline:
		_canvas.draw_string_outline(_font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, maxi(size / 5, 3), INK)
	_canvas.draw_string(_font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


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
		["Quick-swap gauntlet", "T", "D-pad right"],
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
