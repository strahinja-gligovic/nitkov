class_name UiIcons
extends RefCounted
## Procedural comic icons for every spell and rune, drawn with CanvasItem
## calls (no image assets): chunky shapes in hard-edged bands of the element's
## color around a white-hot core, inside a bold ink outline. Each spell has its
## own silhouette, so it reads at a glance even without its color.
##
## Shapes are designed in a unit box, fitted to the requested pixel size once
## and cached, so drawing an icon every frame only replays polygons.

const INK := Color(0.06, 0.03, 0.09)
## Runes have no element; they share the menu's violet.
const RUNE_COLOR := Color(0.8, 0.65, 1.0)

enum Tone { SHADE, BASE, LIGHT, CORE, CLOUD, CLOUD_LIGHT }
## How a shape is outlined: not at all, in the first pass (so the ink rings
## the whole silhouette), or right before the shape itself (an ink line
## separating it from the shapes under it).
enum Ink { NONE, SILHOUETTE, OVER }

## "<id>@<size>" -> Array of shapes fitted to that size (see _fit).
static var _cache := {}


## Draws the icon for a spell or rune id, centred at `center` and fitting a
## `size`-pixel square. `dim` (0..1) greys it out (unaffordable, cooling down);
## `zoom` scales it about its centre (pops and presses).
static func draw(canvas: CanvasItem, id: StringName, center: Vector2, size: float, dim := 0.0, zoom := 1.0) -> void:
	var key := "%s@%d" % [id, roundi(size)]
	if not _cache.has(key):
		_cache[key] = _fit(_design(id), size)
	var shapes: Array = _cache[key]
	var colors := palette(element_of(id))
	canvas.draw_set_transform(center, 0.0, Vector2(zoom, zoom))
	for shape: Dictionary in shapes:
		if shape.ink == Ink.SILHOUETTE:
			_draw_ink(canvas, shape)
	for shape: Dictionary in shapes:
		if shape.ink == Ink.OVER:
			_draw_ink(canvas, shape)
		var color := colors[shape.tone]
		if dim > 0.0:
			var grey := color.get_luminance() * 0.55
			color = color.lerp(Color(grey, grey, grey * 1.1), dim)
		canvas.draw_colored_polygon(shape.points, color)
		canvas.draw_polyline(shape.closed, color, 1.0, true)  # feathered edge
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)


## The element an id belongs to (NONE for runes and unknown ids).
static func element_of(id: StringName) -> SpellData.Element:
	var spell: SpellData = GameData.spells.get(id)
	return spell.element if spell else SpellData.Element.NONE


## The main color of an id's icon: its element's color, or the rune violet.
static func accent_of(id: StringName) -> Color:
	var element := element_of(id)
	return RUNE_COLOR if element == SpellData.Element.NONE else SpellData.element_color(element)


## Hard-edged color bands per element, indexed by Tone: a dark rim, the
## element's own color, a hot light band and a white-hot core (plus storm
## cloud greys). The light bands shift hue the way the element would glow.
static func palette(element: SpellData.Element) -> PackedColorArray:
	var base := SpellData.element_color(element)
	var cloud := Color(0.27, 0.22, 0.4)
	var cloud_light := Color(0.5, 0.43, 0.66)
	match element:
		SpellData.Element.FIRE:
			return PackedColorArray([Color(0.66, 0.13, 0.06), base, Color(1.0, 0.78, 0.24), Color(1.0, 0.98, 0.8), cloud, cloud_light])
		SpellData.Element.FROST:
			return PackedColorArray([Color(0.13, 0.38, 0.7), base, Color(0.74, 0.95, 1.0), Color(0.98, 1.0, 1.0), cloud, cloud_light])
		SpellData.Element.LIGHTNING:
			return PackedColorArray([Color(0.78, 0.47, 0.05), base, Color(1.0, 0.97, 0.66), Color(1.0, 1.0, 1.0), cloud, cloud_light])
		SpellData.Element.WIND:
			return PackedColorArray([Color(0.1, 0.5, 0.46), base, Color(0.84, 1.0, 0.91), Color(1.0, 1.0, 1.0), cloud, cloud_light])
	return PackedColorArray([Color(0.4, 0.26, 0.68), RUNE_COLOR, Color(0.93, 0.87, 1.0), Color(1.0, 1.0, 1.0), cloud, cloud_light])


