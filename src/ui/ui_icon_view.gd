class_name UiIconView
extends Control
## A spell or rune icon (UiIcons) as a Control, optionally on a round
## medallion tinted with the icon's element. Purely visual: it ignores the mouse.

var icon_id := &"":
	set(value):
		icon_id = value
		queue_redraw()
## 0..1: greys the icon out.
var dim := 0.0:
	set(value):
		dim = value
		queue_redraw()
## Draw a round element-tinted medallion behind the icon.
var medallion := false
## Medallion ring color; transparent uses the icon's accent.
var ring := Color(0, 0, 0, 0):
	set(value):
		ring = value
		queue_redraw()
## Icon size as a fraction of the control's shorter side.
var fill := 0.8


func _init(id := &"", side := 64.0, with_medallion := false) -> void:
	icon_id = id
	medallion = with_medallion
	custom_minimum_size = Vector2(side, side)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var side := minf(size.x, size.y)
	var center := size * 0.5
	if medallion:
		var accent := UiIcons.accent_of(icon_id)
		var rim := ring if ring.a > 0.0 else accent.darkened(0.15)
		draw_circle(center, side * 0.5, UiTheme.INK, true, -1.0, true)
		draw_circle(center, side * 0.5 - 2.0, rim, true, -1.0, true)
		draw_circle(center, side * 0.5 - 5.0, accent.darkened(0.78).lerp(Color(0.1, 0.06, 0.14), 0.35), true, -1.0, true)
		draw_circle(center + Vector2(0, -side * 0.08), side * 0.3, Color(accent, 0.12), true, -1.0, true)
	UiIcons.draw(self, icon_id, center, side * fill, dim)
