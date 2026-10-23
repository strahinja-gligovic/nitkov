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
##   --player_primary=ice_spike / --player_signature=frost_nova / --player_rune=blink
##   --player_character=mage  (and the same with bot_ for the bot)
##   --player_hp=40    start the player hurt
##   --slowmo=0.25     run the game at this speed (shots and quit stay in game time)
##   --menu            open the loadout menu at start
##   --hitboxes / --combat_log / --tuning   start with that debug view open
##   --bot_mode=4 --bot_skill=0.7   bot behaviour (BotBrain.Mode) and difficulty
##   --autotest=120    bot vs bot for this many seconds, then print stats and quit
##   --player_skill=0.5  the player-side bot's difficulty in an autotest
##   --spectate        view the duel from the side instead of over the shoulder
##   --spectate=3.5 --spectate_angle=40   ...from this many metres, turned this many degrees
##   --spectate_on=player|bot              ...centred on one fighter instead of between them
##   --log             print every resolved hit
##   --perf            print frame-time stats when quitting
##   --probe           log every fighter's state, sword tip and feet each frame to screenshots/probe.csv
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
	if args.has("probe"):
		process_priority = 1000  # sample poses after every visual has updated this frame
		_probe = FileAccess.open(out_dir.path_join("probe.csv"), FileAccess.WRITE)
		_probe.store_line("t,name,action,action_time,hitstop,px,py,pz,vx,vz,yaw,tipx,tipy,tipz,blx,bly,blz,brx,bry,brz")
		CombatEvents.hit_resolved.connect(func(a: Node, d: Node, r: HitResult, _p: Vector3) -> void:
			_probe.store_line("%.4f,HIT,%s,%s,%s,%s" % [time, _name(a), _name(d), HitResult.Outcome.keys()[r.outcome], r.source]))
	if args.has("log"):
		CombatEvents.hit_resolved.connect(_log_hit)
		CombatEvents.fighter_respawned.connect(func(f: Node) -> void: print("[%6.2f] %s respawned" % [time, _name(f)]))
		CombatEvents.orb_taken.connect(func(f: Node) -> void: print("[%6.2f] %s took an orb (hp %.0f)" % [time, _name(f), (f as Fighter).state.hp]))
		CombatEvents.status_damage.connect(func(f: Node, amount: float, _e: int) -> void:
			print("[%6.2f] %s burns for %.1f (hp %.0f)" % [time, _name(f), amount, (f as Fighter).state.hp]))
		CombatEvents.fighter_died.connect(func(f: Node, k: Node) -> void: print("[%6.2f] %s killed %s" % [time, _name(k), _name(f)]))


## Counts what happens in a bot-vs-bot run and prints a summary at the end
## (TTK numbers come from TtkTracker).
var _stats := {}
var _kills := {}
var _ttk: TtkTracker


func start_autotest(seconds: float) -> void:
	quit_at = seconds
	_ttk = TtkTracker.new()
	add_child(_ttk)
	CombatEvents.hit_resolved.connect(func(_a: Node, _d: Node, r: HitResult, _p: Vector3) -> void:
		var key: String = HitResult.Outcome.keys()[r.outcome]
		if r.reaction != &"":
			_count(String(r.reaction))
		if not r.periodic:
			_count(key)
			_count("%s:%s" % [key, r.source]))
	CombatEvents.fighter_died.connect(func(_f: Node, killer: Node) -> void:
		var name := _name(killer)
		_kills[name] = _kills.get(name, 0) + 1)
	CombatEvents.orb_taken.connect(func(_f: Node) -> void: _count("orb"))
	CombatEvents.spell_cast.connect(func(_f: Node, spell: Resource) -> void: _count("cast:%s" % (spell as SpellData).id))


func _count(key: String) -> void:
	_stats[key] = _stats.get(key, 0) + 1


func _print_autotest_summary() -> void:
	print("=== autotest: %.0fs of bot-vs-bot ===" % time)
	print("kills: ", _kills)
	print(TtkTracker.summary("TTK, first damage -> death", _ttk.wall_clock))
	print(TtkTracker.summary("TTK, time under fire", _ttk.under_fire))
	var keys := _stats.keys()
	keys.sort()
	for key in keys:
		print("  %-28s %d" % [key, _stats[key]])


func _log_hit(attacker: Node, defender: Node, result: HitResult, _at: Vector3) -> void:
	var outcome: String = HitResult.Outcome.keys()[result.outcome]
	var extra := " +%s" % result.reaction if result.reaction != &"" else ""
	print("[%6.2f] %s -> %s: %s %s %.1f dmg%s (hp %.0f)" % [time, _name(attacker), _name(defender),
			outcome, result.source, result.damage, extra, (defender as Fighter).state.hp])


