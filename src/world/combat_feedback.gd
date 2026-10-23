class_name CombatFeedback
extends Node3D
## Cosmetic reactions to combat events: impact stars, camera shake, a
## directional camera kick and an FOV punch on the big moments.
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
		camera_rig.kick(Vector3.DOWN, 0.35)


func _on_hit_resolved(attacker: Node, defender: Node, result: HitResult, at: Vector3) -> void:
	if result.periodic and result.reaction == &"":
		return  # ground-fire ticks: the burning tint on the body says enough
	var color := HIT_COLOR
	var size := 0.8 + result.damage / 25.0
	var trauma := 0.22 + result.damage / 70.0
	var kick := 0.25 + result.damage / 40.0
	var punch := 2.5 if result.source == &"heavy" else 0.0
	match result.outcome:
		HitResult.Outcome.BLOCKED:
			color = BLOCK_COLOR
			size = 0.8
			trauma = 0.15
			kick = 0.3
			punch = 0.0
		HitResult.Outcome.GUARD_BREAK:
			color = BREAK_COLOR
			size = 1.6
			trauma = 0.5
			kick = 0.9
			punch = 4.0
		HitResult.Outcome.PARRIED:
			color = PARRY_COLOR
			size = 1.8
			trauma = 0.4
			kick = 0.6
			punch = 3.5
	if result.element != SpellData.Element.NONE and result.outcome == HitResult.Outcome.HIT:
		color = SpellData.element_color(result.element)
	if result.reaction == &"shatter":
		color = Color(0.85, 0.55, 1.0)
		size = 2.2
		trauma = 0.6
		kick = 1.0
		punch = 5.0
		SpellFx.shatter(self, at)
	Vfx.impact(self, at, color, size)
	if camera_rig == null or (attacker != focus and defender != focus):
		return
	camera_rig.add_trauma(trauma)
	var push := _push_direction(attacker, defender, at)
	if defender == focus:
		camera_rig.kick(push, kick)  # shoved the way the blow travels
	else:
		camera_rig.kick(push, kick * 0.45)  # a smaller lean into your own hit
	if punch > 0.0:
		camera_rig.fov_punch(punch)


## The way a blow travels: attacker to defender, flattened; spells without a
## living attacker fall back to "away from the impact point".
func _push_direction(attacker: Node, defender: Node, at: Vector3) -> Vector3:
	var to := (defender as Node3D).global_position
	var from := at
	if attacker is Node3D and attacker != defender:
		from = (attacker as Node3D).global_position
	var dir := Vector3(to.x - from.x, 0.0, to.z - from.z)
	return dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
