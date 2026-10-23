class_name Autopilot
extends Node
## Command-line verification helper. Arguments after "--":
##   --shots=1.5,3.0   take screenshots at these game-time seconds
##   --out=screenshots folder for screenshots (inside the project)
##   --quit=4.0        quit at this game-time second
##   --drive=walk      replace the player's input with a Scenarios timeline
##   --player_at=0,6   move the player to this x,z first (open ground)
##   --bot_at=2.2      place the bot this far in front of the player
##   --player_yaw=-90  starting facing in degrees (0 = north/-Z, -90 = east)
##   --player_gauntlet=frost / --bot_gauntlet=fire   starting gauntlets
##   --player_rune=blink / --bot_rune=leap           starting runes
##   --player_hp=40    start the player hurt
##   --menu            open the loadout menu at start
##   --bot_mode=4 --bot_skill=0.7   bot behaviour (BotBrain.Mode) and difficulty
##   --autotest=120    bot vs bot for this many seconds, then print stats and quit
##   --player_skill=0.5  the player-side bot's difficulty in an autotest
##   --spectate        view the duel from the side instead of over the shoulder
##   --log             print every resolved hit
## Example: godot --path . --fixed-fps 60 -- --drive=walk --shots=1.5 --quit=2

var shots: Array[float] = []
var out_dir := "res://screenshots"
var quit_at := -1.0
var time := 0.0
var args := {}


static func from_args() -> Autopilot:
	var parsed := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			var parts := arg.substr(2).split("=", true, 1)
			parsed[parts[0]] = parts[1] if parts.size() > 1 else ""
	if parsed.is_empty():
		return null
	var pilot := Autopilot.new()
	pilot.name = "Autopilot"
	pilot.args = parsed
	if parsed.has("shots"):
		for value in String(parsed["shots"]).split(",", false):
			pilot.shots.append(value.to_float())
		pilot.shots.sort()
	if parsed.has("out"):
		pilot.out_dir = "res://" + String(parsed["out"])
	if parsed.has("quit"):
		pilot.quit_at = String(parsed["quit"]).to_float()
	return pilot


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	if args.has("log"):
		CombatEvents.hit_resolved.connect(_log_hit)
		CombatEvents.fighter_respawned.connect(func(f: Node) -> void: print("[%6.2f] %s respawned" % [time, _name(f)]))
		CombatEvents.orb_taken.connect(func(f: Node) -> void: print("[%6.2f] %s took an orb (hp %.0f)" % [time, _name(f), (f as Fighter).state.hp]))
		CombatEvents.status_damage.connect(func(f: Node, amount: float, _e: int) -> void:
			print("[%6.2f] %s burns for %.1f (hp %.0f)" % [time, _name(f), amount, (f as Fighter).state.hp]))
		CombatEvents.fighter_died.connect(func(f: Node, k: Node) -> void: print("[%6.2f] %s killed %s" % [time, _name(k), _name(f)]))


## Counts what happens in a bot-vs-bot run and prints a summary at the end.
## Two TTKs per kill: wall-clock (first damage since spawning -> death, which
## includes retreats and orb runs) and time under fire (only the stretches
## where damage kept coming, each gap capped at 1s), the spec's "4-6s of
## sustained hits".
var _stats := {}
var _engaged := {}
var _under_fire := {}
var _last_damage := {}
var _ttks: Array[float] = []
var _fire_ttks: Array[float] = []
var _kills := {}


