class_name WindSpearLook
extends Node3D
## The Wind Spear's body: a heavy javelin of condensed storm wind. A white-hot
## leaf-shaped point inside a shock cone of compressed air, a long tapered
## shaft of twisting bands wrapped in a darker storm layer, spiral rings
## spinning around its neck, a vortex of streaks spiralling off its tail,
## leaves and motes sucked along it, and shock rings it sheds into the air
## behind it as it flies. -Z is the direction of flight; the Projectile
## places it every frame. finish() lets the vortex fade. Cosmetic only.

const CORE_SHADER := preload("res://src/vfx/wind/wind_core.gdshader")
const VORTEX_SHADER := preload("res://src/vfx/wind/wind_vortex.gdshader")
const RING_SHADER := preload("res://src/vfx/wind/wind_ring.gdshader")
const LINE_SHADER := preload("res://src/vfx/wind/wind_line.gdshader")
const FLASH_SHADER := preload("res://src/vfx/wind/wind_flash.gdshader")

## Seconds between the shock rings it leaves behind, and how long each lasts.
const SHED_EVERY := 0.07
const SHED_LIFE := 0.34
const SHED_POOL := 6
const LEAVES := 4
const MOTES := 6
const FADE_OUT := 0.16
## Metres per second it flies (to grow its tail out of the hand) and the
## distance it covers before it starts shedding rings (none in your face).
const SPEED := 34.0
## Size of the camera-facing star on the point (metres across).
const GLINT_SIZE := 0.62
const SHED_AFTER := 4.5

static var _meshes := {}
static var _materials := {}

var _time := 0.0
var _ending := -1.0
var _spin := 0.0
var _tail: Node3D
var _parts: Array[GeometryInstance3D] = []
var _rings: Array[MeshInstance3D] = []
var _helix: MeshInstance3D
var _shock: MeshInstance3D
var _glint: MeshInstance3D
var _bits: MultiMeshInstance3D
var _light: OmniLight3D
var _wake: WindRibbon
var _shed: Array[MeshInstance3D] = []
var _shed_age := PackedFloat32Array()
var _next_shed := 0
var _shed_timer := 0.0
var _seeds := PackedFloat32Array()


static func create(_spell: ProjectileSpell) -> WindSpearLook:
	return WindSpearLook.new()


func _ready() -> void:
	_build_shared()
	_add_part(_meshes[&"head_core"], _materials[&"core"])
	var sheath := _add_part(_meshes[&"head"], _materials[&"sheath"])
	sheath.set_instance_shader_parameter(&"anim_time", 0.0)
	_shock = _add_part(_meshes[&"shock"], _materials[&"shock"])
	# a white-hot star on the point that faces the camera, so the spear's tip
	# reads even end-on from behind the thrower
	_glint = MeshInstance3D.new()
	_glint.mesh = _meshes[&"quad"]
	_glint.material_override = _materials[&"glint"]
	_glint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glint.position = Vector3(0.0, 0.0, -1.1)
	_glint.set_instance_shader_parameter(&"progress", 0.25)
	add_child(_glint)
	# the tail grows out of the hand instead of reaching back through the thrower
	_tail = Node3D.new()
	add_child(_tail)
	_tail.add_child(_add_part(_meshes[&"shaft"], _materials[&"shaft"], false))
	_tail.add_child(_add_part(_meshes[&"storm"], _materials[&"storm"], false))
	_helix = _add_part(_meshes[&"helix"], _materials[&"helix"], false)
	_tail.add_child(_helix)
	_tail.scale = Vector3(1.0, 1.0, 0.1)
	for i in 2:
		var ring := MeshInstance3D.new()
		ring.mesh = _meshes[&"annulus"]
		ring.material_override = _materials[&"spin_ring"]
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.rotation.x = PI * 0.5  # around the flight line
		ring.position.z = -0.15 + 0.6 * i
		var radius := 0.34 + 0.12 * i
		ring.set_instance_shader_parameter(&"radius_from", radius)
		ring.set_instance_shader_parameter(&"radius_to", radius)
		ring.set_instance_shader_parameter(&"progress", 0.3)
		ring.set_instance_shader_parameter(&"seed", randf())
		add_child(ring)
		_rings.append(ring)
	_bits = MultiMeshInstance3D.new()
	_bits.multimesh = WindParticles.make_multimesh(LEAVES + MOTES)
	_bits.material_override = WindParticles.shared_material()
	_bits.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bits.extra_cull_margin = 2.0
	add_child(_bits)
	for i in LEAVES + MOTES:
		_seeds.append(randf())
	for i in SHED_POOL:
		var ring := MeshInstance3D.new()
		ring.mesh = _meshes[&"annulus"]
		ring.material_override = _materials[&"shed_ring"]
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.top_level = true
		ring.visible = false
		ring.set_instance_shader_parameter(&"radius_from", 0.3)
		ring.set_instance_shader_parameter(&"radius_to", 0.9)
		add_child(ring)
		_shed.append(ring)
		_shed_age.append(SHED_LIFE)
	_wake = WindRibbon.spawn(self, _materials[&"wake"], 0.22, 0.12)
	_wake.dash_length = 1.4
	_wake.spread = 2.0
	_light = OmniLight3D.new()
	_light.light_color = WindFx.COLOR
	_light.light_energy = 2.2
	_light.omni_range = 5.0
	_light.shadow_enabled = false
	add_child(_light)


