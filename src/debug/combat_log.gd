class_name CombatLog
extends PanelContainer
## F4: a running log of what just happened (hits, blocks, parries, breaks,
## reactions, kills with their TTK), plus TTK averages for the session.

const MAX_LINES := 12

var _lines: Array[String] = []
var _ttk := TtkTracker.new()
var _body: Label
var _summary: Label


func _ready() -> void:
	theme = UiTheme.make()
	position = Vector2(20, 54)
	custom_minimum_size = Vector2(520, 0)
	visible = false
	var box := VBoxContainer.new()
	add_child(box)
	box.add_child(UiTheme.title("Combat log  (F4)", 20))
	_summary = Label.new()
	_summary.add_theme_font_size_override(&"font_size", 15)
	_summary.add_theme_color_override(&"font_color", UiTheme.GOLD)
	box.add_child(_summary)
	_body = Label.new()
	_body.add_theme_font_size_override(&"font_size", 15)
	box.add_child(_body)
	add_child(_ttk)
	_ttk.kill_measured.connect(_on_kill)
	CombatEvents.hit_resolved.connect(_on_hit)
	CombatEvents.orb_taken.connect(func(f: Node) -> void: _add("%s grabbed a health orb" % _name(f)))
	CombatEvents.fighter_respawned.connect(func(f: Node) -> void: _add("%s respawned" % _name(f)))
	_refresh()


func _on_hit(attacker: Node, defender: Node, result: HitResult, _at: Vector3) -> void:
	if result.periodic and result.reaction == &"":
		return
	var what: String = HitResult.Outcome.keys()[result.outcome].replace("_", " ").to_lower()
	var line := "%s -> %s  %s %s" % [_name(attacker), _name(defender), result.source, what]
	if result.damage > 0.0:
		line += "  %.0f" % result.damage
	if result.reaction != &"":
		line += "  (%s!)" % String(result.reaction).to_upper()
	_add(line)


func _on_kill(victim: Node, killer: Node, wall_clock: float, under_fire: float) -> void:
	_add("%s killed %s: TTK %.1fs under fire (%.1fs from first hit)" % [_name(killer), _name(victim), under_fire, wall_clock])


func _add(line: String) -> void:
	_lines.append("[%5.1f] %s" % [_ttk.time, line])
	if _lines.size() > MAX_LINES:
		_lines.pop_front()
	_refresh()


func _refresh() -> void:
	_body.text = "\n".join(_lines) if not _lines.is_empty() else "(nothing yet)"
	_summary.text = TtkTracker.summary("TTK under fire", _ttk.under_fire)


static func _name(node: Node) -> String:
	return (node as Fighter).display_name if node is Fighter else "burn"
