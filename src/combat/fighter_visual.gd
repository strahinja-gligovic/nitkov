class_name FighterVisual
extends Node3D
## Displays a fighter: a KayKit model with toon materials and layered
## animation. Strafe locomotion runs underneath, full-body slots handle
## swings, dodges and hit reactions, and an upper-body overlay handles
## blocking and casting. Every frame it reads Fighter.state and seeks clips to
## match it. It never writes simulation state.

const SWORD_SCENE := preload("res://assets/kaykit/weapons/sword_1handed.gltf")
const SKELETON := "Rig/Skeleton3D"
const UPPER_BONES: Array[String] = [
	"spine", "chest", "head",
	"upperarm.l", "lowerarm.l", "hand.l", "handslot.l", "elbowIK.l", "handIK.l",
	"upperarm.r", "lowerarm.r", "hand.r", "handslot.r", "elbowIK.r", "handIK.r",
]
const LOOPING: Array[StringName] = [
	&"Idle", &"Running_A", &"Walking_Backwards", &"Running_Strafe_Left",
	&"Running_Strafe_Right", &"Blocking", &"Jump_Idle",
]
## Ground speed (m/s) at which the run cycle plays at its authored speed.
const RUN_CLIP_SPEED := 4.0

var fighter: Fighter
var model: Node3D
var anim_player: AnimationPlayer
var tree: AnimationTree
var materials: Array[ShaderMaterial] = []
var sword_materials: Array[ShaderMaterial] = []
var hand_slot_left: Node3D
var hand_slot_right: Node3D
var sword: Node3D

var _slots: Array[AnimationNodeAnimation] = []
var _upper: AnimationNodeAnimation
var _full_slot := 0
var _full_key := ""
var _full_weight := 0.0
var _slot_mix := 0.0
var _upper_weight := 0.0
var _loco_blend := Vector2.ZERO
var _flash := 0.0
var _last_hp := -1.0
var _time := 0.0
var _clip_lengths := {}
var _gauntlet_root: Node3D
var _gauntlet_core: MeshInstance3D
var _gauntlet_light: OmniLight3D
var _built_character: CharacterData


func _ready() -> void:
	fighter = get_parent() as Fighter
	_build_model()
	fighter.loadout_changed.connect(_on_loadout_changed)


func _on_loadout_changed() -> void:
	if fighter.character != _built_character:
		_build_model()
	else:
		_build_gauntlet()


## Instances the character's model, strips its props, attaches the longsword,
## converts it to the toon look and builds its AnimationTree.
func _build_model() -> void:
	if model:
		remove_child(model)
		model.queue_free()
		_slots.clear()
		_clip_lengths.clear()
		_full_key = ""
		_gauntlet_root = null
		_gauntlet_core = null
	var character := fighter.character
	_built_character = character
	model = character.scene.instantiate()
	model.scale = Vector3.ONE * character.model_scale
	model.rotation.y = PI  # KayKit faces +Z; fighters face -Z
	add_child(model)
	for node_name in character.remove_nodes:
		var node := model.find_child(node_name, true, false)
		if node:
			node.get_parent().remove_child(node)
			node.free()
	hand_slot_left = model.find_child("handslot_l", true, false)
	hand_slot_right = model.find_child("handslot_r", true, false)
	if character.sword_node != "":
		sword = model.find_child(character.sword_node, true, false)
	else:
		sword = SWORD_SCENE.instantiate()
		sword.position = Vector3(0.0, 0.0333, 0.0)
		sword.rotation_degrees = Vector3(0.0, 180.0, 0.0)
		hand_slot_right.add_child(sword)
	materials = ToonMaterials.convert_model(model)
	sword_materials = _materials_under(sword)
	anim_player = model.find_child("AnimationPlayer", true, false)
	for clip in LOOPING:
		anim_player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	_build_tree()
	_build_gauntlet()


func _process(delta: float) -> void:
	_time += delta
	var s := fighter.state
	_update_full_body(s, delta)
	_update_upper_body(s, delta)
	_update_locomotion(delta)
	tree.set(&"parameters/full_blend/blend_amount", _full_weight)
	tree.set(&"parameters/full_mix/blend_amount", _slot_mix)
	tree.set(&"parameters/upper_blend/blend_amount", _upper_weight)
	tree.advance(delta)
	_update_status_tint(s)
	_update_gauntlet(s)
	_update_flash(s, delta)
	_update_tells(s)
	model.position.x = sin(_time * 90.0) * 0.03 if s.hitstop > 0.0 else 0.0


