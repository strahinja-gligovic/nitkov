class_name Autopilot
extends Node
## Command-line verification helper. Arguments after "--":
##   --shots=1.5,3.0   take screenshots at these game-time seconds
##   --out=screenshots folder for screenshots (inside the project)
##   --quit=4.0        quit at this game-time second
##   --drive=walk      replace the player's input with a Scenarios timeline
##   --player_at=0,6   move the player to this x,z first (open ground)
##   --bot_at=2.2      place the bot this far in front of the player
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
		CombatEvents.status_damage.connect(func(f: Node, amount: float, _e: int) -> void:
			print("[%6.2f] %s burns for %.1f (hp %.0f)" % [time, _name(f), amount, (f as Fighter).state.hp]))
		CombatEvents.fighter_died.connect(func(f: Node, k: Node) -> void: print("[%6.2f] %s killed %s" % [time, _name(k), _name(f)]))


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
		get_tree().quit()


func _capture(file_name: String) -> void:
	var image := get_viewport().get_texture().get_image()
	if image == null:
		push_warning("Autopilot: no frame to capture (headless?)")
		return
	var path := ProjectSettings.globalize_path(out_dir.path_join(file_name))
	image.save_png(path)
	print("Autopilot: saved ", path)