static func _draw_ink(canvas: CanvasItem, shape: Dictionary) -> void:
	for outline: PackedVector2Array in shape.ink_points:
		canvas.draw_colored_polygon(outline, INK)
		var closed := outline.duplicate()
		closed.append(outline[0])
		canvas.draw_polyline(closed, INK, 1.0, true)


# --- fitting ----------------------------------------------------------------------

## Scales a design (unit-box shapes) to fill a `size`-pixel square, leaving
## room for the ink, and precomputes the ink outlines and closed edges.
static func _fit(design: Array, size: float) -> Array:
	var ink := clampf(size * 0.045, 1.5, 3.5)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for shape: Dictionary in design:
		for p: Vector2 in shape.points:
			lo = lo.min(p)
			hi = hi.max(p)
	var middle := (lo + hi) * 0.5
	var scale := (size - 2.0 * ink - 2.0) / maxf(hi.x - lo.x, hi.y - lo.y)
	var out: Array = []
	for shape: Dictionary in design:
		var points := PackedVector2Array()
		for p: Vector2 in shape.points:
			points.append((p - middle) * scale)
		var closed := points.duplicate()
		closed.append(points[0])
		# growing a shape can close a narrow gap into a hole; inking it is fine
		var ink_points: Array = Geometry2D.offset_polygon(points, ink, Geometry2D.JOIN_ROUND) if shape.ink != Ink.NONE else []
		out.append({points = points, closed = closed, tone = shape.tone, ink = shape.ink, ink_points = ink_points})
	return out


static func _shape(points: PackedVector2Array, tone: Tone, ink := Ink.NONE) -> Dictionary:
	return {points = points, tone = tone, ink = ink}


# --- designs (unit box, y down) ------------------------------------------------------

static func _design(id: StringName) -> Array:
	match id:
		&"firebolt":
			return _fireball()
		&"flame_wall":
			return _flame_wall()
		&"ice_spike":
			return _ice_spike()
		&"frost_nova":
			return _frost_nova()
		&"lightning_bolt":
			return _lightning_bolt()
		&"lightning_strike":
			return _lightning_strike()
		&"wind_slash":
			return _wind_slash()
		&"wind_spear":
			return _wind_spear()
		&"leap":
			return _leap()
		&"blink":
			return _blink()
	return _orb()


## A fireball streaking up and to the right, its tail breaking into three
## flame tongues, in bands from a red rim to a white-hot heart.
static func _fireball() -> Array:
	var d := Vector2(1.0, -1.0).normalized()
	var c := Vector2(0.18, -0.18)
	return [
		_shape(_comet(c, d, 0.5, 1.2), Tone.SHADE, Ink.SILHOUETTE),
		_shape(_comet(c + d * 0.07, d, 0.38, 0.86), Tone.BASE),
		_shape(_comet(c + d * 0.13, d, 0.25, 0.5), Tone.LIGHT),
		_shape(_circle(c + d * 0.17, 0.12), Tone.CORE),
		_shape(_circle(c - d * 1.02 + Vector2(-d.y, d.x) * 0.5, 0.07), Tone.BASE, Ink.SILHOUETTE),
		_shape(_circle(c - d * 0.98 - Vector2(-d.y, d.x) * 0.62, 0.05), Tone.LIGHT, Ink.SILHOUETTE),
	]


## A low wall of five flames on a burning strip of ground.
static func _flame_wall() -> Array:
	var xs := [-0.76, -0.38, 0.0, 0.38, 0.76]
	var outer := _flame_row(xs, [-0.08, -0.5, -0.95, -0.45, -0.02], 0.2, -0.98, 0.98, 0.55, 0.19)
	var middle := _flame_row(xs, [0.12, -0.2, -0.56, -0.16, 0.16], 0.3, -0.86, 0.86, 0.55, 0.13)
	var inner := _flame_row(xs, [0.33, 0.12, -0.18, 0.14, 0.36], 0.4, -0.7, 0.7, 0.55, 0.08)
	var ground := _round_rect(Rect2(-1.0, 0.46, 2.0, 0.24), 0.1)
	return [
		_shape(outer, Tone.SHADE, Ink.SILHOUETTE),
		_shape(middle, Tone.BASE),
		_shape(inner, Tone.LIGHT),
		_shape(ground, Tone.SHADE, Ink.OVER),
		_shape(_round_rect(Rect2(-0.86, 0.5, 1.72, 0.07), 0.035), Tone.LIGHT),
	]


