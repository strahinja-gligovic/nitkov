class_name FlameWall
extends Node3D
## A line of burning ground. Every tick_interval it burns enemies standing in
## it (unblockable Fire hits that can set off Shatter), then dies out.

const FLAME := preload("res://src/vfx/flame.gdshader")

var caster: Fighter
var spell: FlameWallSpell
var team := 0

var _centre := Vector3.ZERO
## Unit vector along the wall's length; the wall faces _facing.
var _axis := Vector3.RIGHT
var _facing := Vector3.FORWARD
var _age := 0.0
var _tick := 0.0
var _flames: Array[ShaderMaterial] = []
var _tuning: CombatTuning


func setup(from: Fighter, data: FlameWallSpell, centre: Vector3, facing: Vector3) -> void:
	caster = from
	spell = data
	team = from.team
	_centre = centre
	_facing = facing
	_axis = facing.cross(Vector3.UP).normalized()
	_tuning = from.tuning


func _ready() -> void:
	global_position = _centre
	look_at(_centre + _facing, Vector3.UP)
	_build_visual()


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= spell.duration:
		queue_free()
		return
	_tick += delta
	while _tick >= spell.tick_interval:
		_tick -= spell.tick_interval
		_burn_occupants()
	var intensity := clampf(_age / 0.2, 0.0, 1.0) * clampf((spell.duration - _age) / 0.4, 0.0, 1.0)
	for material in _flames:
		material.set_shader_parameter(&"intensity", intensity)


func contains(point: Vector3, margin := 0.0) -> bool:
	var local := point - _centre
	return absf(local.dot(_axis)) <= spell.length * 0.5 + margin \
			and absf(local.dot(_facing)) <= spell.width * 0.5 + margin \
			and local.y > -1.0 and local.y < spell.height


func _burn_occupants() -> void:
	for node in get_tree().get_nodes_in_group(&"fighters"):
		var fighter := node as Fighter
		if fighter.team == team or fighter.state.is_dead() or not contains(fighter.global_position, Fighter.RADIUS):
			continue
		var hit := SpellHit.new()
		hit.element = SpellData.Element.FIRE
		hit.source = spell.id
		hit.damage = spell.damage_per_second * spell.tick_interval
		hit.blockable = false
		hit.periodic = true
		var result := CombatRules.resolve_spell(fighter.state, hit, false, _tuning)
		Fighter.report_hit(caster, fighter, result, fighter.chest_position())


func _build_visual() -> void:
	var embers := MeshInstance3D.new()
	var strip := BoxMesh.new()
	strip.size = Vector3(spell.length, 0.08, spell.width)
	embers.mesh = strip
	embers.position = Vector3(0.0, 0.04, 0.0)
	embers.material_override = ToonMaterials.make_vfx(Color(1.0, 0.3, 0.08), 2.5, false)
	add_child(embers)
	var tongues := int(spell.length / 0.55)
	for i in tongues:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.38
		cone.height = spell.height
		cone.radial_segments = 8
		cone.rings = 6
		var material := ShaderMaterial.new()
		material.shader = FLAME
		material.set_shader_parameter(&"flame_height", spell.height)
		material.set_shader_parameter(&"seed", randf() * 10.0)
		material.set_shader_parameter(&"intensity", 0.0)
		_flames.append(material)
		var flame := MeshInstance3D.new()
		flame.mesh = cone
		flame.material_override = material
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var along := (float(i) + 0.5) / tongues - 0.5
		flame.position = Vector3(along * spell.length, spell.height * 0.5 * randf_range(0.75, 1.0),
				randf_range(-0.2, 0.2) * spell.width)
		flame.scale = Vector3.ONE * randf_range(0.8, 1.15)
		add_child(flame)
	for i in 3:
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.5, 0.15)
		light.light_energy = 1.4
		light.omni_range = 5.0
		light.position = Vector3((i - 1) * spell.length * 0.33, 1.0, 0.0)
		add_child(light)