func _add_part(mesh: Mesh, material: Material, attach := true) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if attach:
		add_child(part)
	_parts.append(part)
	return part


func _process(delta: float) -> void:
	_time += delta
	var fade := 1.0
	if _ending >= 0.0:
		_ending += delta
		fade = 1.0 - clampf(_ending / FADE_OUT, 0.0, 1.0)
		_light.light_energy = 2.2 * fade
		if _ending > SHED_LIFE + 0.05:
			queue_free()
			return
	else:
		_tail.scale.z = clampf(_time * SPEED / 3.0, 0.1, 1.0)
		_wake.add(global_transform * Vector3(0.0, 0.0, 0.4))
		_shed_timer -= delta
		if _shed_timer <= 0.0 and _time * SPEED > SHED_AFTER:
			_shed_timer += SHED_EVERY
			_shed_ring()
	_spin += delta * TAU * 2.2
	for part in _parts:
		part.set_instance_shader_parameter(&"anim_time", _time)
		part.set_instance_shader_parameter(&"fade", fade)
	# the shock cone flickers, the helix and the rings spin
	_shock.scale = Vector3.ONE * (1.0 + 0.06 * sin(_time * 70.0))
	_glint.scale = Vector3.ONE * GLINT_SIZE * fade * (1.0 + 0.18 * sin(_time * 55.0))
	_glint.set_instance_shader_parameter(&"spin", _spin * 0.6)
	_helix.rotation.z = -_spin * 1.3
	for i in _rings.size():
		_rings[i].rotation = Vector3(PI * 0.5, 0.0, 0.0)
		_rings[i].rotate_object_local(Vector3.UP, _spin * (1.6 if i == 0 else -1.1))
		_rings[i].set_instance_shader_parameter(&"fade", fade)
	_age_shed(delta)
	_place_bits(fade)


## Ends the spear's flight: the body fades out fast, the shed rings play out.
func finish() -> void:
	if _ending < 0.0:
		_ending = 0.0


## Leaves a shock ring in the air at the spear's neck, facing along its flight.
func _shed_ring() -> void:
	var ring := _shed[_next_shed]
	_next_shed = (_next_shed + 1) % SHED_POOL
	ring.global_transform = Transform3D(global_basis.orthonormalized() * Basis(Vector3.RIGHT, PI * 0.5), global_transform * Vector3(0.0, 0.0, 0.1))
	ring.rotate_object_local(Vector3.UP, randf() * TAU)
	ring.set_instance_shader_parameter(&"seed", randf())
	ring.visible = true
	_shed_age[_shed.find(ring)] = 0.0


func _age_shed(delta: float) -> void:
	for i in SHED_POOL:
		if _shed_age[i] >= SHED_LIFE:
			_shed[i].visible = false
			continue
		_shed_age[i] += delta
		_shed[i].set_instance_shader_parameter(&"progress", _shed_age[i] / SHED_LIFE)