## One icicle flying up and to the right: thick at the back where it broke
## off (a jagged crown of crystal points), tapering to a needle tip, with
## frost glints.
static func _ice_spike() -> Array:
	var tail := Vector2(-0.74, 0.74)
	var tip := Vector2(0.9, -0.9)
	var a := (tip - tail).normalized()
	var n := Vector2(-a.y, a.x)
	var length := tail.distance_to(tip)
	var at := func(u: float, v: float) -> Vector2: return tail + a * u * length + n * v
	var outline := PackedVector2Array([tip, at.call(0.55, -0.2), at.call(0.14, -0.34), at.call(-0.04, -0.3),
			at.call(0.04, -0.15), at.call(-0.1, -0.04), at.call(0.03, 0.08), at.call(-0.05, 0.24),
			at.call(0.14, 0.34), at.call(0.55, 0.2)])
	var lit := PackedVector2Array([tip, at.call(0.55, -0.2), at.call(0.14, -0.34), at.call(-0.04, -0.3),
			at.call(0.04, -0.15), at.call(0.2, -0.04), at.call(0.6, -0.02)])
	var dark := PackedVector2Array([tip, at.call(0.55, 0.2), at.call(0.14, 0.34), at.call(-0.05, 0.24),
			at.call(0.03, 0.08), at.call(0.22, 0.06), at.call(0.62, 0.05)])
	var glint := PackedVector2Array([at.call(0.9, -0.04), at.call(0.55, -0.13), at.call(0.24, -0.2),
			at.call(0.3, -0.1), at.call(0.6, -0.06)])
	return [
		_shape(outline, Tone.BASE, Ink.SILHOUETTE),
		_shape(lit, Tone.LIGHT),
		_shape(dark, Tone.SHADE),
		_shape(glint, Tone.CORE),
		_shape(_star(Vector2(-0.5, -0.42), 0.26, 0.07, 4, 0.0), Tone.CORE, Ink.SILHOUETTE),
		_shape(_star(Vector2(0.5, 0.5), 0.17, 0.05, 4, 0.0), Tone.LIGHT, Ink.SILHOUETTE),
	]


## A burst of ice shards flung out in every direction from a crystal core,
## with a ring of cold between them.
static func _frost_nova() -> Array:
	var shapes: Array = []
	for i in 4:
		var start := deg_to_rad(90.0 * i + 12.0)
		shapes.append(_shape(_arc_band(Vector2.ZERO, 0.62, 0.07, start, start + deg_to_rad(66.0)), Tone.LIGHT, Ink.SILHOUETTE))
	for i in 8:
		var angle := TAU * i / 8.0 - PI * 0.5
		var long := i % 2 == 0
		var dir := Vector2.from_angle(angle)
		var side := Vector2(-dir.y, dir.x)
		var root := dir * 0.2
		var tip := dir * (1.0 if long else 0.66)
		var mid := dir * (0.5 if long else 0.4)
		var width := 0.15 if long else 0.11
		shapes.append(_shape(PackedVector2Array([root + side * 0.05, mid + side * width, tip, mid - side * width, root - side * 0.05]),
				Tone.BASE, Ink.SILHOUETTE))
		shapes.append(_shape(PackedVector2Array([root, mid + side * width, tip, mid + side * width * 0.15]), Tone.LIGHT))
	shapes.append(_shape(_star(Vector2.ZERO, 0.3, 0.17, 6, PI / 6.0), Tone.LIGHT, Ink.OVER))
	shapes.append(_shape(_circle(Vector2.ZERO, 0.11, 12), Tone.CORE))
	return shapes


