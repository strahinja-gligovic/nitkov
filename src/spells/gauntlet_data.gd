class_name GauntletData
extends Resource
## An elemental gauntlet: a stamina-costing primary and a cooldown signature.

@export var id := &"fire"
@export var display_name := "Fire"
@export var element := SpellData.Element.FIRE
@export var primary: SpellData
@export var signature: SpellData
