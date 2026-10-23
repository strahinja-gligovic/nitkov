class_name Loadout
extends Resource
## What a fighter brings into a match: a character, any primary spell, any
## signature spell and a mobility rune (mix and match across elements).

@export var character := &"knight"
@export var primary := &"firebolt"
@export var signature := &"flame_wall"
@export var rune := &"leap"


static func make(character_id: StringName, primary_id: StringName, signature_id: StringName, rune_id: StringName) -> Loadout:
	var loadout := Loadout.new()
	loadout.character = character_id
	loadout.primary = primary_id
	loadout.signature = signature_id
	loadout.rune = rune_id
	return loadout
