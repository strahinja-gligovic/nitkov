class_name Scenarios
extends RefCounted
## Named input timelines for ScriptedController, used by the Autopilot's
## --drive=<name> argument to exercise features in automated runs.

const L := InputCommand.LIGHT
const H := InputCommand.HEAVY
const B := InputCommand.BLOCK
const D := InputCommand.DASH
const S := InputCommand.SPRINT
const P := InputCommand.PRIMARY
const G := InputCommand.SIGNATURE
const R := InputCommand.RUNE


static func get_timeline(scenario: String) -> Array:
	match scenario:
		"walk":
			return [
				{"at": 0.3, "for": 1.0, "move": Vector2(0, 1)},
				{"at": 1.3, "for": 1.0, "move": Vector2(0, 1), "hold": S},
				{"at": 2.3, "for": 1.2, "move": Vector2(1, 0), "turn": 1.2},
			]
		"melee":
			# light chain into a heavy against a target ~2m ahead (--bot_at=2.2)
			return [
				{"at": 0.3, "press": L},
				{"at": 0.75, "press": L},
				{"at": 1.15, "press": L},
				{"at": 2.2, "press": H},
			]
	push_warning("Scenarios: unknown scenario '%s'" % scenario)
	return []