## A jagged bolt cracking across from left to right, with one forked branch.
static func _lightning_bolt() -> Array:
	var line := PackedVector2Array([Vector2(-0.98, 0.08), Vector2(-0.5, -0.24), Vector2(-0.2, 0.22),
			Vector2(0.18, -0.2), Vector2(0.44, 0.12), Vector2(0.98, -0.06)])
	var widths := PackedFloat32Array([0.07, 0.18, 0.2, 0.19, 0.14, 0.0])
	var fork := PackedVector2Array([Vector2(-0.24, 0.16), Vector2(-0.02, 0.5), Vector2(0.26, 0.44)])
	var fork_widths := PackedFloat32Array([0.09, 0.07, 0.0])
	return [
		_shape(_band(fork, fork_widths), Tone.BASE, Ink.SILHOUETTE),
		_shape(_band(line, widths), Tone.BASE, Ink.SILHOUETTE),
		_shape(_band(fork, _scaled(fork_widths, 0.45)), Tone.LIGHT),
		_shape(_band(line, _scaled(widths, 0.62)), Tone.LIGHT),
		_shape(_band(line, _scaled(widths, 0.28)), Tone.CORE),
		_shape(_star(Vector2(0.62, -0.42), 0.16, 0.05, 4, 0.0), Tone.LIGHT, Ink.SILHOUETTE),
	]


## A storm cloud hurling a bolt down onto a burst at the ground.
static func _lightning_strike() -> Array:
	var cloud := _union([_circle(Vector2(-0.46, -0.5), 0.27), _circle(Vector2(-0.1, -0.68), 0.33),
			_circle(Vector2(0.3, -0.6), 0.29), _circle(Vector2(0.62, -0.44), 0.19),
			_round_rect(Rect2(-0.72, -0.56, 1.5, 0.3), 0.14)])
	var puff := _union([_circle(Vector2(-0.14, -0.74), 0.2), _circle(Vector2(0.24, -0.66), 0.16),
			_circle(Vector2(-0.46, -0.56), 0.14)])
	var bolt := PackedVector2Array([Vector2(0.06, -0.44), Vector2(-0.32, 0.14), Vector2(-0.06, 0.14),
			Vector2(-0.2, 0.86), Vector2(0.34, -0.02), Vector2(0.07, -0.02), Vector2(0.3, -0.44)])
	return [
		_shape(_star(Vector2(-0.2, 0.84), 0.34, 0.14, 8, 0.2), Tone.LIGHT, Ink.SILHOUETTE),
		_shape(cloud, Tone.CLOUD, Ink.SILHOUETTE),
		_shape(puff, Tone.CLOUD_LIGHT),
		_shape(bolt, Tone.BASE, Ink.OVER),
		_shape(_shrink(bolt, 0.05), Tone.LIGHT),
		_shape(_shrink(bolt, 0.09), Tone.CORE),
	]


## A crescent of wind sliced through the air, trailing streaks.
static func _wind_slash() -> Array:
	var tilt := deg_to_rad(-18.0)
	var c := Vector2(-0.34, 0.0)
	var shapes: Array = []
	for streak in [[-0.42, 0.62], [0.02, 0.8], [0.44, 0.56]]:
		var y: float = streak[0]
		var length: float = streak[1]
		var line := PackedVector2Array([Vector2(-0.98, y), Vector2(-0.98 + length * 0.5, y), Vector2(-0.98 + length, y)])
		shapes.append(_shape(_rotated(_band(line, PackedFloat32Array([0.0, 0.06, 0.035])), tilt), Tone.LIGHT, Ink.SILHOUETTE))
	shapes.append(_shape(_rotated(_crescent(c, 1.0, 0.44, -64.0, 64.0), tilt), Tone.BASE, Ink.SILHOUETTE))
	shapes.append(_shape(_rotated(_crescent(c, 1.0, 0.24, -58.0, 58.0), tilt), Tone.LIGHT))
	shapes.append(_shape(_rotated(_crescent(c, 1.0, 0.08, -46.0, 46.0), tilt), Tone.CORE))
	shapes.append(_shape(_rotated(_crescent(c, 0.72, 0.1, -40.0, 40.0), tilt), Tone.SHADE))
	return shapes