## Leaves and motes sucked along the spear: each spirals around the shaft
## from the point back past the tail, then starts over.
func _place_bits(fade: float) -> void:
	var multimesh := _bits.multimesh
	for i in LEAVES + MOTES:
		var random := _seeds[i]
		var leaf := i < LEAVES
		var cycle := fposmod(random * 5.3 + _time * (1.7 if leaf else 2.4), 1.0)
		var angle := random * TAU + _time * (11.0 + random * 6.0) * (1.0 if i % 2 == 0 else -1.0)
		var radius := lerpf(0.3, 0.62, cycle) + random * 0.1
		var at := Vector3(cos(angle) * radius, sin(angle) * radius, lerpf(-0.4, 2.4, cycle) * _tail.scale.z)
		var alpha := sin(cycle * PI) * fade
		var basis := Basis.IDENTITY.scaled(Vector3.ONE * 0.05)
		if leaf:
			basis = Basis(Vector3(random - 0.5, 1.0, random).normalized(), _time * (12.0 + random * 9.0)).scaled(Vector3.ONE * 0.2)
		multimesh.set_instance_transform(i, Transform3D(basis, at))
		var kind := WindParticles.Kind.LEAF if leaf else WindParticles.Kind.MOTE
		multimesh.set_instance_custom_data(i, WindParticles.custom(kind, cycle, random, alpha))
	multimesh.visible_instance_count = LEAVES + MOTES


