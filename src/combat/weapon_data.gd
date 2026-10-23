class_name WeaponData
extends Resource
## A melee weapon: its light chain and its heavy.

@export var id := &"longsword"
@export var display_name := "Longsword"
## Played in order; after the last one the chain wraps to the first.
@export var light_chain: Array[AttackData] = []
@export var heavy: AttackData