## A spear of storm wind flying up and to the right, wrapped in a gale.
static func _wind_spear() -> Array:
	var tail := Vector2(-0.9, 0.9)
	var tip := Vector2(0.92, -0.92)
	var a := (tip - tail).normalized()
	var n := Vector2(-a.y, a.x)
	var head_base := tip - a * 0.86
	var shaft := _band(PackedVector2Array([tail, head_base + a * 0.1]), PackedFloat32Array([0.07, 0.085]))
	var head := PackedVector2Array()
	_bezier(head, head_base, head_base + a * 0.22 + n * 0.44, tip, 8, false)
	_bezier(head, tip, head_base + a * 0.22 - n * 0.44, head_base, 8)
	head.remove_at(head.size() - 1)
	var head_lit := PackedVector2Array()
	_bezier(head_lit, head_base + a * 0.06, head_base + a * 0.22 + n * 0.28, tip - a * 0.04, 8, false)
	head_lit.append(head_base + a * 0.3)
	var shapes: Array = [
		_shape(shaft, Tone.SHADE, Ink.SILHOUETTE),
		_shape(head, Tone.BASE, Ink.SILHOUETTE),
		_shape(head_lit, Tone.LIGHT),
		_shape(_band(PackedVector2Array([head_base + a * 0.16, tip - a * 0.08]), PackedFloat32Array([0.03, 0.0])), Tone.CORE),
		_shape(_star(head_base, 0.13, 0.07, 4, PI * 0.25), Tone.LIGHT, Ink.OVER),
	]
	for at in [0.28, 0.56]:
		var centre: Vector2 = tail.lerp(head_base, at)
		shapes.append(_shape(_swirl(centre, a, n, 0.34, 0.13), Tone.LIGHT, Ink.OVER))
	return shapes


## Two chevrons leaping upward.
static func _leap() -> Array:
	var shapes: Array = []
	for k in 2:
		var y := 0.36 - k * 0.62
		var line := PackedVector2Array([Vector2(-0.7, y + 0.34), Vector2(0.0, y - 0.32), Vector2(0.7, y + 0.34)])
		var widths := PackedFloat32Array([0.16, 0.17, 0.16])
		shapes.append(_shape(_band(line, widths), Tone.BASE if k == 1 else Tone.SHADE, Ink.SILHOUETTE))
		shapes.append(_shape(_band(line, _scaled(widths, 0.35)), Tone.CORE if k == 1 else Tone.LIGHT))
	return shapes


## A chevron blinking forward out of a trail of fading dots.
static func _blink() -> Array:
	var line := PackedVector2Array([Vector2(0.02, -0.66), Vector2(0.64, 0.0), Vector2(0.02, 0.66)])
	var widths := PackedFloat32Array([0.17, 0.18, 0.17])
	return [
		_shape(_circle(Vector2(-0.32, 0.0), 0.15), Tone.BASE, Ink.SILHOUETTE),
		_shape(_circle(Vector2(-0.66, 0.0), 0.11), Tone.SHADE, Ink.SILHOUETTE),
		_shape(_circle(Vector2(-0.92, 0.0), 0.07), Tone.SHADE, Ink.SILHOUETTE),
		_shape(_band(line, widths), Tone.BASE, Ink.SILHOUETTE),
		_shape(_band(line, _scaled(widths, 0.35)), Tone.CORE),
		_shape(_star(Vector2(0.78, -0.62), 0.24, 0.07, 4, 0.0), Tone.CORE, Ink.SILHOUETTE),
	]


## Anything without its own design: a glowing orb.
static func _orb() -> Array:
	return [
		_shape(_circle(Vector2.ZERO, 0.8), Tone.SHADE, Ink.SILHOUETTE),
		_shape(_circle(Vector2(-0.06, -0.06), 0.62), Tone.BASE),
		_shape(_circle(Vector2(-0.16, -0.16), 0.36), Tone.LIGHT),
		_shape(_circle(Vector2(-0.22, -0.22), 0.14), Tone.CORE),
	]