static func _build_shared() -> void:
	if not _meshes.is_empty():
		return
	# a leaf-shaped point (z, radius), the tip leading at -Z
	var head := PackedVector2Array([Vector2(-1.2, 0.0), Vector2(-1.05, 0.045), Vector2(-0.85, 0.11),
			Vector2(-0.66, 0.16), Vector2(-0.5, 0.15), Vector2(-0.38, 0.1), Vector2(-0.28, 0.07)])
	_meshes[&"head"] = WindMeshes.lathe(head, 12)
	var core := PackedVector2Array()
	for point in head:
		core.append(Vector2(point.x + 0.04, point.y * 0.5))
	_meshes[&"head_core"] = WindMeshes.lathe(core, 10)
	_meshes[&"shock"] = WindMeshes.lathe(PackedVector2Array([Vector2(-1.32, 0.0), Vector2(-1.22, 0.14),
			Vector2(-1.0, 0.27), Vector2(-0.7, 0.38), Vector2(-0.35, 0.45), Vector2(-0.05, 0.48)]), 20)
	_meshes[&"shaft"] = WindMeshes.lathe(PackedVector2Array([Vector2(-0.45, 0.06), Vector2(-0.25, 0.15),
			Vector2(0.1, 0.19), Vector2(0.7, 0.16), Vector2(1.5, 0.1), Vector2(2.3, 0.05), Vector2(2.9, 0.02)]), 16)
	_meshes[&"storm"] = WindMeshes.lathe(PackedVector2Array([Vector2(-0.35, 0.1), Vector2(-0.1, 0.26),
			Vector2(0.4, 0.3), Vector2(1.2, 0.24), Vector2(2.1, 0.15), Vector2(3.0, 0.08)]), 16)
	_meshes[&"annulus"] = WindMeshes.annulus(0.55)
	_meshes[&"quad"] = QuadMesh.new()
	# two strands spiralling off the tail, widening as they go
	var paths: Array[PackedVector3Array] = []
	var widths := PackedFloat32Array()
	for strand in 2:
		var path := PackedVector3Array()
		for k in 25:
			var t := float(k) / 24.0
			var angle := strand * PI + t * TAU * 1.1
			var radius := lerpf(0.2, 0.42, t)
			path.append(Vector3(cos(angle) * radius, sin(angle) * radius, lerpf(0.1, 3.1, t)))
		paths.append(path)
		widths.append(0.04)
	_meshes[&"helix"] = WindMeshes.lines(paths, widths, 0.5)

	var core_material := ShaderMaterial.new()
	core_material.shader = CORE_SHADER
	core_material.set_shader_parameter(&"hot_band", 0.75)
	core_material.set_shader_parameter(&"hot_energy", 2.0)
	core_material.set_shader_parameter(&"ink_band", 2.0)  # no ink on the inner core
	_materials[&"core"] = core_material
	var glint := ShaderMaterial.new()
	glint.shader = FLASH_SHADER
	glint.set_shader_parameter(&"spikes", 4.0)
	glint.set_shader_parameter(&"swirl", 1.2)
	glint.set_shader_parameter(&"energy", 1.7)
	glint.set_shader_parameter(&"pull", 0.4)
	_materials[&"glint"] = glint
	var sheath := ShaderMaterial.new()
	sheath.shader = CORE_SHADER
	sheath.set_shader_parameter(&"hot_energy", 1.6)
	sheath.set_shader_parameter(&"hot_band", 0.35)
	sheath.set_shader_parameter(&"ink_band", 0.84)
	_materials[&"sheath"] = sheath
	var shock := ShaderMaterial.new()
	shock.shader = VORTEX_SHADER
	shock.set_shader_parameter(&"strands", 5.0)
	shock.set_shader_parameter(&"twist", 0.4)
	shock.set_shader_parameter(&"speed", 1.5)
	shock.set_shader_parameter(&"band_fill", 0.18)
	shock.set_shader_parameter(&"energy", 0.8)
	shock.set_shader_parameter(&"rim_energy", 1.0)
	shock.set_shader_parameter(&"body_alpha", 0.08)
	shock.set_shader_parameter(&"front_fade", 0.3)
	shock.set_shader_parameter(&"back_fade", 1.0)
	shock.set_shader_parameter(&"distortion", 0.02)
	_materials[&"shock"] = shock
	var shaft := ShaderMaterial.new()
	shaft.shader = VORTEX_SHADER
	shaft.set_shader_parameter(&"strands", 3.0)
	shaft.set_shader_parameter(&"twist", 2.2)
	shaft.set_shader_parameter(&"speed", 2.6)
	shaft.set_shader_parameter(&"band_fill", 0.36)
	shaft.set_shader_parameter(&"energy", 1.5)
	shaft.set_shader_parameter(&"body_alpha", 0.3)
	_materials[&"shaft"] = shaft
	var storm := ShaderMaterial.new()
	storm.shader = VORTEX_SHADER
	storm.set_shader_parameter(&"strands", 2.0)
	storm.set_shader_parameter(&"twist", -1.2)
	storm.set_shader_parameter(&"speed", -1.6)
	storm.set_shader_parameter(&"band_fill", 0.16)
	storm.set_shader_parameter(&"storm_fill", 0.3)
	storm.set_shader_parameter(&"storm_alpha", 0.55)
	storm.set_shader_parameter(&"energy", 1.1)
	storm.set_shader_parameter(&"rim_energy", 0.5)
	storm.set_shader_parameter(&"body_alpha", 0.1)
	storm.set_shader_parameter(&"front_fade", 0.2)
	_materials[&"storm"] = storm
	var helix := ShaderMaterial.new()
	helix.shader = LINE_SHADER
	helix.set_shader_parameter(&"energy", 1.3)
	helix.set_shader_parameter(&"dash_fill", 0.6)
	helix.set_shader_parameter(&"scroll", 4.0)
	helix.set_shader_parameter(&"head_fade", 0.1)
	helix.set_shader_parameter(&"tail_fade", 1.0)
	_materials[&"helix"] = helix
	var spin_ring := ShaderMaterial.new()
	spin_ring.shader = RING_SHADER
	spin_ring.set_shader_parameter(&"arcs", 2.0)
	spin_ring.set_shader_parameter(&"arc_fill", 0.6)
	spin_ring.set_shader_parameter(&"swirl", 0.25)
	spin_ring.set_shader_parameter(&"spin", 0.0)
	spin_ring.set_shader_parameter(&"band_from", 0.55)
	spin_ring.set_shader_parameter(&"band_to", 0.55)
	spin_ring.set_shader_parameter(&"energy", 1.6)
	_materials[&"spin_ring"] = spin_ring
	var shed_ring := ShaderMaterial.new()
	shed_ring.shader = RING_SHADER
	shed_ring.set_shader_parameter(&"arcs", 2.0)
	shed_ring.set_shader_parameter(&"arc_fill", 0.82)
	shed_ring.set_shader_parameter(&"swirl", 0.12)
	shed_ring.set_shader_parameter(&"spin", 0.4)
	shed_ring.set_shader_parameter(&"band_from", 0.35)
	shed_ring.set_shader_parameter(&"band_to", 0.85)
	shed_ring.set_shader_parameter(&"energy", 1.3)
	_materials[&"shed_ring"] = shed_ring
	var wake := ShaderMaterial.new()
	wake.shader = LINE_SHADER
	wake.set_shader_parameter(&"energy", 0.9)
	wake.set_shader_parameter(&"core_width", 0.3)
	wake.set_shader_parameter(&"head_fade", 0.1)
	wake.set_shader_parameter(&"tail_fade", 0.7)
	_materials[&"wake"] = wake
