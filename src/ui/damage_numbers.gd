class_name DamageNumbers
extends Node3D
## Floating comic text for hits: damage numbers in the element's color, and
## shouts for blocks, parries, guard breaks and Shatter.

const INK := Color(0.06, 0.03, 0.09)


func _ready() -> void:
	CombatEvents.hit_resolved.connect(_on_hit)
	CombatEvents.status_damage.connect(_on_status_damage)


func _on_hit(_attacker: Node, _defender: Node, result: HitResult, at: Vector3) -> void:
	match result.outcome:
		HitResult.Outcome.PARRIED:
			_pop(at, "PARRY!", Color(1.0, 0.85, 0.2), 1.4)
			return
		HitResult.Outcome.BLOCKED:
			_pop(at, "BLOCK" if result.damage < 0.5 else "%d" % roundi(result.damage), Color(0.55, 0.8, 1.0), 0.8)
			return
		HitResult.Outcome.GUARD_BREAK:
			_pop(at + Vector3.UP * 0.3, "GUARD BREAK!", Color(1.0, 0.3, 0.25), 1.3)
	if result.reaction == &"shatter":
		_pop(at + Vector3.UP * 0.4, "SHATTER!", Color(0.85, 0.55, 1.0), 1.6)
	if result.damage >= 0.5:
		var color := Color(1.0, 0.97, 0.9)
		if result.element != SpellData.Element.NONE:
			color = SpellData.element_color(result.element).lightened(0.25)
		var scale := 0.7 if result.periodic else 0.8 + result.damage / 40.0
		_pop(at, "%d" % roundi(result.damage), color, scale)


func _on_status_damage(fighter: Node, amount: float, element: int) -> void:
	_pop((fighter as Fighter).chest_position() + Vector3.UP * 0.4, "%.0f" % ceilf(amount),
			SpellData.element_color(element).lightened(0.2), 0.6)


func _pop(at: Vector3, text: String, color: Color, scale: float) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 72
	label.outline_size = 18
	label.outline_modulate = INK
	label.modulate = color
	label.pixel_size = 0.0045 * scale
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.render_priority = 10
	label.outline_render_priority = 9
	add_child(label)
	label.global_position = at + Vector3(randf_range(-0.3, 0.3), randf_range(0.0, 0.25), randf_range(-0.3, 0.3))
	var tween := label.create_tween().set_parallel()
	tween.tween_property(label, "global_position", label.global_position + Vector3.UP * 0.9, 0.8) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(label, "modulate:a", 0.0, 0.35).set_delay(0.45)
	tween.tween_property(label, "outline_modulate:a", 0.0, 0.35).set_delay(0.45)
	tween.chain().tween_callback(label.queue_free)
