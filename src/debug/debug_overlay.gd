class_name DebugOverlay
extends CanvasLayer
## Debug keys: F1 tuning panel, F2 hitbox view, F3 slow motion, F4 combat log
## (controller: Back, D-pad up / down / left). Handled in _input so they work
## even while a UI control has focus.

signal tuning_toggled(open: bool)

const SLOWMO_SCALE := 0.25

var tuning_panel: TuningPanel
var combat_log: CombatLog
var hitbox_viz: HitboxViz

var _badge: Label


func _ready() -> void:
	layer = 8
	tuning_panel = TuningPanel.new()
	var entries: Array = [["Combat", GameData.tuning]]
	for id: StringName in GameData.weapons:
		entries.append([GameData.weapons[id].display_name, GameData.weapons[id]])
	for id: StringName in GameData.spells:
		entries.append(["%s (spell)" % GameData.spells[id].display_name, GameData.spells[id]])
	for id: StringName in GameData.runes:
		entries.append(["%s rune" % GameData.runes[id].display_name, GameData.runes[id]])
	tuning_panel.setup(entries)
	tuning_panel.visible = false
	add_child(tuning_panel)
	combat_log = CombatLog.new()
	add_child(combat_log)
	_badge = UiTheme.title("", 22)
	_badge.position = Vector2(20, 14)
	add_child(_badge)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_tuning"):
		tuning_panel.visible = not tuning_panel.visible
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if tuning_panel.visible else Input.MOUSE_MODE_CAPTURED
		tuning_toggled.emit(tuning_panel.visible)
	elif event.is_action_pressed(&"debug_hitboxes"):
		hitbox_viz.visible = not hitbox_viz.visible
	elif event.is_action_pressed(&"debug_slowmo"):
		Engine.time_scale = 1.0 if Engine.time_scale < 1.0 else SLOWMO_SCALE
	elif event.is_action_pressed(&"debug_log"):
		combat_log.visible = not combat_log.visible
	else:
		return
	get_viewport().set_input_as_handled()
	_update_badge()


func _update_badge() -> void:
	var tags: Array[String] = []
	if Engine.time_scale < 1.0:
		tags.append("SLOW-MO x%.2f" % Engine.time_scale)
	if hitbox_viz.visible:
		tags.append("HITBOXES")
	_badge.text = "   ".join(tags)
