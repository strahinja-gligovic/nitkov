extends Node
## Loads the shared tuning data (autoload "GameData"). The tuning panel edits
## these same instances, so changes take effect immediately everywhere.

const TUNING_PATH := "res://data/combat_tuning.tres"

var tuning: CombatTuning


func _ready() -> void:
	tuning = load(TUNING_PATH)