# --- geometry -------------------------------------------------------------------------

static func _circle(c: Vector2, r: float, steps := 20) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in steps:
		out.append(c + Vector2.from_angle(TAU * i / steps) * r)
	return out


static func _star(c: Vector2, outer: float, inner: float, points: int, turn: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in points * 2:
		var r := outer if i % 2 == 0 else inner
		out.append(c + Vector2.from_angle(turn - PI * 0.5 + PI * i / points) * r)
	return out


static func _round_rect(rect: Rect2, radius: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var corners := [rect.position + Vector2(rect.size.x - radius, radius), rect.end - Vector2(radius, radius),
			rect.position + Vector2(radius, rect.size.y - radius), rect.position + Vector2(radius, radius)]
	for k in 4:
		for i in 5:
			out.append(corners[k] + Vector2.from_angle(-PI * 0.5 + PI * 0.5 * k + PI * 0.125 * i) * radius)
	return out


## Appends a quadratic Bezier from `a` to `b` (without `a` when `skip_start`,
## so consecutive curves don't repeat their shared point).
static func _bezier(out: PackedVector2Array, a: Vector2, control: Vector2, b: Vector2, steps: int, skip_start := true) -> void:
	for i in range(1 if skip_start else 0, steps + 1):
		var t := float(i) / steps
		out.append(a.lerp(control, t).lerp(control.lerp(b, t), t))


## A ribbon along `line`, `widths` (half-widths) per point; zero makes a point.
static func _band(line: PackedVector2Array, widths: PackedFloat32Array) -> PackedVector2Array:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in line.size():
		var before := (line[i] - line[i - 1]).normalized() if i > 0 else Vector2.ZERO
		var after := (line[i + 1] - line[i]).normalized() if i < line.size() - 1 else Vector2.ZERO
		var along := (before + after).normalized()
		if along == Vector2.ZERO:
			along = before if before != Vector2.ZERO else after
		var normal := Vector2(-along.y, along.x)
		var reference := Vector2(-before.y, before.x) if before != Vector2.ZERO else normal
		var miter := widths[i] / maxf(absf(normal.dot(reference)), 0.5)
		if widths[i] <= 0.0:
			left.append(line[i])
			continue
		left.append(line[i] + normal * miter)
		right.append(line[i] - normal * miter)
	right.reverse()
	left.append_array(right)
	return left


static func _scaled(widths: PackedFloat32Array, factor: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for w in widths:
		out.append(w * factor)
	return out


## A crescent bulging toward +X: its outer edge an arc of radius `r` about `c`
## from `from_deg` to `to_deg`, thickest (`thickness`) in the middle and
## tapering to points.
static func _crescent(c: Vector2, r: float, thickness: float, from_deg: float, to_deg: float, steps := 16) -> PackedVector2Array:
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for i in steps + 1:
		var t := float(i) / steps
		var dir := Vector2.from_angle(deg_to_rad(lerpf(from_deg, to_deg, t)))
		outer.append(c + dir * r)
		if i > 0 and i < steps:
			inner.append(c + dir * (r - thickness * sin(PI * t)))
	inner.reverse()
	outer.append_array(inner)
	return outer


## A ring segment `width` thick around radius `r`, between two angles.
static func _arc_band(c: Vector2, r: float, width: float, from: float, to: float, steps := 10) -> PackedVector2Array:
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for i in steps + 1:
		var dir := Vector2.from_angle(lerpf(from, to, float(i) / steps))
		outer.append(c + dir * (r + width * 0.5))
		inner.append(c + dir * (r - width * 0.5))
	inner.reverse()
	outer.append_array(inner)
	return outer


## A tapering loop of wind around an axis `a` (seen side-on: an ellipse
## `across` wide and `deep` along the axis, open on one side).
static func _swirl(c: Vector2, a: Vector2, n: Vector2, across: float, deep: float) -> PackedVector2Array:
	var line := PackedVector2Array()
	var widths := PackedFloat32Array()
	var steps := 12
	for i in steps + 1:
		var t := float(i) / steps
		var angle := lerpf(-PI * 0.15, PI * 1.25, t)
		line.append(c + n * cos(angle) * across + a * (sin(angle) * deep - t * 0.12))
		widths.append(0.055 * sin(PI * minf(t * 1.15, 1.0)) + 0.004)
	widths[steps] = 0.0
	return _band(line, widths)


static func _rotated(points: PackedVector2Array, angle: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		out.append(p.rotated(angle))
	return out


## The polygon pulled in by `amount` (a thinner copy for inner color bands).
static func _shrink(points: PackedVector2Array, amount: float) -> PackedVector2Array:
	var shrunk := Geometry2D.offset_polygon(points, -amount, Geometry2D.JOIN_MITER)
	return _largest(shrunk) if not shrunk.is_empty() else points


## The outline of several overlapping polygons merged into one.
static func _union(parts: Array) -> PackedVector2Array:
	var merged: PackedVector2Array = parts[0]
	for i in range(1, parts.size()):
		merged = _largest(Geometry2D.merge_polygons(merged, parts[i]))
	return merged


## The biggest of several polygons: the outer boundary of a merge, not a hole.
static func _largest(polygons: Array) -> PackedVector2Array:
	var best := PackedVector2Array()
	var best_area := -1.0
	for polygon: PackedVector2Array in polygons:
		var area := 0.0
		for i in polygon.size():
			area += polygon[i].cross(polygon[(i + 1) % polygon.size()])
		if absf(area) > best_area:
			best_area = absf(area)
			best = polygon
	return best


## A comet of flame flying along `d`: a round head of radius `r` and a tail
## `tail` long that splits into three tongues.
static func _comet(c: Vector2, d: Vector2, r: float, tail: float) -> PackedVector2Array:
	var p := Vector2(-d.y, d.x)
	var at := func(u: float, v: float) -> Vector2: return c - d * u + p * v
	var out := PackedVector2Array()
	for i in 13:
		var angle := lerpf(-PI * 0.5, PI * 0.5, i / 12.0)
		out.append(c + (d * cos(angle) + p * sin(angle)) * r)
	var steps := 5
	_bezier(out, at.call(0.0, r), at.call(tail * 0.25, r * 1.08), at.call(tail * 0.64, r * 0.92), steps)
	_bezier(out, at.call(tail * 0.64, r * 0.92), at.call(tail * 0.46, r * 0.62), at.call(tail * 0.42, r * 0.36), steps)
	_bezier(out, at.call(tail * 0.42, r * 0.36), at.call(tail * 0.66, r * 0.3), at.call(tail, 0.0), steps)
	_bezier(out, at.call(tail, 0.0), at.call(tail * 0.7, -r * 0.2), at.call(tail * 0.44, -r * 0.36), steps)
	_bezier(out, at.call(tail * 0.44, -r * 0.36), at.call(tail * 0.56, -r * 0.6), at.call(tail * 0.72, -r * 0.88), steps)
	_bezier(out, at.call(tail * 0.72, -r * 0.88), at.call(tail * 0.3, -r * 1.08), at.call(0.0, -r), steps)
	out.remove_at(out.size() - 1)  # the head's first point closes the loop
	return out


## A row of flame tongues standing on the line y = `bottom`, tips at `tips`
## (y per tongue at `xs`), valleys dipping to `valley`, spanning `left`..`right`.
static func _flame_row(xs: Array, tips: Array, valley: float, left: float, right: float, bottom: float, width: float) -> PackedVector2Array:
	var out := PackedVector2Array([Vector2(left, bottom)])
	var from := Vector2(left, bottom)
	for i in xs.size():
		var tip := Vector2(xs[i] + width * 0.25, tips[i])
		_bezier(out, from, Vector2(xs[i] - width * 0.75, lerpf(from.y, tip.y, 0.55)), tip, 6)
		var to := Vector2(right, bottom) if i == xs.size() - 1 else Vector2((xs[i] + xs[i + 1]) * 0.5, valley)
		_bezier(out, tip, Vector2(xs[i] + width * 0.55, lerpf(tip.y, to.y, 0.35)), to, 6)
		from = to
	return out  # the closing edge runs along the bottom
