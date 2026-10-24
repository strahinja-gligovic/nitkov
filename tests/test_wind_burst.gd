extends "res://tests/spell_world_test.gd"
## WindBurst, where a Wind Spear lands: everyone in reach is blown away from
## the centre (full strength at the centre, half at the edge) and popped up.
## Enemies take the burst damage (half for the one the spear struck); the
## caster and allies are only moved; guards facing the burst block it; enemy
## projectiles in it are blown off course.

const AT := Vector3(0.0, 1.3, -10.0)

var caster: Fighter
var spear: ProjectileSpell


func before_each() -> void:
	super()
	caster = add_fighter(Vector3.ZERO, 0)
	spear = spell(&"wind_spear") as ProjectileSpell


## Someone on `team` standing `offset` (flat) from the spot under the burst,
## facing it.
func _stand(offset: Vector3, team := 1) -> Fighter:
	var at := Vector3(AT.x, 0.0, AT.z) + offset
	return add_fighter(at, team, yaw_toward(at, AT) if offset.length() > 0.01 else 0.0)


## Bursts `burst` (a Wind Spear) thrown by the caster at `at`, flying -Z, as
## if it had just struck `struck` there.
func _blast(burst: ProjectileSpell, at: Vector3, struck: Fighter) -> void:
	var thrown := add_projectile(caster, burst, at, Vector3.FORWARD * burst.speed)
	WindBurst.blast(thrown, at, Vector3.UP, struck)


## The flat direction from the burst at `at` out to `fighter`.
static func _away(fighter: Fighter, at := AT) -> Vector3:
	return Vector3(fighter.global_position.x - at.x, 0.0, fighter.global_position.z - at.z).normalized()


func test_enemies_are_blown_away_from_the_centre_with_falloff() -> void:
	var near := _stand(Vector3(1.0, 0.0, 0.0))
	var far := _stand(Vector3(0.0, 0.0, 3.5))
	var beyond := _stand(Vector3(-(spear.burst_radius + Fighter.RADIUS + 0.6), 0.0, 0.0))
	_blast(spear, AT, null)
	for foe: Fighter in [near, far]:
		assert_almost_eq(foe.state.knockback.normalized().dot(_away(foe)), 1.0, 0.0001, "straight away from the burst")
		assert_eq(foe.state.knockback.y, 0.0, "the shove is flat; the pop is separate")
		assert_between(foe.state.knockback.length(), spear.burst_push * 0.5, spear.burst_push)
		assert_between(foe.state.launch, spear.burst_launch * 0.5, spear.burst_launch, "and off its feet")
	assert_gt(near.state.knockback.length(), far.state.knockback.length() + 2.0, "much harder near the centre")
	assert_gt(near.state.launch, far.state.launch)
	assert_eq(beyond.state.knockback, Vector3.ZERO, "out of reach")
	assert_eq(beyond.state.launch, 0.0)
	assert_eq(hits_on(beyond).size(), 0)


func test_full_strength_at_the_centre_and_half_at_the_edge() -> void:
	var centre := _stand(Vector3.ZERO)
	var edge := _stand(Vector3(spear.burst_radius + Fighter.RADIUS - 0.1, 0.0, 0.0))
	_blast(spear, centre.global_position + Vector3.UP * 0.9, null)
	assert_between(centre.state.knockback.length(), spear.burst_push * 0.95, spear.burst_push, "full strength")
	assert_almost_eq(centre.state.knockback.normalized().dot(Vector3.FORWARD), 1.0, 0.0001,
			"dead centre: blown on the way the spear flew")
	assert_between(centre.state.launch, spear.burst_launch * 0.95, spear.burst_launch)
	assert_eq(hits_on(edge).size(), 1, "a body overlapping the edge is in reach")
	assert_almost_eq(edge.state.knockback.length(), spear.burst_push * 0.5, 0.0001, "half strength at the edge")
	assert_almost_eq(edge.state.launch, spear.burst_launch * 0.5, 0.0001)


func test_enemies_take_the_burst_damage_and_the_struck_one_half() -> void:
	var struck := _stand(Vector3(0.6, 0.0, 0.0))
	var bystander := _stand(Vector3(-1.5, 0.0, 0.0))
	_blast(spear, AT, struck)
	assert_almost_eq(struck.state.hp, struck.state.max_hp - spear.burst_damage * 0.5, 0.001,
			"the spear already hit this one")
	assert_almost_eq(bystander.state.hp, bystander.state.max_hp - spear.burst_damage, 0.001)
	assert_eq(hits.size(), 2)
	for hit in hits:
		var result: HitResult = hit.result
		assert_eq(result.outcome, HitResult.Outcome.HIT)
		assert_eq(result.element, SpellData.Element.WIND)
		assert_eq(result.source, spear.id)
		assert_eq(hit.attacker, caster, "credited to the caster")


