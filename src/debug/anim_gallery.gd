class_name AnimGallery
extends Node3D
## A row of fighters that each show one move side by side, to compare
## animation candidates through the real pipeline (simulation timing,
## TimeRemap, layers, the character and its sword). Every fighter casts the
## same spell at the same moment, but its own copy of the spell plays its own
## move; one fixed camera frames the row. The arena's player and bot are
## parked out of the way. Debug only (Autopilot: --gallery=<moves>).
##   --gallery=cast_a,cast_b    the moves, one fighter each ("-" = the spell's own move)
##   --gallery_spell=ice_spike  the spell they cast (a primary or a signature)
##   --gallery_angle=90         view: 0 = from their right (sword side), 90 = front,
##                              180 = left (gauntlet side), 270 = behind
##   --gallery_at=0.5           when they press cast (game seconds)
##   --gallery_walk=0,1         walk this way while casting (right, forward; 1 = full speed)
##   --gallery_leap=0.3         leap at this time first, to cast in the air
##   --gallery_character=warden who casts ("all" = each character in turn)
##   --gallery_zoom=1.0         >1 frames the row tighter
##   --gallery_spacing=1.8      metres between fighters
##   --gallery_fov=30           camera field of view (narrower = flatter, but further back)
##   --gallery_turns=0,90       turn each fighter this many degrees left (cycled), to see
##                              one move from several sides in the same frame
##   --gallery_replace=stagger_shock  show each fighter's move in place of this one
##                              instead of as the spell's (any move: reactions, leaps...)
##   --gallery_strike=0.3       call a Lightning Strike (from the parked bot) on the row at
##                              this time: it lands 0.9 s later and stuns everyone within
##                              2.5 m of the row's centre (keep the row that narrow)

const FIGHTER_SCENE := preload("res://src/combat/fighter.tscn")
## Every gallery row faces north (-Z) from the arena's open centre.
const CENTRE := Vector3(0.0, 0.0, 2.0)

var args := {}
var fighters: Array[Fighter] = []
var camera: Camera3D

var _view := Vector3.RIGHT
var _height := 3.6
var _time := 0.0
var _strike_at := -1.0


func _ready() -> void:
	var moves := String(args.get("gallery", "-")).split(",", false)
	var spell_id := StringName(args.get("gallery_spell", "firebolt"))
	var spell: SpellData = GameData.spells.get(spell_id)
	if spell == null:
		push_warning("AnimGallery: unknown spell %s" % spell_id)
		return
	var spacing := String(args.get("gallery_spacing", "1.8")).to_float()
	var angle := deg_to_rad(String(args.get("gallery_angle", "90")).to_float())
	_park_the_others()

	# a fighter facing -Z has +X on its right; the camera sits `angle` around from there
	_view = Vector3.RIGHT.rotated(Vector3.UP, angle)
	var across := _view.rotated(Vector3.UP, PI * 0.5)
	var characters: Array = GameData.characters.keys()
	var who := String(args.get("gallery_character", "warden"))
	var turns := String(args.get("gallery_turns", "0")).split(",", false)
	for i in moves.size():
		var at := CENTRE + across * (i - (moves.size() - 1) * 0.5) * spacing
		var character := StringName(characters[i % characters.size()] if who == "all" else who)
		var yaw := deg_to_rad(turns[i % turns.size()].to_float())
		fighters.append(_spawn(at, yaw, character, spell, StringName(moves[i]) if moves[i] != "-" else spell.animation))

	camera = Camera3D.new()
	camera.name = "GalleryCamera"
	camera.fov = String(args.get("gallery_fov", "30")).to_float()
	add_child(camera)
	camera.add_child(ToonMaterials.make_ink_pass())
	var width := moves.size() * spacing + 0.6
	_height = maxf(3.0, width / (16.0 / 9.0)) / String(args.get("gallery_zoom", "1.0")).to_float()
	camera.current = true
	_frame()
	_strike_at = String(args.get("gallery_strike", "-1")).to_float()


func _process(_delta: float) -> void:
	if camera:
		_frame()


func _physics_process(delta: float) -> void:
	_time += delta
	if _strike_at >= 0.0 and _time >= _strike_at:
		_strike_at = -1.0
		_call_strikes()


## A Lightning Strike on the middle of the row, cast by the parked bot (the
## only fighter on the other team), so the fighters take the real stun.
func _call_strikes() -> void:
	var caster: Fighter = null
	for node in get_tree().get_nodes_in_group(&"fighters"):
		if (node as Fighter).team != 0:
			caster = node as Fighter
	var spell := GameData.spells.get(&"lightning_strike") as LightningStrikeSpell
	if caster == null or spell == null:
		return
	var centre := Vector3.ZERO
	for fighter in fighters:
		centre += fighter.global_position / fighters.size()
	var strike := LightningStrike.new()
	strike.setup(caster, spell, centre)
	get_parent().add_child(strike)