# --- animation --------------------------------------------------------------

## The clip and clip time a full-body action should show, or [] for none.
func _full_body_pose(s: FighterState) -> Array:
	match s.action:
		FighterState.Action.ATTACK:
			var a := s.attack
			return [a.animation, _warp(s.action_time, a.windup, a.active + a.recovery, a.strike_time, a.animation)]
		FighterState.Action.DASH:
			var clip := _dodge_clip(s)
			return [clip, _progress(s) * _len(clip)]
		FighterState.Action.FLINCH:
			return [&"Hit_A", _progress(s) * _len(&"Hit_A") * 0.85]
		FighterState.Action.STAGGER:
			var clip := &"Block_Hit" if s.stagger_kind == &"guard_break" else &"Hit_B"
			return [clip, _progress(s) * _len(clip)]
		FighterState.Action.DEAD:
			return [&"Death_A", minf(s.action_time, _len(&"Death_A") - 0.01)]
	if s.leaping or (not s.on_floor and fighter.velocity.y < -3.0):
		return [&"Jump_Idle", fmod(_time, _len(&"Jump_Idle"))]
	return []


## The clip and clip time the upper body should show over locomotion, or [].
func _upper_body_pose(s: FighterState) -> Array:
	if s.action == FighterState.Action.CAST and s.spell != null:
		var sp := s.spell
		return [sp.animation, _warp(s.action_time, sp.windup, sp.recovery, sp.release_time, sp.animation)]
	if s.blocking:
		return [&"Blocking", fmod(_time, _len(&"Blocking"))]
	return []


func _update_full_body(s: FighterState, delta: float) -> void:
	var pose := _full_body_pose(s)
	if pose.is_empty():
		_full_key = ""
		_full_weight = move_toward(_full_weight, 0.0, delta / 0.12)
	else:
		var key := "%d:%s" % [s.action_serial, pose[0]]
		if key != _full_key:
			if _full_weight > 0.05:
				_full_slot = 1 - _full_slot  # crossfade from the other slot
			else:
				_slot_mix = float(_full_slot)
			_slots[_full_slot].animation = pose[0]
			_full_key = key
		tree.set("parameters/full_%d_seek/seek_request" % _full_slot, pose[1])
		_full_weight = move_toward(_full_weight, 1.0, delta / 0.05)
	_slot_mix = move_toward(_slot_mix, float(_full_slot), delta / 0.07)


func _update_upper_body(s: FighterState, delta: float) -> void:
	var pose := _upper_body_pose(s)
	if pose.is_empty():
		_upper_weight = move_toward(_upper_weight, 0.0, delta / 0.1)
		return
	if _upper.animation != pose[0]:
		_upper.animation = pose[0]
	tree.set(&"parameters/upper_seek/seek_request", pose[1])
	_upper_weight = move_toward(_upper_weight, 1.0, delta / 0.06)


func _update_locomotion(delta: float) -> void:
	var velocity := Vector3(fighter.velocity.x, 0.0, fighter.velocity.z)
	var forward := fighter.forward()
	var right := Vector3(-forward.z, 0.0, forward.x)
	var local := Vector2(velocity.dot(right), velocity.dot(forward))
	var target := (local / maxf(fighter.tuning.walk_speed, 0.1)).limit_length(1.0)
	_loco_blend = _loco_blend.lerp(target, 1.0 - exp(-12.0 * delta))
	tree.set(&"parameters/loco/blend_position", _loco_blend)
	var speed := local.length()
	tree.set(&"parameters/loco_speed/scale", clampf(speed / RUN_CLIP_SPEED, 0.7, 2.2) if speed > 0.3 else 1.0)


## Maps action time onto clip time so the clip's key moment (strike/release)
## lands exactly when the logic says it happens.
func _warp(t: float, before: float, after: float, key_time: float, clip: StringName) -> float:
	if t < before:
		return t / maxf(before, 0.001) * key_time
	var length := _len(clip)
	return key_time + minf((t - before) / maxf(after, 0.001), 1.0) * (length - key_time)


