extends Node
## Choices made in the start menu (autoload "MatchConfig"). The arena reads
## them when a match loads; running the arena scene directly uses these defaults.

var player := Loadout.make(&"knight", &"firebolt", &"flame_wall", &"leap")
var bot := Loadout.make(&"barbarian", &"shard_volley", &"frost_nova", &"blink")
var bot_mode := BotBrain.Mode.DUELIST
var bot_difficulty := 0.5
