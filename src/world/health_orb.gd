class_name HealthOrb
extends Node3D
## A health pickup. Touch it while hurt to heal 50% over a second (damage
## interrupts the heal); it reappears 30 seconds later. Pickup is decided in
## the physics tick by distance, so it's deterministic like the rest of the
## simulation.

const COLOR := Color(0.45, 1.0, 0.55)
const PICKUP_RADIUS := 1.1

var available := true
var respawn_left := 0.0

var _tuning: CombatTuning = GameData.tuning
var _orb: Node3D
var _beam: MeshInstance3D
var _time := 0.0


func _ready() -> void:
	_build_visual()


func _physics_process(delta: float) -> void:
	if not available:
		respawn_left -= delta
		if respawn_left <= 0.0:
			available = true
			Vfx.ring(get_parent(), global_position, COLOR, 1.5, 0.35)
		return
	for node in get_tree().get_nodes_in_group(&"fighters"):
		var fighter := node as Fighter
		var s := fighter.state
		if s.is_dead() or s.hp >= s.max_hp:
			continue
		var offset := fighter.global_position - global_position
		if Vector2(offset.x, offset.z).length() <= PICKUP_RADIUS and absf(offset.y) < 1.8:
			available = false
			respawn_left = _tuning.orb_respawn
			CombatRules.start_heal(s, _tuning)
			CombatEvents.orb_taken.emit(fighter)
			Vfx.impact(get_parent(), global_position + Vector3.UP * 1.0, COLOR, 1.8, 0.3, 6.0)
			return


func _process(delta: float) -> void:
	_time += delta
	_orb.visible = available
	_beam.visible = available
	_orb.position.y = 1.0 + sin(_time * 2.4) * 0.15
	_orb.rotation.y = _time * 1.5


func _build_visual() -> void:
	var pedestal := MeshInstance3D.new()
	var base := CylinderMesh.new()
	base.top_radius = 0.6
	base.bottom_radius = 0.75
	base.height = 0.2
	pedestal.mesh = base
	pedestal.position.y = 0.1
	pedestal.material_override = ToonMaterials.make(Color(0.3, 0.26, 0.36), {&"glow_color": COLOR, &"glow_energy": 0.35})
	add_child(pedestal)

	_orb = Node3D.new()
	add_child(_orb)
	var core := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.32
	sphere.height = 0.64
	core.mesh = sphere
	core.material_override = ToonMaterials.make_vfx(COLOR.lightened(0.4), 3.0, false)
	_orb.add_child(core)
	var cross := MeshInstance3D.new()
	var bar := BoxMesh.new()
	bar.size = Vector3(0.75, 0.2, 0.2)
	cross.mesh = bar
	cross.material_override = ToonMaterials.make(Color.WHITE, {&"glow_color": COLOR, &"glow_energy": 1.2})
	_orb.add_child(cross)
	var cross_v := cross.duplicate() as MeshInstance3D
	cross_v.rotation_degrees.z = 90.0
	_orb.add_child(cross_v)
	var light := OmniLight3D.new()
	light.light_color = COLOR
	light.light_energy = 1.4
	light.omni_range = 5.0
	_orb.add_child(light)

	_beam = MeshInstance3D.new()
	var column := CylinderMesh.new()
	column.top_radius = 0.12
	column.bottom_radius = 0.35
	column.height = 7.0
	_beam.mesh = column
	_beam.position.y = 3.5
	var beam_material := ToonMaterials.make_vfx(COLOR, 1.2)
	beam_material.albedo_color.a = 0.18
	_beam.material_override = beam_material
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beam)
