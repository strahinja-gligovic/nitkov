class_name ScreenFx
extends CanvasLayer
## Full-screen feedback for the local player, between the 3D view and the HUD:
##   flash()   a brief wash of light (a bolt landing nearby, Shatter, a stun)
##   pulse()   a tinted vignette that swells and fades
##   warp()    a ring of refraction racing out from a point (a wind burst)
##   frost     ice crystals growing in from the edges (0..1; set every frame)
##   shock     electric arcs crackling along the edges (0..1; set every frame)
## All of it stays at the edges or is gone within a fraction of a second, so
## the middle of the screen stays readable. Presentation only, and both rects
## hide themselves when idle, so it costs nothing between big moments (the
## warp reads the screen, so it only runs for its own short life).

const OVERLAY_SHADER := preload("res://src/vfx/screen/screen_overlay.gdshader")
const WARP_SHADER := preload("res://src/vfx/screen/screen_warp.gdshader")
## Above the 3D view, below the HUD (layer 5).
const LAYER := 2
## Never more than this much of a flash, however many big moments stack.
const MAX_FLASH := 0.42
const MAX_PULSE := 0.75

## The steady edge looks (0..1), driven every frame by CombatFeedback.
var frost := 0.0
var shock := 0.0

var _overlay: ColorRect
var _overlay_material: ShaderMaterial
var _warp: ColorRect
var _warp_material: ShaderMaterial
var _time := 0.0
var _flash := 0.0
var _flash_fade := 8.0
var _flash_color := Color.WHITE
var _pulse := 0.0
var _pulse_age := 0.0
var _pulse_length := 0.4
var _pulse_color := Color.WHITE
var _warp_age := 1.0
var _warp_length := 0.4
var _warp_strength := 0.0
var _warp_centre := Vector2(0.5, 0.5)


func _ready() -> void:
	layer = LAYER
	_warp = _full_rect("Warp")
	_warp_material = ShaderMaterial.new()
	_warp_material.shader = WARP_SHADER
	_warp.material = _warp_material
	_overlay = _full_rect("Overlay")
	_overlay_material = ShaderMaterial.new()
	_overlay_material.shader = OVERLAY_SHADER
	_overlay.material = _overlay_material
	_refresh(0.0)


## A brief wash of `color`: `strength` 0..1 of the cap, fading over `seconds`
## in a couple of held beats.
func flash(color: Color, strength: float, seconds := 0.12) -> void:
	strength = clampf(strength, 0.0, 1.0) * MAX_FLASH
	if strength <= _flash:
		return
	_flash = strength
	_flash_color = color
	_flash_fade = strength / maxf(seconds, 0.03)


## A tinted vignette that swells in fast and fades out over `seconds`.
func pulse(color: Color, strength: float, seconds := 0.4) -> void:
	strength = clampf(strength, 0.0, 1.0) * MAX_PULSE
	if strength <= _pulse_level():
		return
	_pulse = strength
	_pulse_color = color
	_pulse_age = 0.0
	_pulse_length = maxf(seconds, 0.1)


## A refraction ring racing out from `screen_uv` (0..1 across the screen).
func warp(screen_uv: Vector2, strength: float, seconds := 0.4) -> void:
	strength = clampf(strength, 0.0, 1.0)
	if _warp_age < _warp_length and strength <= _warp_strength * (1.0 - _warp_age / _warp_length):
		return
	_warp_centre = screen_uv
	_warp_strength = strength
	_warp_age = 0.0
	_warp_length = maxf(seconds, 0.1)


func _process(delta: float) -> void:
	_refresh(delta)


func _pulse_level() -> float:
	if _pulse_age >= _pulse_length:
		return 0.0
	var swell := clampf(_pulse_age / 0.05, 0.0, 1.0)
	return _pulse * swell * pow(1.0 - _pulse_age / _pulse_length, 1.6)


func _refresh(delta: float) -> void:
	_time += delta
	_flash = maxf(_flash - _flash_fade * delta, 0.0)
	_pulse_age += delta
	_warp_age += delta
	var aspect := _aspect()
	# held beats: a flash steps down instead of gliding (hand-drawn timing)
	var flash := ceilf(_flash / MAX_FLASH * 3.0) / 3.0 * MAX_FLASH if _flash > 0.01 else 0.0
	var pulse := _pulse_level()
	var showing := flash > 0.0 or pulse > 0.005 or frost > 0.005 or shock > 0.005
	_overlay.visible = showing
	if showing:
		_overlay_material.set_shader_parameter(&"flash", flash)
		_overlay_material.set_shader_parameter(&"flash_color", _flash_color)
		_overlay_material.set_shader_parameter(&"pulse", pulse)
		_overlay_material.set_shader_parameter(&"pulse_color", _pulse_color)
		_overlay_material.set_shader_parameter(&"frost", clampf(frost, 0.0, 1.0))
		_overlay_material.set_shader_parameter(&"shock", clampf(shock, 0.0, 1.0))
		_overlay_material.set_shader_parameter(&"time", _time)
		_overlay_material.set_shader_parameter(&"aspect", aspect)
	var warping := _warp_age < _warp_length and _warp_strength > 0.01
	_warp.visible = warping
	if warping:
		_warp_material.set_shader_parameter(&"center", _warp_centre)
		_warp_material.set_shader_parameter(&"progress", _warp_age / _warp_length)
		_warp_material.set_shader_parameter(&"strength", _warp_strength)
		_warp_material.set_shader_parameter(&"aspect", aspect)


func _aspect() -> float:
	var size := get_viewport().get_visible_rect().size if get_viewport() else Vector2.ZERO
	return size.x / size.y if size.y > 0.0 else 16.0 / 9.0


func _full_rect(node_name: String) -> ColorRect:
	var rect := ColorRect.new()
	rect.name = node_name
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.color = Color.WHITE
	rect.visible = false
	add_child(rect)
	return rect
