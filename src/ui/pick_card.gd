class_name PickCard
extends Button
## A selectable card in the loadout menus (a spell or a rune): its icon on a
## medallion tinted with the element, the name, a one-line pitch and its
## damage and cost. The picked card is unmistakable: it glows in its element's
## color under a thick gold frame with a check badge, while the others sit
## dark. It's a real Button, so mouse, keyboard and controller focus all work.

const SIZE := Vector2(304, 108)
## One-line pitches for the cards (the full descriptions are in the data).
const TAGLINES := {
	&"firebolt": "Fast fireball; the splash sets foes Burning.",
	&"ice_spike": "One heavy spike that Chills. Fire Shatters it!",
	&"lightning_bolt": "Near-instant bolt that interrupts attacks.",
	&"wind_slash": "Wide crescent of wind that shoves foes back.",
	&"flame_wall": "A wall of fire across your aim. Unblockable.",
	&"frost_nova": "Frost blast all around you: Chill and slow.",
	&"lightning_strike": "Marks the ground, then the sky strikes. Stuns.",
	&"wind_spear": "Bursts into a gale that blows everyone away.",
	&"leap": "A huge jump, then a slow, floaty fall.",
	&"blink": "Teleport a short hop the way you're moving.",
}

var payload := &""
var item: Resource

var _accent := Color.WHITE
var _icon: UiIconView
var _title: Label
var _blurb: Label
var _stats: Label


func setup(source: Resource) -> void:
	item = source
	payload = source.id
	_accent = UiIcons.accent_of(source.id)
	toggle_mode = true
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = SIZE
	clip_contents = false
	_apply_styles()

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override(&"margin_left", 12)
	margin.add_theme_constant_override(&"margin_right", 12)
	margin.add_theme_constant_override(&"margin_top", 8)
	margin.add_theme_constant_override(&"margin_bottom", 8)
	add_child(margin)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 12)
	margin.add_child(row)
	_icon = UiIconView.new(source.id, 70.0, true)
	_icon.fill = 0.72
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_icon)
	var text := VBoxContainer.new()
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override(&"separation", 1)
	row.add_child(text)
	_title = _label(source.display_name, 21)
	_title.add_theme_font_override(&"font", UiTheme.bold_font())
	text.add_child(_title)
	_blurb = _label(tagline(source), 15)
	_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_blurb.max_lines_visible = 2
	_blurb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_blurb.add_theme_constant_override(&"line_spacing", -2)
	text.add_child(_blurb)
	_stats = _label(stat_line(source), 14)
	_stats.add_theme_font_override(&"font", UiTheme.bold_font())
	text.add_child(_stats)
	toggled.connect(func(_on: bool) -> void: _restyle())
	_restyle()


## Selects or deselects without emitting a signal (menus syncing to a loadout).
func set_selected(on: bool) -> void:
	set_pressed_no_signal(on)
	_restyle()


## The card's one-line pitch: a hand-written tagline, or the description's
## first clause for anything new.
static func tagline(source: Resource) -> String:
	if TAGLINES.has(source.id):
		return TAGLINES[source.id]
	var text: String = source.description
	var cut := text.find(":")
	return text if cut < 0 else text.substr(0, cut) + "."


## `text` broken into lines of about `width` characters (tooltips don't wrap).
static func wrapped(text: String, width := 60) -> String:
	var lines: Array[String] = []
	var line := ""
	for word in text.split(" "):
		if line != "" and line.length() + word.length() + 1 > width:
			lines.append(line)
			line = word
		else:
			line = word if line == "" else line + " " + word
	lines.append(line)
	return "
".join(lines)


## Damage and cost from the data, e.g. "12 dmg · 15 stamina".
static func stat_line(source: Resource) -> String:
	var parts: Array[String] = []
	if source is FlameWallSpell:
		parts.append("%d dmg/s" % roundi((source as FlameWallSpell).damage_per_second))
	elif source.get(&"damage") != null and float(source.get(&"damage")) > 0.0:
		parts.append("%d dmg" % roundi(float(source.get(&"damage"))))
	if source is SpellData and (source as SpellData).slot == SpellData.Slot.PRIMARY:
		parts.append("%d stamina" % roundi((source as SpellData).stamina_cost))
	else:
		parts.append("%ds cooldown" % roundi(float(source.get(&"cooldown"))))
	return " · ".join(parts)


func _draw() -> void:
	if not button_pressed:
		return
	# the check badge in the top-right corner
	var at := Vector2(size.x - 4.0, 4.0)
	draw_circle(at, 13.0, UiTheme.INK, true, -1.0, true)
	draw_circle(at, 10.5, UiTheme.GOLD, true, -1.0, true)
	draw_polyline(PackedVector2Array([at + Vector2(-5.0, 0.0), at + Vector2(-1.5, 4.0), at + Vector2(5.0, -4.0)]),
			UiTheme.INK, 3.0, true)


func _restyle() -> void:
	var on := button_pressed
	_title.add_theme_color_override(&"font_color", _accent.lightened(0.55) if on else _accent.lightened(0.2))
	_blurb.add_theme_color_override(&"font_color", UiTheme.TEXT if on else UiTheme.MUTED)
	_stats.add_theme_color_override(&"font_color", UiTheme.GOLD if on else UiTheme.GOLD.darkened(0.3))
	_icon.ring = UiTheme.GOLD if on else _accent.darkened(0.35)
	_icon.dim = 0.0 if on else 0.15
	queue_redraw()


func _label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override(&"font_size", size)
	return label


func _apply_styles() -> void:
	var dark := Color(0.1, 0.06, 0.14, 0.96)
	var lit := Color(0.12, 0.07, 0.17).lerp(_accent, 0.24)
	add_theme_stylebox_override(&"normal", _box(dark, _accent.darkened(0.5), 2))
	add_theme_stylebox_override(&"hover", _box(dark.lerp(_accent, 0.08), _accent, 3))
	add_theme_stylebox_override(&"pressed", _box(lit, UiTheme.GOLD, 4, _accent))
	add_theme_stylebox_override(&"hover_pressed", _box(lit.lightened(0.06), UiTheme.GOLD, 4, _accent))
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = Color.WHITE
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(14)
	focus.set_expand_margin_all(5)
	focus.anti_aliasing = true
	add_theme_stylebox_override(&"focus", focus)


static func _box(fill: Color, border: Color, width: int, glow := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(10)
	box.anti_aliasing = true
	if glow.a > 0.0:
		box.shadow_color = Color(glow, 0.5)
		box.shadow_size = 12
	else:
		box.shadow_color = Color(0, 0, 0, 0.35)
		box.shadow_size = 4
		box.shadow_offset = Vector2(0, 2)
	return box
