extends Node
## Loads the shared game data (autoload "GameData"). The tuning panel edits
## these same instances, so changes take effect immediately everywhere.

const TUNING_PATH := "res://data/combat_tuning.tres"
const MOVES_PATH := "res://data/moves/humanoid.tres"
const WEAPON_PATHS: Array[String] = ["res://data/weapons/longsword.tres"]
const SPELL_PATHS: Array[String] = [
	"res://data/spells/firebolt.tres", "res://data/spells/ice_spike.tres",
	"res://data/spells/lightning_bolt.tres", "res://data/spells/wind_slash.tres",
	"res://data/spells/flame_wall.tres", "res://data/spells/frost_nova.tres",
	"res://data/spells/lightning_strike.tres", "res://data/spells/wind_spear.tres",
]
const RUNE_PATHS: Array[String] = ["res://data/runes/leap.tres", "res://data/runes/blink.tres"]
const CHARACTER_PATHS: Array[String] = [
	"res://data/characters/warden.tres", "res://data/characters/huntress.tres",
	"res://data/characters/brawler.tres", "res://data/characters/tavernkeep.tres",
]

var tuning: CombatTuning
## How every move looks (presentation only).
var moves: MoveSet
## id -> WeaponData
var weapons := {}
## id -> SpellData (primaries and signatures, every element)
var spells := {}
## id -> RuneData
var runes := {}
## id -> CharacterData
var characters := {}


func _ready() -> void:
	tuning = load(TUNING_PATH)
	moves = load(MOVES_PATH)
	for path in WEAPON_PATHS:
		var weapon: WeaponData = load(path)
		weapons[weapon.id] = weapon
	for path in SPELL_PATHS:
		var spell: SpellData = load(path)
		spells[spell.id] = spell
	for path in RUNE_PATHS:
		var rune: RuneData = load(path)
		runes[rune.id] = rune
	for path in CHARACTER_PATHS:
		var character: CharacterData = load(path)
		characters[character.id] = character


## Every spell that fits a slot, in load order.
func spells_for(slot: SpellData.Slot) -> Array[SpellData]:
	var out: Array[SpellData] = []
	for spell: SpellData in spells.values():
		if spell.slot == slot:
			out.append(spell)
	return out
