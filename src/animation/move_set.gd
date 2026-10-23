class_name MoveSet
extends Resource
## Every move a fighter can show, by id: swings, casts, reactions, dashes,
## jumps and the locomotion loops. Gameplay data names moves by id
## (AttackData.animation, SpellData.animation); FighterVisual looks them up.

@export var moves: Dictionary[StringName, AnimMove] = {}


func get_move(id: StringName) -> AnimMove:
	return moves.get(id)


func has_move(id: StringName) -> bool:
	return moves.has(id)
