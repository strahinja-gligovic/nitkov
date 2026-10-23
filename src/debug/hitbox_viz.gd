class_name HitboxViz
extends MeshInstance3D
## F2: draws the invisible combat geometry every frame. Swing arcs (yellow
## wind-up, red active, grey recovery), block arcs (blue), parry windows (gold),
## invulnerability (cyan), hurt capsules (white), projectile radii, Flame Wall
## zones and Nova blasts. Drawn on top of everything.

const WINDUP := Color(1.0, 0.9, 0.2)
const ACTIVE := Color(1.0, 0.2, 0.2)
const RECOVERY := Color(0.6, 0.6, 0.6, 0.6)
const GUARD := Color(0.35, 0.65, 1.0)
const PARRY := Color(1.0, 0.8, 0.2)
const INVULN := Color(0.3, 1.0, 1.0)
const BODY := Color(1, 1, 1, 0.5)

var _mesh := ImmediateMesh.new()
var _blasts: Array = []  # [centre, radius, color, seconds left]


func _ready() -> void:
	mesh = _mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.render_priority = 20
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384.0
	visible = false
	CombatEvents.spell_cast.connect(_on_spell_cast)


func _on_spell_cast(fighter: Node, spell: Resource) -> void:
	if spell is NovaSpell:
		_blasts.append([(fighter as Fighter).global_position, (spell as NovaSpell).radius, GUARD, 0.4])


func _process(delta: float) -> void:
	for blast: Array in _blasts:
		blast[3] -= delta
	_blasts = _blasts.filter(func(b: Array) -> bool: return b[3] > 0.0)
	if not visible:
		return
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for node in get_tree().get_nodes_in_group(&"fighters"):
		_draw_fighter(node as Fighter)
	for node in get_tree().get_nodes_in_group(&"projectiles"):
		var bolt := node as Projectile
		_circle(bolt.global_position, bolt.spell.radius, Vector3.UP, SpellData.element_color(bolt.spell.element))
		_circle(bolt.global_position, bolt.spell.radius, Vector3.RIGHT, SpellData.element_color(bolt.spell.element))
	for node in get_tree().get_nodes_in_group(&"zones"):
		_draw_wall(node as FlameWall)
	for blast: Array in _blasts:
		_circle(blast[0] + Vector3.UP * 0.1, blast[1], Vector3.UP, blast[2])
	_mesh.surface_end()


func _draw_fighter(f: Fighter) -> void:
	var s := f.state
	var feet := f.global_position + Vector3.UP * 0.05
	_circle(feet, Fighter.RADIUS, Vector3.UP, BODY)
	_circle(feet + Vector3.UP * 1.5, Fighter.RADIUS, Vector3.UP, BODY)
	if s.is_dead():
		return
	if s.action == FighterState.Action.ATTACK:
		var a := s.attack
		var color := WINDUP if s.action_time < a.windup else (ACTIVE if a.is_active_at(s.action_time) else RECOVERY)
		_arc(feet + Vector3.UP * 0.9, a.reach + Fighter.RADIUS, s.facing_yaw, a.arc, color)
	if s.blocking:
		_arc(feet + Vector3.UP * 1.0, 1.0, s.facing_yaw, f.tuning.block_arc, GUARD)
	if s.parry_window > 0.0:
		_circle(feet + Vector3.UP * 1.0, 1.25, Vector3.UP, PARRY)
	if s.invulnerable > 0.0:
		_circle(feet + Vector3.UP * 0.8, 0.65, Vector3.UP, INVULN)


func _draw_wall(wall: FlameWall) -> void:
	var half_length := wall.spell.length * 0.5
	var half_width := wall.spell.width * 0.5
	var x := wall.global_basis.x
	var z := wall.global_basis.z
	var base := wall.global_position + Vector3.UP * 0.1
	var corners := [base + x * half_length + z * half_width, base - x * half_length + z * half_width,
			base - x * half_length - z * half_width, base + x * half_length - z * half_width]
	for i in 4:
		_line(corners[i], corners[(i + 1) % 4], ACTIVE)


## A horizontal pie outline: the swing or guard arc around a facing.
func _arc(centre: Vector3, radius: float, facing_yaw: float, degrees: float, color: Color) -> void:
	var half := deg_to_rad(degrees * 0.5)
	var steps := 16
	var prev := centre + CombatRules.yaw_to_dir(facing_yaw - half) * radius
	_line(centre, prev, color)
	for i in range(1, steps + 1):
		var point := centre + CombatRules.yaw_to_dir(facing_yaw - half + 2.0 * half * i / steps) * radius
		_line(prev, point, color)
		prev = point
	_line(centre, prev, color)


func _circle(centre: Vector3, radius: float, normal: Vector3, color: Color) -> void:
	var u := normal.cross(Vector3.FORWARD if absf(normal.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var v := normal.cross(u)
	var steps := 24
	for i in steps:
		var a := TAU * i / steps
		var b := TAU * (i + 1) / steps
		_line(centre + (u * cos(a) + v * sin(a)) * radius, centre + (u * cos(b) + v * sin(b)) * radius, color)


func _line(a: Vector3, b: Vector3, color: Color) -> void:
	_mesh.surface_set_color(color)
	_mesh.surface_add_vertex(a)
	_mesh.surface_set_color(color)
	_mesh.surface_add_vertex(b)