func _progress(s: FighterState) -> float:
	return clampf(s.action_time / maxf(s.action_duration, 0.001), 0.0, 1.0)


func _dodge_clip(s: FighterState) -> StringName:
	var forward := CombatRules.yaw_to_dir(s.facing_yaw)
	var right := Vector3(-forward.z, 0.0, forward.x)
	var f := s.dash_dir.dot(forward)
	var r := s.dash_dir.dot(right)
	if absf(f) >= absf(r):
		return &"Dodge_Forward" if f >= 0.0 else &"Dodge_Backward"
	return &"Dodge_Right" if r > 0.0 else &"Dodge_Left"


func _len(clip: StringName) -> float:
	if not _clip_lengths.has(clip):
		_clip_lengths[clip] = anim_player.get_animation(clip).length if anim_player.has_animation(clip) else 1.0
	return _clip_lengths[clip]


func _build_tree() -> void:
	var root := AnimationNodeBlendTree.new()
	var loco := AnimationNodeBlendSpace2D.new()
	loco.add_blend_point(_clip(&"Idle"), Vector2.ZERO, -1, &"idle")
	loco.add_blend_point(_clip(&"Running_A"), Vector2(0, 1), -1, &"forward")
	loco.add_blend_point(_clip(&"Walking_Backwards"), Vector2(0, -1), -1, &"back")
	loco.add_blend_point(_clip(&"Running_Strafe_Left"), Vector2(-1, 0), -1, &"left")
	loco.add_blend_point(_clip(&"Running_Strafe_Right"), Vector2(1, 0), -1, &"right")
	root.add_node(&"loco", loco)
	root.add_node(&"loco_speed", AnimationNodeTimeScale.new())
	root.connect_node(&"loco_speed", 0, &"loco")

	for i in 2:
		var slot := _clip(&"Idle")
		_slots.append(slot)
		root.add_node(StringName("full_%d" % i), slot)
		root.add_node(StringName("full_%d_seek" % i), AnimationNodeTimeSeek.new())
		root.connect_node(StringName("full_%d_seek" % i), 0, StringName("full_%d" % i))
	root.add_node(&"full_mix", AnimationNodeBlend2.new())
	root.connect_node(&"full_mix", 0, &"full_0_seek")
	root.connect_node(&"full_mix", 1, &"full_1_seek")
	root.add_node(&"full_blend", AnimationNodeBlend2.new())
	root.connect_node(&"full_blend", 0, &"loco_speed")
	root.connect_node(&"full_blend", 1, &"full_mix")

	_upper = _clip(&"Blocking")
	root.add_node(&"upper", _upper)
	root.add_node(&"upper_seek", AnimationNodeTimeSeek.new())
	root.connect_node(&"upper_seek", 0, &"upper")
	var upper_blend := AnimationNodeBlend2.new()
	upper_blend.filter_enabled = true
	for bone in UPPER_BONES:
		upper_blend.set_filter_path(NodePath("%s:%s" % [SKELETON, bone]), true)
	root.add_node(&"upper_blend", upper_blend)
	root.connect_node(&"upper_blend", 0, &"full_blend")
	root.connect_node(&"upper_blend", 1, &"upper_seek")
	root.connect_node(&"output", 0, &"upper_blend")

	tree = AnimationTree.new()
	tree.name = "AnimationTree"
	tree.tree_root = root
	model.add_child(tree)
	tree.anim_player = tree.get_path_to(anim_player)
	# the dodge clips slide the root bone; the simulation already moves the body
	tree.root_motion_track = NodePath("%s:root" % SKELETON)
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	tree.active = true


static func _clip(clip: StringName) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = clip
	return node


# --- gauntlet ---------------------------------------------------------------