## Keeps the row centred, the camera standing back far enough to see
## `_height` metres (a narrow field of view keeps the perspective flat).
func _frame() -> void:
	var centre := Vector3.ZERO
	var count := 0
	for fighter in fighters:
		if is_instance_valid(fighter):
			centre += fighter.global_position
			count += 1
	if count == 0:
		return
	centre /= count
	var distance := _height * 0.5 / tan(deg_to_rad(camera.fov * 0.5))
	var look := centre + Vector3.UP * 1.05
	camera.global_position = look + _view * distance + Vector3.UP * distance * 0.06
	camera.look_at(look)


func _spawn(at: Vector3, yaw: float, character: StringName, spell: SpellData, move: StringName) -> Fighter:
	var fighter: Fighter = FIGHTER_SCENE.instantiate()
	fighter.team = 0
	fighter.display_name = String(move)
	var primary := spell.id if spell.slot == SpellData.Slot.PRIMARY else &"firebolt"
	var signature := spell.id if spell.slot == SpellData.Slot.SIGNATURE else &"flame_wall"
	fighter.apply_loadout(Loadout.make(character, primary, signature, &"leap"))
	var replace := StringName(args.get("gallery_replace", ""))
	if replace == &"":
		var own := spell.duplicate() as SpellData
		own.animation = move
		if spell.slot == SpellData.Slot.PRIMARY:
			fighter.primary = own
		else:
			fighter.signature = own
	fighter.name = "Gallery%d" % fighters.size()
	fighter.position = at
	fighter.rotation.y = yaw
	get_parent().add_child(fighter)
	var visual := fighter.get_node_or_null(^"Visual") as FighterVisual
	if replace != &"" and visual and visual.director:
		visual.director.stand_ins[replace] = move
	fighter.controller = GalleryPilot.new(args, spell.slot == SpellData.Slot.SIGNATURE, yaw)
	var label := Label3D.new()
	label.text = String(move)
	label.font_size = 40
	label.pixel_size = 0.004
	label.outline_size = 10
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3(0.0, 2.25, 0.0)
	fighter.add_child(label)
	return fighter


## The arena's own fighters stand idle behind the row, unseen.
func _park_the_others() -> void:
	var spot := 0
	for node in get_tree().get_nodes_in_group(&"fighters"):
		var fighter := node as Fighter
		fighter.controller = null
		fighter.global_position = CENTRE + Vector3(-3.0 + spot * 6.0, 0.0, 17.0)
		spot += 1
		var visual := fighter.get_node_or_null(^"Visual") as Node3D
		if visual:
			visual.visible = false


## Faces its yaw and presses cast on cue; optionally walks (relative to its
## facing) or leaps first.
class GalleryPilot:
	var time := 0.0
	var press_at := 0.5
	var leap_at := -1.0
	var walk := Vector2.ZERO
	var button := InputCommand.PRIMARY
	var yaw := 0.0

	func _init(args: Dictionary, signature: bool, facing: float) -> void:
		yaw = facing
		press_at = String(args.get("gallery_at", "0.5")).to_float()
		leap_at = String(args.get("gallery_leap", "-1")).to_float()
		if args.has("gallery_walk"):
			var parts := String(args["gallery_walk"]).split(",")
			walk = Vector2(parts[0].to_float(), parts[1].to_float() if parts.size() > 1 else 0.0)
		button = InputCommand.SIGNATURE if signature else InputCommand.PRIMARY

	func get_command(fighter: Fighter) -> InputCommand:
		var dt := fighter.get_physics_process_delta_time()
		var cmd := InputCommand.new()
		cmd.aim_yaw = yaw
		cmd.aim_target = fighter.global_position + Vector3.UP * 1.3 + CombatRules.yaw_to_dir(yaw) * 12.0
		if time < press_at and time + dt >= press_at:
			cmd.pressed |= button
		if leap_at >= 0.0 and time < leap_at and time + dt >= leap_at:
			cmd.pressed |= InputCommand.RUNE
		# walk from a little before the cast until well after it
		if walk != Vector2.ZERO and time >= press_at - 0.6:
			var world := Basis(Vector3.UP, yaw) * Vector3(walk.x, 0.0, -walk.y)
			cmd.move = Vector2(world.x, world.z).limit_length(1.0)
		time += dt
		return cmd