static func _name(node: Node) -> String:
	return (node as Fighter).display_name if node is Fighter else "world"


var _spectator: Camera3D
var _spectated: Node3D
var _spectator_offset := Vector3.ZERO


## A side-on camera framing two fighters, for checking animation timing.
## `angle` turns it around them (degrees; + toward the first fighter's front).
## With a `focus`, it frames that fighter and follows it.
func spectate(a: Node3D, b: Node3D, distance := 6.0, angle := 0.0, focus: Node3D = null) -> void:
	var camera := Camera3D.new()
	camera.name = "SpectatorCamera"
	camera.fov = 50.0
	add_child(camera)
	camera.add_child(ToonMaterials.make_ink_pass())
	var mid := (a.global_position + b.global_position) * 0.5 if focus == null else focus.global_position
	var across := (b.global_position - a.global_position).cross(Vector3.UP).normalized()
	across = across.rotated(Vector3.UP, deg_to_rad(angle))
	camera.global_position = mid + across * distance + Vector3.UP * 1.6
	camera.look_at(mid + Vector3.UP * 0.9)
	camera.current = true
	if focus:
		_spectator = camera
		_spectated = focus
		_spectator_offset = camera.global_position - focus.global_position


var _next_trace := 0.0
var _probe: FileAccess


func _write_probe() -> void:
	for node in get_tree().get_nodes_in_group(&"fighters"):
		var f := node as Fighter
		var visual := f.get_node_or_null(^"Visual") as FighterVisual
		if visual == null or visual.rig == null:
			continue
		var tip := visual.drawn_tip
		var feet := visual.drawn_feet
		var s := f.state
		var at := visual.global_position
		_probe.store_line("%.4f,%s,%s,%.4f,%.3f,%.4f,%.4f,%.4f,%.3f,%.3f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f" % [
				time, _name(f), FighterState.Action.keys()[s.action], s.action_time, s.hitstop, at.x, at.y, at.z,
				f.velocity.x, f.velocity.z, s.facing_yaw, tip.x, tip.y, tip.z,
				feet[0].x, feet[0].y, feet[0].z, feet[1].x, feet[1].y, feet[1].z])
var _frame_times: Array[float] = []


func _print_perf() -> void:
	if _frame_times.is_empty():
		return
	var sorted := _frame_times.duplicate()
	sorted.sort()
	var total := 0.0
	for t in sorted:
		total += t
	print("perf: %d frames, avg %.2f ms (%.0f fps), p95 %.2f ms, worst %.2f ms, process %.2f ms, physics %.2f ms" % [
			sorted.size(), total / sorted.size() * 1000.0, sorted.size() / total, sorted[int(sorted.size() * 0.95)] * 1000.0,
			sorted[sorted.size() - 1] * 1000.0, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0])


## --trace: print every fighter's action state four times a second.
func _trace() -> void:
	if not args.has("trace") or time < _next_trace:
		return
	_next_trace = time + 0.25
	for node in get_tree().get_nodes_in_group(&"fighters"):
		var f := node as Fighter
		var s := f.state
		print("[%6.2f] %-4s %-7s t=%.2f atk=%s combo=%d stam=%.0f hp=%.0f pos=(%.1f,%.1f) buf=%s" % [time, f.display_name,
				FighterState.Action.keys()[s.action], s.action_time, s.attack.id if s.attack else "-", s.combo_index,
				s.stamina, s.hp, f.global_position.x, f.global_position.z, s.buffer.keys()])


func _process(delta: float) -> void:
	time += delta
	_trace()
	if _spectator and is_instance_valid(_spectated):
		_spectator.global_position = _spectated.global_position + _spectator_offset
	while not shots.is_empty() and time >= shots[0]:
		var at: float = shots.pop_front()
		_capture("shot_%05.2f.png" % at)
	if _probe:
		_write_probe()
	if args.has("perf") and time > 1.0:
		_frame_times.append(delta)
	if quit_at >= 0.0 and time >= quit_at:
		if args.has("autotest"):
			_print_autotest_summary()
		if args.has("perf"):
			_print_perf()
		get_tree().quit()


func _capture(file_name: String) -> void:
	var image := get_viewport().get_texture().get_image()
	if image == null:
		push_warning("Autopilot: no frame to capture (headless?)")
		return
	var path := ProjectSettings.globalize_path(out_dir.path_join(file_name))
	image.save_png(path)
	print("Autopilot: saved ", path)