## A glowing orb (primary spell's element), a bracer (signature's element)
## and a light on the left fist.
func _build_gauntlet() -> void:
	if _gauntlet_root:
		_gauntlet_root.queue_free()
		_gauntlet_root = null
	if hand_slot_left == null:
		return
	var color := SpellData.element_color(fighter.primary.element)
	var accent := SpellData.element_color(fighter.signature.element)
	_gauntlet_root = Node3D.new()
	_gauntlet_root.name = "Gauntlet"
	hand_slot_left.add_child(_gauntlet_root)

	var bracer := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.12
	torus.outer_radius = 0.24
	bracer.mesh = torus
	bracer.position = Vector3(0.0, -0.12, 0.0)
	bracer.material_override = ToonMaterials.make(Color(0.24, 0.19, 0.3), {&"glow_color": accent, &"glow_energy": 0.9})
	_gauntlet_root.add_child(bracer)

	_gauntlet_core = MeshInstance3D.new()
	var orb := SphereMesh.new()
	orb.radius = 0.15
	orb.height = 0.3
	_gauntlet_core.mesh = orb
	_gauntlet_core.position = Vector3(0.0, 0.08, 0.0)
	_gauntlet_core.material_override = ToonMaterials.make_vfx(color.lightened(0.3), 3.5, false)
	_gauntlet_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_gauntlet_root.add_child(_gauntlet_core)

	var halo := MeshInstance3D.new()
	var halo_mesh := SphereMesh.new()
	halo_mesh.radius = 0.3
	halo_mesh.height = 0.6
	halo.mesh = halo_mesh
	var halo_material := ToonMaterials.make_vfx(color, 1.5)
	halo_material.albedo_color.a = 0.3
	halo.material_override = halo_material
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_gauntlet_core.add_child(halo)

	_gauntlet_light = OmniLight3D.new()
	_gauntlet_light.light_color = color
	_gauntlet_light.omni_range = 2.5
	_gauntlet_core.add_child(_gauntlet_light)


## The orb swells while a spell winds up and flares while guarding.
func _update_gauntlet(s: FighterState) -> void:
	if _gauntlet_core == null:
		return
	var boost := 1.0
	if s.action == FighterState.Action.CAST and not s.spell_released:
		boost = 1.0 + 2.5 * clampf(s.action_time / maxf(s.spell.windup, 0.01), 0.0, 1.0)
	elif s.blocking:
		boost = 1.7
	_gauntlet_core.scale = Vector3.ONE * (1.0 + 0.3 * (boost - 1.0))
	_gauntlet_light.light_energy = 0.7 * boost


# --- flashes and tells ------------------------------------------------------

## Burning bodies flicker orange; chilled ones glow colder with each stack.
func _update_status_tint(s: FighterState) -> void:
	var energy := 0.0
	var color := Color.BLACK
	if s.chill_stacks > 0:
		color = SpellData.element_color(SpellData.Element.FROST)
		energy = 0.15 * s.chill_stacks
	if s.burn_time > 0.0:
		color = SpellData.element_color(SpellData.Element.FIRE)
		energy = maxf(energy, 0.45 + 0.3 * sin(_time * 26.0))
	for material in materials:
		material.set_shader_parameter(&"glow_color", color)
		material.set_shader_parameter(&"glow_energy", energy)

func _update_flash(s: FighterState, delta: float) -> void:
	if _last_hp >= 0.0 and s.hp < _last_hp:
		_flash = 1.0
	_last_hp = s.hp
	if _flash <= 0.0:
		return
	_flash = maxf(_flash - delta / 0.14, 0.0)
	for material in materials:
		material.set_shader_parameter(&"flash_amount", _flash * 0.85)


## Heavy wind-ups make the blade glow brighter until it swings. (Runs after
## the status tint, so the blade's glow wins.)
func _update_tells(s: FighterState) -> void:
	if not (s.action == FighterState.Action.ATTACK and s.attack.hyperarmor and s.action_time < s.attack.windup + s.attack.active):
		return
	var glow := 1.0 + 4.0 * clampf(s.action_time / s.attack.windup, 0.0, 1.0)
	for material in sword_materials:
		material.set_shader_parameter(&"glow_color", Color(1.0, 0.45, 0.1))
		material.set_shader_parameter(&"glow_energy", glow)


static func _materials_under(root: Node) -> Array[ShaderMaterial]:
	var found: Array[ShaderMaterial] = []
	if root == null:
		return found
	var meshes: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.append(root)
	for node in meshes:
		var mesh_instance := node as MeshInstance3D
		for surface in mesh_instance.get_surface_override_material_count():
			var material := mesh_instance.get_surface_override_material(surface) as ShaderMaterial
			if material:
				found.append(material)
	return found
