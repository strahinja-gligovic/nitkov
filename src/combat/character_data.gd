class_name CharacterData
extends Resource
## A playable character: a clothed body on the shared 65-bone humanoid rig,
## the head cut from a matching base body, hair, and where the longsword and
## the gauntlet's orb sit in the hands. CharacterRig assembles it.

@export var id := &"warden"
@export var display_name := "Warden"
@export_multiline var blurb := ""
## The outfit: a headless, clothed body (Quaternius Modular Outfits).
@export var outfit: PackedScene
## The base body the head (face, eyes, brows) is cut from, and the name of
## its body mesh.
@export var head_from: PackedScene
@export var head_mesh := ""
## Open collars get a fill around the neck so a deep duck never shows a hollow.
@export var collar_fill := false
## Female proportions (the collar fill's shape and the grip differ slightly).
@export var female := false
## Hair and beards, skinned to the same rig (bound to the matching body type).
@export var hair: Array[PackedScene] = []
## Hair and brow color (their textures are greyscale).
@export var hair_color := Color(0.22, 0.15, 0.1)
## The longsword's grip centre in the right fist, in hand_r space.
@export var grip := Vector3(-0.029, 0.095, -0.004)
## The gauntlet orb's spot in front of the left knuckles, in hand_l space.
@export var orb_anchor := Vector3(0.008, 0.177, -0.006)
