extends Node
## Loads the shared game data (autoload "GameData"). The tuning panel edits
## these same instances, so changes take effect immediately everywhere.

const TUNING_PATH := "res://data/combat_tuning.tres"
const WEAPON_PATHS: Array[String] = ["res://data/weapons/longsword.tres"]
const SPELL_PATHS: Array[String] = [
	"res://data/spells/firebolt.tres", "res://data/spells/shard_volley.tres",
	"res://data/spells/flame_wall.tres", "res://data/spells/frost_nova.tres",
]
const RUNE_PATHS: Array[String] = ["res://data/runes/leap.tres", "res://data/runes/blink.tres"]
const CHARACTER_PATHS: Array[String] = [
	"res://data/characters/knight.tres", "res://data/characters/barbarian.tres",
	"res://data/characters/mage.tres", "res://data/characters/rogue.tres",
	"res://data/characters/rogue_hooded.tres",
]

var tuning: CombatTuning
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
