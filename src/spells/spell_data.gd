class_name SpellData
extends Resource
## Base for gauntlet spells. A cast runs windup -> release -> recovery; at
## release the subclass spawns its effect via release().

enum Element { NONE, FIRE, FROST }

@export var id := &""
@export var display_name := ""
@export var element := Element.NONE
## Spent when the cast starts (primaries).
@export var stamina_cost := 0.0
## Starts when the spell releases (signatures).
@export var cooldown := 0.0

@export_group("Timing")
@export var windup := 0.15
@export var recovery := 0.25

@export_group("Animation")
@export var animation := &"Spellcast_Shoot"
## Second in the clip where the spell leaves the hand.
@export var release_time := 0.35


## Spawns the spell's effect toward `target` (the caster's aim point).
func release(_caster: Fighter, _target: Vector3) -> void:
	pass


static func element_color(element: Element) -> Color:
	match element:
		Element.FIRE:
			return Color(1.0, 0.45, 0.12)
		Element.FROST:
			return Color(0.35, 0.8, 1.0)
	return Color(0.8, 0.8, 0.8)
