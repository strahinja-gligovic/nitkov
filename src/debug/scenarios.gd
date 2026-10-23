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
		"bot_pressure":
			# for the bot: two lights, then two heavies
			return [
				{"at": 0.5, "press": L},
				{"at": 1.3, "press": L},
				{"at": 2.3, "press": H},
				{"at": 4.8, "press": H},
			]
		"guard":
			# for the player vs bot_pressure: block, block, parry the heavy, then
			# block the second heavy (which breaks the guard)
			return [
				{"at": 0.2, "for": 2.0, "hold": B},
				{"at": 2.92, "for": 0.1, "press": B},
				{"at": 3.6, "for": 2.6, "hold": B},
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
