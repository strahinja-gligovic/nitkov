class_name CharacterData
extends Resource
## A playable character model and how to dress it for a fight: which props
## to strip, where the longsword comes from, and how to scale it.

@export var id := &"knight"
@export var display_name := "Knight"
@export_multiline var blurb := ""
@export var scene: PackedScene
## Nodes in the model to remove (shields, staves, spare weapons...).
@export var remove_nodes: PackedStringArray = []
## A node in the model to use as the longsword; empty attaches the shared one.
@export var sword_node := ""
## KayKit characters are ~2.35 units tall; 0.78 brings them to ~1.85m.
@export var model_scale := 0.78
