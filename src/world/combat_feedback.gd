class_name CombatFeedback
extends Node3D
## Cosmetic reactions to combat events: impact stars and camera shake.
## Listens to CombatEvents only; never touches simulation state.

const HIT_COLOR := Color(1.0, 0.94, 0.7)
const BLOCK_COLOR := Color(0.55, 0.8, 1.0)
const BREAK_COLOR := Color(1.0, 0.3, 0.25)
const PARRY_COLOR := Color(1.0, 0.85, 0.2)

var camera_rig: CameraRig
## The local player; shake only when they're involved.
var focus: Fighter


func _ready() -> void:
	CombatEvents.hit_resolved.connect(_on_hit_resolved)
	CombatEvents.landed.connect(_on_landed)


func _on_landed(fighter: Node) -> void:
	Vfx.ring(self, (fighter as Fighter).global_position, Color(0.75, 0.95, 1.0), 1.8, 0.3)
	if camera_rig and fighter == focus:
		camera_rig.add_trauma(0.18)


func _on_hit_resolved(attacker: Node, defender: Node, result: HitResult, at: Vector3) -> void:
	if result.periodic and result.reaction == &"":
		return  # ground-fire ticks: the burning tint on the body says enough
	var color := HIT_COLOR
	var size := 0.8 + result.damage / 25.0
	var trauma := 0.22 + result.damage / 70.0
	match result.outcome:
		HitResult.Outcome.BLOCKED:
			color = BLOCK_COLOR
			size = 0.8
			trauma = 0.15
		HitResult.Outcome.GUARD_BREAK:
			color = BREAK_COLOR
			size = 1.6
			trauma = 0.5
		HitResult.Outcome.PARRIED:
			color = PARRY_COLOR
			size = 1.8
			trauma = 0.4
	if result.element != SpellData.Element.NONE and result.outcome == HitResult.Outcome.HIT:
		color = SpellData.element_color(result.element)
	if result.reaction == &"shatter":
		color = Color(0.85, 0.55, 1.0)
		size = 2.2
		trauma = 0.6
		Vfx.shards(self, at, SpellData.element_color(SpellData.Element.FROST), 12, 2.2)
	Vfx.impact(self, at, color, size)
	if camera_rig and (attacker == focus or defender == focus):
		camera_rig.add_trauma(trauma)
