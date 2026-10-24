class_name UiTheme
extends RefCounted
## The shared comic-book UI look: dark violet panels with a gold ink border,
## chunky buttons and a heavy display font. Built in code so every screen
## stays consistent.

const INK := Color(0.06, 0.03, 0.09)
const PANEL := Color(0.11, 0.07, 0.16, 0.94)
const GOLD := Color(1.0, 0.78, 0.3)
const TEXT := Color(0.98, 0.94, 0.86)
const MUTED := Color(0.72, 0.66, 0.78)

static var _bold: FontVariation
static var _heading: FontVariation
static var _impact: FontVariation


static func make() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 20
	theme.set_stylebox(&"panel", &"PanelContainer", _box(PANEL, GOLD, 4, 12))
	theme.set_stylebox(&"panel", &"Panel", _box(PANEL, GOLD, 4, 12))
	theme.set_stylebox(&"normal", &"Button", _box(Color(0.2, 0.13, 0.27), INK, 3, 8))
	theme.set_stylebox(&"hover", &"Button", _box(Color(0.3, 0.2, 0.4), GOLD, 3, 8))
	theme.set_stylebox(&"pressed", &"Button", _box(Color(0.42, 0.28, 0.5), GOLD, 3, 8))
	theme.set_stylebox(&"focus", &"Button", _box(Color(0, 0, 0, 0), GOLD, 3, 8))
	for kind: StringName in [&"OptionButton", &"SpinBox", &"LineEdit"]:
		theme.set_stylebox(&"normal", kind, _box(Color(0.2, 0.13, 0.27), INK, 3, 8))
		theme.set_stylebox(&"focus", kind, _box(Color(0, 0, 0, 0), GOLD, 3, 8))
	theme.set_stylebox(&"hover", &"OptionButton", _box(Color(0.3, 0.2, 0.4), GOLD, 3, 8))
	theme.set_stylebox(&"pressed", &"OptionButton", _box(Color(0.42, 0.28, 0.5), GOLD, 3, 8))
	theme.set_stylebox(&"panel", &"TooltipPanel", _box(Color(0.08, 0.05, 0.12, 0.97), GOLD, 2, 6))
	theme.set_color(&"font_color", &"TooltipLabel", TEXT)
	theme.set_font_size(&"font_size", &"TooltipLabel", 16)
	theme.set_color(&"font_color", &"Label", TEXT)
	theme.set_color(&"font_color", &"Button", TEXT)
	theme.set_color(&"font_color", &"OptionButton", TEXT)
	theme.set_color(&"font_outline_color", &"Label", INK)
	theme.set_constant(&"outline_size", &"Label", 4)
	return theme


static func _box(fill: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(radius)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	return box


static func title(text: String, size := 30) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override(&"font", bold_font())
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", GOLD)
	label.add_theme_constant_override(&"outline_size", 8)
	return label


## A small gold all-caps heading with a little letter spacing (section titles).
static func heading(text: String, size := 17) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_font_override(&"font", heading_font())
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", GOLD)
	label.add_theme_constant_override(&"outline_size", 6)
	return label


## The UI font made heavier: titles, names and the HUD's numbers.
static func bold_font() -> Font:
	if _bold == null:
		_bold = FontVariation.new()
		_bold.base_font = ThemeDB.fallback_font
		_bold.variation_embolden = 0.85
	return _bold


## Extra heavy and slanted forward, for punchy comic numbers and shouts.
static func impact_font() -> Font:
	if _impact == null:
		_impact = FontVariation.new()
		_impact.base_font = ThemeDB.fallback_font
		_impact.variation_embolden = 1.25
		_impact.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(-0.2, 1.0), Vector2.ZERO)
		_impact.spacing_glyph = 1
	return _impact


static func heading_font() -> Font:
	if _heading == null:
		_heading = FontVariation.new()
		_heading.base_font = ThemeDB.fallback_font
		_heading.variation_embolden = 0.7
		_heading.spacing_glyph = 2
	return _heading
