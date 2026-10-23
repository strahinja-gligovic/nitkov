class_name MenuShowcase
extends SubViewportContainer
## The start menu's living backdrop: your fighter and the opponent on two
## small stages under the arena's dusk sky. They're real Fighters on the same
## team (so nothing gets hurt), which means picking a spell makes your
## character actually cast it.

const FIGHTER_SCENE := preload("res://src/combat/fighter.tscn")
const PLAYER_HOME := Vector3(-1.05, 0.0, 0.7)
const OPPONENT_HOME := Vector3(1.45, 0.0, -0.7)
const CAMERA_HOME := Vector3(0.05, 1.65, 6.2)
const LOOK_AT := Vector3(-0.2, 1.0, 0.0)

var player: Fighter
var opponent: Fighter

var _viewport: SubViewport
var _world: Node3D
var _camera: Camera3D
var _player_actor := ShowcaseActor.new()
var _opponent_actor := ShowcaseActor.new()
var _time := 0.0


func _ready() -> void:
	stretch = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_2X
	add_child(_viewport)
	_world = Node3D.new()
	_world.name = "Showcase"
	_viewport.add_child(_world)
	ArenaBuilder.add_sky_and_sun(_world)
	_build_stage()
	_camera = Camera3D.new()
	_camera.fov = 52.0
	_world.add_child(_camera)
	_camera.add_child(ToonMaterials.make_ink_pass())
	_camera.current = true
	player = _spawn(MatchConfig.player, PLAYER_HOME, _player_actor, OPPONENT_HOME)
	opponent = _spawn(MatchConfig.bot, OPPONENT_HOME, _opponent_actor, PLAYER_HOME)


## Swap what a display fighter wears or wields.
func show_loadout(for_player: bool, loadout: Loadout) -> void:
	(player if for_player else opponent).apply_loadout(loadout)


## Make a display fighter perform: InputCommand.PRIMARY, SIGNATURE, RUNE, LIGHT...
func perform(for_player: bool, button: int) -> void:
	var actor := _player_actor if for_player else _opponent_actor
	var me := player if for_player else opponent
	var other := opponent if for_player else player
	var across := (other.global_position - me.global_position).normalized()
	var aim := other.chest_position() + across * 8.0  # fly past the other one
	if button == InputCommand.SIGNATURE:
		aim = other.global_position + across * 2.5  # walls rise behind the other one
	actor.press(button, aim)


func _physics_process(_delta: float) -> void:
	# Blink and leaps wander off the stage; once idle again, pop back home.
	for pair in [[player, PLAYER_HOME], [opponent, OPPONENT_HOME]]:
		var fighter: Fighter = pair[0]
		var home: Vector3 = pair[1]
		if fighter == null or not fighter.state.is_actionable() or not fighter.is_on_floor():
			continue
		if fighter.global_position.distance_to(home) > 0.4:
			Vfx.ring(_world, fighter.global_position, Color(0.8, 0.6, 1.0), 1.2, 0.3)
			fighter.global_position = home
			fighter.velocity = Vector3.ZERO
			Vfx.ring(_world, home, Color(0.8, 0.6, 1.0), 1.2, 0.3)


func _process(delta: float) -> void:
	_time += delta
	_camera.position = CAMERA_HOME + Vector3(sin(_time * 0.21) * 0.45, sin(_time * 0.13) * 0.08, 0.0)
	_camera.look_at(LOOK_AT)


func _spawn(loadout: Loadout, home: Vector3, actor: ShowcaseActor, facing_toward: Vector3) -> Fighter:
	var fighter: Fighter = FIGHTER_SCENE.instantiate()
	fighter.team = 0
	fighter.display_name = "Showcase"
	fighter.apply_loadout(loadout)
	# three-quarter view: half toward the camera, half toward the other stage
	var look := ((CAMERA_HOME + facing_toward) * 0.5 - home) * Vector3(1, 0, 1)
	actor.yaw = CombatRules.dir_to_yaw(look)
	fighter.transform = Transform3D(Basis(Vector3.UP, actor.yaw), home)
	fighter.controller = actor
	_world.add_child(fighter)
	return fighter


func _build_stage() -> void:
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(60, 1, 60)
	floor_shape.shape = floor_box
	floor_shape.position.y = -0.5
	floor_body.add_child(floor_shape)
	var floor_mesh := MeshInstance3D.new()
	var plane := BoxMesh.new()
	plane.size = Vector3(60, 1, 60)
	floor_mesh.mesh = plane
	floor_mesh.position.y = -0.5
	floor_mesh.material_override = ToonMaterials.make(Color(0.22, 0.19, 0.27), {&"world_grid": true, &"grid_size": 2.0, &"grunge_strength": 0.4})
	floor_body.add_child(floor_mesh)
	_world.add_child(floor_body)
	for stage in [[PLAYER_HOME, Color(0.1, 0.75, 0.72)], [OPPONENT_HOME, Color(1.0, 0.45, 0.15)]]:
		_add_pedestal(stage[0], stage[1])
	for i in 7:
		var angle := -2.4 + i * 0.8
		var crystal := MeshInstance3D.new()
		var prism := BoxMesh.new()
		prism.size = Vector3(0.7, 2.2 + (i % 3) * 0.8, 0.7)
		crystal.mesh = prism
		crystal.position = Vector3(sin(angle) * 9.0, 1.0, -cos(angle) * 9.0 - 2.0)
		crystal.rotation_degrees = Vector3(0, 45, 10.0 - (i % 2) * 20.0)
		var tint := Color(0.95, 0.3, 0.85) if i % 2 == 0 else Color(0.35, 0.8, 1.0)
		crystal.material_override = ToonMaterials.make(tint, {&"glow_color": tint, &"glow_energy": 1.4})
		_world.add_child(crystal)


func _add_pedestal(at: Vector3, color: Color) -> void:
	var pedestal := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.5
	disc.bottom_radius = 1.7
	disc.height = 0.3
	pedestal.mesh = disc
	pedestal.position = at + Vector3(0, -0.12, 0)
	pedestal.material_override = ToonMaterials.make(Color(0.34, 0.28, 0.4), {&"grunge_strength": 0.35})
	_world.add_child(pedestal)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.55
	torus.outer_radius = 1.68
	ring.mesh = torus
	ring.position = at + Vector3(0, 0.04, 0)
	ring.material_override = ToonMaterials.make_vfx(color, 2.5, false)
	_world.add_child(ring)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 1.2
	light.omni_range = 4.0
	light.position = at + Vector3(0, 0.6, 0)
	_world.add_child(light)