func start_autotest(seconds: float) -> void:
	quit_at = seconds
	CombatEvents.hit_resolved.connect(func(_a: Node, d: Node, r: HitResult, _p: Vector3) -> void:
		var key: String = HitResult.Outcome.keys()[r.outcome]
		if r.reaction != &"":
			_count(String(r.reaction))
		if not r.periodic:
			_count(key)
			_count("%s:%s" % [key, r.source])
		if r.damage > 0.0:
			_note_damage(d))
	CombatEvents.status_damage.connect(func(f: Node, _amount: float, _e: int) -> void: _note_damage(f))
	CombatEvents.fighter_died.connect(func(f: Node, killer: Node) -> void:
		if _engaged.has(f):
			_ttks.append(time - float(_engaged[f]))
			_fire_ttks.append(float(_under_fire[f]))
		_forget(f)
		var name := _name(killer)
		_kills[name] = _kills.get(name, 0) + 1)
	CombatEvents.fighter_respawned.connect(_forget)
	CombatEvents.orb_taken.connect(func(_f: Node) -> void: _count("orb"))
	CombatEvents.spell_cast.connect(func(_f: Node, spell: Resource) -> void: _count("cast:%s" % (spell as SpellData).id))


func _note_damage(fighter: Node) -> void:
	if not _engaged.has(fighter):
		_engaged[fighter] = time
		_under_fire[fighter] = 0.0
	else:
		_under_fire[fighter] += minf(time - float(_last_damage[fighter]), 1.0)
	_last_damage[fighter] = time


func _forget(fighter: Node) -> void:
	_engaged.erase(fighter)
	_under_fire.erase(fighter)
	_last_damage.erase(fighter)


func _count(key: String) -> void:
	_stats[key] = _stats.get(key, 0) + 1


func _print_autotest_summary() -> void:
	print("=== autotest: %.0fs of bot-vs-bot ===" % time)
	print("kills: ", _kills)
	_print_spread("TTK, first damage -> death", _ttks)
	_print_spread("TTK, time under fire", _fire_ttks)
	var keys := _stats.keys()
	keys.sort()
	for key in keys:
		print("  %-28s %d" % [key, _stats[key]])


static func _print_spread(label: String, values: Array[float]) -> void:
	if values.is_empty():
		return
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for value in sorted:
		total += value
	print("%s: avg %.1fs, median %.1fs, min %.1fs, max %.1fs over %d kills" % [
			label, total / sorted.size(), sorted[sorted.size() / 2], sorted[0], sorted[-1], sorted.size()])


func _log_hit(attacker: Node, defender: Node, result: HitResult, _at: Vector3) -> void:
	var outcome: String = HitResult.Outcome.keys()[result.outcome]
	var extra := " +%s" % result.reaction if result.reaction != &"" else ""
	print("[%6.2f] %s -> %s: %s %s %.1f dmg%s (hp %.0f)" % [time, _name(attacker), _name(defender),
			outcome, result.source, result.damage, extra, (defender as Fighter).state.hp])


static func _name(node: Node) -> String:
	return (node as Fighter).display_name if node is Fighter else "world"


## A side-on camera framing two fighters, for checking animation timing.
func spectate(a: Node3D, b: Node3D) -> void:
	var camera := Camera3D.new()
	camera.name = "SpectatorCamera"
	camera.fov = 50.0
	add_child(camera)
	camera.add_child(ToonMaterials.make_ink_pass())
	var mid := (a.global_position + b.global_position) * 0.5
	var across := (b.global_position - a.global_position).cross(Vector3.UP).normalized()
	camera.global_position = mid + across * 6.0 + Vector3.UP * 1.6
	camera.look_at(mid + Vector3.UP * 0.9)
	camera.current = true


func _process(delta: float) -> void:
	time += delta
	while not shots.is_empty() and time >= shots[0]:
		var at: float = shots.pop_front()
		_capture("shot_%05.2f.png" % at)
	if quit_at >= 0.0 and time >= quit_at:
		if args.has("autotest"):
			_print_autotest_summary()
		get_tree().quit()


func _capture(file_name: String) -> void:
	var image := get_viewport().get_texture().get_image()
	if image == null:
		push_warning("Autopilot: no frame to capture (headless?)")
		return
	var path := ProjectSettings.globalize_path(out_dir.path_join(file_name))
	image.save_png(path)
	print("Autopilot: saved ", path)
