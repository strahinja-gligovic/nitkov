extends Node
## Loads the shared tuning data (autoload "GameData"). The tuning panel edits
## these same instances, so changes take effect immediately everywhere.

const TUNING_PATH := "res://data/combat_tuning.tres"
const WEAPON_PATHS: Array[String] = ["res://data/weapons/longsword.tres"]
const GAUNTLET_PATHS: Array[String] = ["res://data/gauntlets/fire.tres", "res://data/gauntlets/frost.tres"]

var tuning: CombatTuning
## id -> WeaponData
var weapons := {}
## id -> GauntletData
var gauntlets := {}


func _ready() -> void:
	tuning = load(TUNING_PATH)
	for path in WEAPON_PATHS:
		var weapon: WeaponData = load(path)
		weapons[weapon.id] = weapon
	for path in GAUNTLET_PATHS:
		var gauntlet: GauntletData = load(path)
		gauntlets[gauntlet.id] = gauntlet