func test_the_caster_and_allies_are_blown_away_unharmed() -> void:
	var at := Vector3(0.0, 1.3, -1.5)  # the spear bursts right in front of its thrower
	var ally := add_fighter(Vector3(1.5, 0.0, -1.5), caster.team)
	_blast(spear, at, null)
	assert_almost_eq(caster.state.knockback.normalized().dot(_away(caster, at)), 1.0, 0.0001, "flung back clear")
	assert_between(caster.state.knockback.length(), spear.burst_push * 0.5, spear.burst_push)
	assert_gt(caster.state.launch, 0.0)
	assert_almost_eq(ally.state.knockback.normalized().dot(_away(ally, at)), 1.0, 0.0001, "allies are blown away too")
	assert_gt(ally.state.launch, 0.0)
	assert_eq(caster.state.hp, caster.state.max_hp, "but not hurt")
	assert_eq(ally.state.hp, ally.state.max_hp)
	assert_eq(hits.size(), 0, "and nothing to report")


func test_a_burst_that_leaves_friends_alone_does() -> void:
	var calm := spear.duplicate() as ProjectileSpell
	calm.burst_moves_allies = false
	var ally := _stand(Vector3(1.0, 0.0, 0.0), caster.team)
	var foe := _stand(Vector3(-1.0, 0.0, 0.0))
	_blast(calm, AT, null)
	assert_eq(ally.state.knockback, Vector3.ZERO)
	assert_eq(ally.state.launch, 0.0)
	assert_gt(foe.state.knockback.length(), 0.0, "enemies are still blown away")


func test_a_guard_facing_the_burst_blocks_it() -> void:
	# Facing the burst is what counts, not facing whoever threw the spear:
	# this guard stands between the two with its back to the thrower.
	var guard := _stand(Vector3(0.0, 0.0, 1.5))
	var at := Vector3(AT.x, 0.0, AT.z) + Vector3(1.5, 0.0, 0.0)
	var turned := add_fighter(at, 1, yaw_toward(Vector3(AT.x, 0.0, AT.z), at))  # back to the burst
	for fighter: Fighter in [guard, turned]:
		drive(fighter, command(fighter, InputCommand.BLOCK))
		assert_true(fighter.state.blocking)
	_blast(spear, AT, null)
	var blocked := last_result(guard)
	assert_eq(blocked.outcome, HitResult.Outcome.BLOCKED, "a guard facing the burst blocks it")
	assert_almost_eq(guard.state.hp, guard.state.max_hp - spear.burst_damage * tuning.spell_block_chip, 0.001, "chip only")
	assert_almost_eq(guard.state.stamina, guard.state.max_stamina - tuning.spell_block_stamina, 0.001)
	assert_eq(guard.state.action, FighterState.Action.IDLE, "no stagger")
	assert_eq(guard.state.launch, 0.0, "a guard keeps its feet")
	assert_eq(last_result(turned).outcome, HitResult.Outcome.HIT, "a guard facing away doesn't")
	assert_almost_eq(turned.state.hp, turned.state.max_hp - spear.burst_damage, 0.001)
	assert_gt(turned.state.launch, 0.0)
	assert_almost_eq(guard.state.knockback.length(), turned.state.knockback.length() * 0.5, 0.01,
			"the guard is pushed half as hard")
	assert_almost_eq(guard.state.knockback.normalized().dot(_away(guard)), 1.0, 0.0001)


func test_dodging_and_dead_fighters_are_untouched() -> void:
	var dodging := _stand(Vector3(1.0, 0.0, 0.0))
	dodging.state.invulnerable = 0.2
	var dead := _stand(Vector3(-1.0, 0.0, 0.0))
	dead.state.take_damage(1000.0)
	_blast(spear, AT, null)
	for fighter: Fighter in [dodging, dead]:
		assert_eq(fighter.state.knockback, Vector3.ZERO)
		assert_eq(fighter.state.launch, 0.0)
		assert_eq(hits_on(fighter).size(), 0)
	assert_eq(dodging.state.hp, dodging.state.max_hp, "i-frames dodge the burst")


func test_enemy_projectiles_are_blown_off_course_but_not_your_own() -> void:
	var foe := add_fighter(Vector3(0.0, 0.0, -24.0), 1, PI)
	var firebolt := spell(&"firebolt") as ProjectileSpell
	var theirs := add_projectile(foe, firebolt, AT + Vector3(2.0, 0.0, 0.0), Vector3.BACK * firebolt.speed)
	var mine := add_projectile(caster, firebolt, AT + Vector3(-2.0, 0.0, 0.0), Vector3.FORWARD * firebolt.speed)
	var out_of_reach := add_projectile(foe, firebolt, AT + Vector3(0.0, 0.0, -(spear.burst_radius + 1.0)),
			Vector3.BACK * firebolt.speed)
	_blast(spear, AT, null)
	assert_almost_eq(theirs.velocity, Vector3.RIGHT * firebolt.speed, Vector3.ONE * 0.001,
			"an enemy bolt in the burst is blown away from it, at the same speed")
	assert_almost_eq(-theirs.global_basis.z, Vector3.RIGHT, Vector3.ONE * 0.001, "and turned to face its new course")
	assert_eq(mine.velocity, Vector3.FORWARD * firebolt.speed, "your own spells fly on")
	assert_eq(out_of_reach.velocity, Vector3.BACK * firebolt.speed, "and so do bolts outside the burst")
