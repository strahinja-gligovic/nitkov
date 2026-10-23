extends GutTest
## Base for tests that put spells into a small world: a floor, fighters
## placed by hand, and the projectiles, strikes, walls and bursts they cast.
## Nothing moves by itself. The fighters' and the spells' physics ticks are
## switched off, and each test steps them one fixed tick at a time, so every
## result is exact and nothing depends on frame timing.
##
## Effects the spells spawn land in `world` too, so they run (headless) and
## are freed with it after each test. Hits and impacts are recorded from
## CombatEvents into `hits`, `impacts` and `casts`.

const FIGHTER := preload("res://src/combat/fighter.tscn")
const DT := 1.0 / 60.0

## Holds everything a test builds; freed after each test.
var world: Node3D
var tuning: CombatTuning
## One entry per CombatEvents.hit_resolved: {attacker, target, result, at}.
var hits: Array[Dictionary] = []
## One entry per CombatEvents.spell_impact: {caster, spell, at}.
var impacts: Array[Dictionary] = []
## One entry per CombatEvents.spell_cast: {fighter, spell}.
var casts: Array[Dictionary] = []


func before_each() -> void:
	tuning = GameData.tuning
	hits.clear()
	impacts.clear()
	casts.clear()
	world = Node3D.new()
	world.name = "World"
	add_child_autofree(world)
	add_block(Vector3(0.0, -0.5, 0.0), Vector3(200.0, 1.0, 200.0))  # the floor, top at y = 0
	CombatEvents.hit_resolved.connect(_on_hit_resolved)
	CombatEvents.spell_impact.connect(_on_spell_impact)
	CombatEvents.spell_cast.connect(_on_spell_cast)


func after_each() -> void:
	CombatEvents.hit_resolved.disconnect(_on_hit_resolved)
	CombatEvents.spell_impact.disconnect(_on_spell_impact)
	CombatEvents.spell_cast.disconnect(_on_spell_cast)


func _on_hit_resolved(attacker: Node, target: Node, result: HitResult, at: Vector3) -> void:
	hits.append({"attacker": attacker, "target": target, "result": result, "at": at})


func _on_spell_impact(caster: Node, spell: Resource, at: Vector3) -> void:
	impacts.append({"caster": caster, "spell": spell, "at": at})


func _on_spell_cast(fighter: Node, spell: Resource) -> void:
	casts.append({"fighter": fighter, "spell": spell})


# --- building the world ------------------------------------------------------

## A box of world geometry (physics layer 1).
func add_block(centre: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = centre
	world.add_child(body)
	return body


## A fighter standing at `at` on `team`, facing `yaw` (0 faces -Z), settled
## onto the ground. It only acts when a test drives it.
func add_fighter(at: Vector3, team := 0, yaw := 0.0) -> Fighter:
	var fighter: Fighter = FIGHTER.instantiate()
	fighter.team = team
	fighter.position = at
	fighter.rotation.y = yaw
	world.add_child(fighter)
	fighter.set_physics_process(false)
	drive(fighter, command(fighter), 3)
	return fighter


## The yaw that faces from `from` toward `to`.
static func yaw_toward(from: Vector3, to: Vector3) -> float:
	return CombatRules.dir_to_yaw(to - from)


static func spell(id: StringName) -> SpellData:
	return GameData.spells[id]


# --- driving fighters ----------------------------------------------------------

## One tick of intent: `held` buttons held, `pressed` pressed this tick, the
## crosshair on `target`, facing where the fighter already faces.
func command(fighter: Fighter, held := 0, pressed := 0, target := Vector3.ZERO) -> InputCommand:
	var cmd := InputCommand.new()
	cmd.held = held | pressed
	cmd.pressed = pressed
	cmd.aim_yaw = fighter.state.facing_yaw
	cmd.aim_target = target
	return cmd


## Runs `fighter` for `count` fixed ticks of `cmd`; a press only counts on
## its first tick.
func drive(fighter: Fighter, cmd: InputCommand, count := 1) -> void:
	for i in count:
		fighter.simulate(cmd, DT)
		cmd.pressed = 0


## Like drive(), but inside real physics frames, for tests that measure
## distance (move_and_slide() takes its delta from the engine).
func drive_physics(fighter: Fighter, cmd: InputCommand, count := 1) -> void:
	for i in count:
		await get_tree().physics_frame
		fighter.simulate(cmd, get_physics_process_delta_time())
		cmd.pressed = 0


# --- spells in flight ----------------------------------------------------------

## A projectile of `spell` from `caster`, at `origin`, flying at `velocity`.
## It waits for step().
func add_projectile(caster: Fighter, data: ProjectileSpell, origin: Vector3, velocity: Vector3) -> Projectile:
	var projectile := Projectile.new()
	projectile.setup(caster, data, origin, velocity)
	world.add_child(projectile)
	projectile.set_physics_process(false)
	return projectile


## Spell nodes in play: projectiles plus zones (Flame Walls, Lightning Strikes).
func spell_nodes() -> Array[Node]:
	var out: Array[Node] = []
	for group in [&"projectiles", &"zones"]:
		for node in get_tree().get_nodes_in_group(group):
			if alive(node):
				out.append(node)
	return out


## Spell nodes that appeared since `before` (a spell_nodes() snapshot), with
## their physics ticks switched off so they wait for step().
func adopt_new(before: Array[Node]) -> Array[Node]:
	var spawned: Array[Node] = []
	for node in spell_nodes():
		if not before.has(node):
			node.set_physics_process(false)
			spawned.append(node)
	return spawned


## Releases `spell` from `caster` toward `target` the way a cast's release
## does (no wind-up), and returns what it spawned, waiting for step().
func release(caster: Fighter, data: SpellData, target: Vector3) -> Array[Node]:
	var before := spell_nodes()
	data.release(caster, target)
	return adopt_new(before)


## Whether a spell node is still in play (not freed and not about to be).
static func alive(node: Variant) -> bool:
	return is_instance_valid(node) and not (node as Node).is_queued_for_deletion()


## Steps `nodes` (spell nodes) together for `count` physics ticks.
func step(nodes: Array, count := 1) -> void:
	for i in count:
		for node in nodes:
			if alive(node):
				node._physics_process(DT)


## Steps `node` until it ends, at most `max_ticks`; returns the ticks it took.
func step_until_gone(node: Node, max_ticks := 600) -> int:
	for tick in max_ticks:
		if not alive(node):
			return tick
		node._physics_process(DT)
	return max_ticks


## Ticks needed to cover `seconds`.
static func ticks(seconds: float) -> int:
	return ceili(seconds / DT - 0.001)


# --- reading what happened -----------------------------------------------------

## The recorded hits on `target`.
func hits_on(target: Fighter) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for hit in hits:
		if hit.target == target:
			out.append(hit)
	return out


## The result of the last hit on `target`, or null.
func last_result(target: Fighter) -> HitResult:
	var on := hits_on(target)
	return on[-1].result if not on.is_empty() else null


## How fast and which way a fighter is being shoved, flat.
static func shove(fighter: Fighter) -> Vector3:
	return fighter.state.knockback
