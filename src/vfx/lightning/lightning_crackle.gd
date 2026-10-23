class_name LightningCrackle
extends LightningArc
## Arcs that crackle for a moment and go out. Every `refresh` seconds the
## `shape` callback redraws them, so they re-randomize; the brightness pops
## in, holds, then flickers down; the node frees itself after `life` seconds.
## Impacts, releases, the strike's ground arcs and the charge all use it with
## their own shapes.

## Called as shape.call(arc, t) on each redraw (t = age / life, 0..1); it
## add()s the paths (clear() and commit() happen around it).
var shape: Callable
var life := 0.3
var refresh := 1.0 / 30.0
## Part of the life spent at full brightness before the fade.
var hold := 0.35
## How much the brightness may drop on a beat (0 steady .. 1 strobing).
var flicker := 0.4
var peak := 1.0
## Optional: envelope.call(age_seconds) -> brightness, replacing the
## hold-and-fade (strobes).
var envelope: Callable

var _age := 0.0
var _next := 0.0
var _beat_level := 1.0


static func spawn(parent: Node, shape_fn: Callable, life_seconds: float, tint := LightningFx.COLOR,
		inked := false) -> LightningCrackle:
	var crackle := LightningCrackle.new()
	crackle.style(inked, tint)
	crackle.shape = shape_fn
	crackle.life = life_seconds
	parent.add_child(crackle)
	crackle._redraw()
	crackle._apply_brightness()
	return crackle


func _process(delta: float) -> void:
	_age += delta
	if _age >= life:
		queue_free()
		return
	_next -= delta
	if _next <= 0.0:
		_next += refresh
		_redraw()
	_apply_brightness()


func _redraw() -> void:
	_beat_level = 1.0 - flicker * randf()
	clear()
	if shape.is_valid():
		shape.call(self, clampf(_age / life, 0.0, 1.0))
	commit()


func _apply_brightness() -> void:
	var level := peak * _beat_level
	if envelope.is_valid():
		level *= envelope.call(_age)
	else:
		var t := clampf(_age / life, 0.0, 1.0)
		if t > hold:
			level *= pow(1.0 - (t - hold) / (1.0 - hold), 1.4)
	set_brightness(level)
