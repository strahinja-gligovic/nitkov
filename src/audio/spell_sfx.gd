class_name SpellSfx
extends RefCounted
## How spells sound. SpellFx calls these next to each visual; every sound is
## cosmetic, frees itself, and reads nothing back. (Silent for now.)


## The wind-up in the casting hand (`hand` follows the gauntlet).
static func charge(_spell: SpellData, _hand: Node3D, _seconds: float) -> void:
	pass


## The spell leaving the hand at `at`.
static func release(_spell: SpellData, _world: Node, _at: Vector3) -> void:
	pass


## The flight: `look` is the projectile's body, which moves with it.
static func projectile(_spell: ProjectileSpell, _look: Node3D) -> void:
	pass


## The projectile is gone (its look may linger to fade its trail).
static func projectile_end(_look: Node3D) -> void:
	pass


## Where a projectile ends (`struck` a fighter; `fizzled` out of range). A
## Wind Spear bursts here.
static func impact(_spell: ProjectileSpell, _world: Node, _at: Vector3, _struck: bool, _fizzled: bool) -> void:
	pass


## The Flame Wall burning; `look` lives as long as the wall.
static func flame_wall(_spell: FlameWallSpell, _look: Node3D) -> void:
	pass


static func nova(_spell: NovaSpell, _world: Node, _at: Vector3) -> void:
	pass


## The strike's warning mark; `warning` is freed when the bolt lands.
static func strike_warning(_spell: LightningStrikeSpell, _warning: Node3D) -> void:
	pass


static func strike(_spell: LightningStrikeSpell, _world: Node, _at: Vector3) -> void:
	pass


static func shatter(_world: Node, _at: Vector3) -> void:
	pass


## A lightning stun on a fighter's body (`body` follows the fighter).
static func shock(_body: Node3D, _seconds: float) -> void:
	pass
