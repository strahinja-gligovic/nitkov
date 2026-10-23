class_name RuneData
extends Resource
## A mobility rune: one movement ability on its own cooldown, independent of
## your spells. Subclasses implement activate().

@export var id := &""
@export var display_name := ""
@export_multiline var description := ""
@export var cooldown := 10.0
## Whether it can be used while airborne.
@export var air_use := false


func activate(_fighter: Fighter, _cmd: InputCommand) -> void:
	pass
