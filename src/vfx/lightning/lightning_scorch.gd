class_name LightningScorch
extends Decal
## A burn where lightning hit: a dark blot with a branching crack pattern (a
## Lichtenberg figure, the shape lightning leaves) whose cracks glow
## white-hot, cool through yellow and orange to dark red, while the whole
## mark fades over its life. The textures are drawn once, in code, and shared
## (skipped headless, where nothing is drawn).

const TEXTURE_SIZE := 256
const VARIANTS := 3
const BURN := Color(0.035, 0.02, 0.045)
## The cracks' colour as they cool: white-hot, yellow, orange, ember.
const HEAT_STEPS: Array[Color] = [Color(1.0, 0.97, 0.86), Color(1.0, 0.82, 0.3), Color(1.0, 0.47, 0.12),
		Color(0.75, 0.16, 0.06)]

static var _albedo: Array[Texture2D] = []
static var _glow: Array[Texture2D] = []
## [glow, char, blot] brush sets, made once.
static var _brushes: Array = []

var life := 3.0
## Seconds for the cracks to go dark.
var cool := 1.2
## Peak glow of the cracks.
var heat := 4.0
var _age := 0.0


## A scorch `size` metres across at `at` on the surface facing `normal`.
static func spawn(parent: Node, at: Vector3, normal: Vector3, size: float, life_seconds := 3.0,
		cool_seconds := 1.2, peak_heat := 4.0) -> LightningScorch:
	prepare()
	var scorch := LightningScorch.new()
	if not _albedo.is_empty():
		var variant := randi() % _albedo.size()
		scorch.texture_albedo = _albedo[variant]
		scorch.texture_emission = _glow[variant]
	scorch.size = Vector3(size, maxf(0.5, size * 0.2), size)
	scorch.upper_fade = 0.2
	scorch.lower_fade = 0.2
	scorch.normal_fade = 0.35
	scorch.albedo_mix = 1.0
	scorch.life = life_seconds
	scorch.cool = cool_seconds
	scorch.heat = peak_heat
	scorch.emission_energy = peak_heat
	scorch.modulate = HEAT_STEPS[0]
	parent.add_child(scorch)
	var up := normal.normalized() if normal.length() > 0.01 else Vector3.UP
	var basis := Basis(Quaternion(Vector3.UP, up)) * Basis(Vector3.UP, randf() * TAU)
	scorch.global_transform = Transform3D(basis, at)
	return scorch


func _process(delta: float) -> void:
	_age += delta
	if _age >= life:
		queue_free()
		return
	var t := clampf(_age / cool, 0.0, 1.0)
	var step := mini(int(t * HEAT_STEPS.size()), HEAT_STEPS.size() - 1)
	var color := HEAT_STEPS[step]
	emission_energy = heat * pow(1.0 - t, 1.6)
	var fade := clampf((life - _age) / (life * 0.45), 0.0, 1.0)
	modulate = Color(color.r, color.g, color.b, fade)


## Draws the next texture variant, if any are missing: one per call, so no
## single frame pays for them all (the warning calls it ahead of the strike).
static func prepare() -> void:
	if _albedo.size() >= VARIANTS or DisplayServer.get_name() == "headless":
		return
	if _brushes.is_empty():
		# crack brushes thinnest first; the char round a crack is a size wider
		_brushes = [
			[_brush(0, Color.WHITE, 1.0), _brush(1, Color.WHITE, 1.0), _brush(2, Color.WHITE, 1.0)],
			[_brush(1, BURN, 0.9), _brush(2, BURN, 0.9), _brush(3, BURN, 0.9)],
			[_brush(16, BURN, 0.32), _brush(26, BURN, 0.3), _brush(38, BURN, 0.28)],
		]
	var glow_brushes: Array = _brushes[0]
	var char_brushes: Array = _brushes[1]
	var blot_brushes: Array = _brushes[2]
	var burn := Image.create_empty(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	burn.fill(Color(BURN, 0.0))
	var glow := Image.create_empty(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	glow.fill(Color.BLACK)
	var centre := Vector2.ONE * TEXTURE_SIZE * 0.5
	# the blot: soft dark dabs heaped round the centre
	for i in 22:
		var at := centre + Vector2.from_angle(randf() * TAU) * randf_range(0.0, 0.16) * TEXTURE_SIZE
		_stamp(burn, blot_brushes[randi() % 3], at)
	_stamp(burn, blot_brushes[2], centre)
	# the figure: branches from the centre that fork as they go
	var branches := randi_range(6, 8)
	for b in branches:
		var angle := TAU * (b + randf_range(-0.3, 0.3)) / branches
		var reach := randf_range(0.36, 0.47) * TEXTURE_SIZE
		var tip := centre + Vector2.from_angle(angle) * reach
		var path := LightningArc.jagged(Vector3(centre.x, centre.y, 0.0), Vector3(tip.x, tip.y, 0.0), 6, 0.15,
				Vector3.BACK)
		_trace(burn, glow, path, char_brushes, glow_brushes, 2)
		for f in randi_range(2, 4):
			var fork := LightningArc.fork(path, reach * randf_range(0.2, 0.42), 0.9, 4, 0.22, Vector3.BACK,
					Vector2(0.2, 0.8))
			_trace(burn, glow, fork, char_brushes, glow_brushes, 1)
	burn.generate_mipmaps()
	glow.generate_mipmaps()
	_albedo.append(ImageTexture.create_from_image(burn))
	_glow.append(ImageTexture.create_from_image(glow))


## Draws a path into both images: char into the burn, light into the glow,
## thinning from `thickness` (a brush index) toward its end.
static func _trace(burn: Image, glow: Image, path: PackedVector3Array, char_brushes: Array,
		glow_brushes: Array, thickness: int) -> void:
	var last := path.size() - 1
	for i in last:
		var a := Vector2(path[i].x, path[i].y)
		var b := Vector2(path[i + 1].x, path[i + 1].y)
		var brush := clampi(thickness - int(float(thickness + 1) * i / last), 0, 2)
		var steps := maxi(1, int(a.distance_to(b)))
		for s in steps:
			var at := a.lerp(b, float(s) / steps)
			_stamp(burn, char_brushes[brush], at)
			_stamp(glow, glow_brushes[brush], at)


static func _stamp(image: Image, brush: Image, at: Vector2) -> void:
	var half := brush.get_width() / 2
	image.blend_rect(brush, Rect2i(Vector2i.ZERO, brush.get_size()), Vector2i(roundi(at.x) - half, roundi(at.y) - half))


## A round dab of `color`, `radius` pixels (0 is a single pixel), solid up to
## `opacity` in the middle and soft at the edge.
static func _brush(radius: int, color: Color, opacity: float) -> Image:
	var size := radius * 2 + 1
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var d := Vector2(x - radius, y - radius).length() / (radius + 0.5)
			var alpha := clampf((1.0 - d) * (2.0 if radius < 4 else 1.0), 0.0, 1.0)
			image.set_pixel(x, y, Color(color, alpha * opacity))
	return image
