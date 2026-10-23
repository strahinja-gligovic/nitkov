class_name Autopilot
extends Node
## Command-line verification helper. Arguments after "--":
##   --shots=1.5,3.0   take screenshots at these game-time seconds
##   --out=screenshots folder for screenshots (inside the project)
##   --quit=4.0        quit at this game-time second
##   --drive=walk      replace the player's input with a Scenarios timeline
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
