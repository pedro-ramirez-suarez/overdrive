class_name ProcTexture
extends RefCounted
## Procedurally-built ground and road textures (SPEC.md §M6 polish).
##
## Built on value noise that TILES EXACTLY, because the world meshes carry no UVs
## — they are regenerated on every sculpt, so unwrapping them would be wasted work
## — and are textured triplanar from world position instead. Anything drawn here
## therefore repeats across the whole map, and a visible seam would repeat with
## it. FastNoiseLite is not used: it is neither periodic nor anisotropic, and
## anisotropy is exactly what makes grass read as strands rather than blobs.
##
## Textures are generated once and cached. Building them costs a moment of CPU on
## first use; they are small (256px) and every later caller gets the same object.

const SIZE := 256

## Meters of ground one tile of each texture covers. The material's uv1_scale is
## 1/this, so the numbers below are readable as real-world sizes.
const GRASS_METERS := 6.0
const ROAD_METERS := 3.0

## Bump when the generators below change, or the on-disk cache will serve the old
## texture forever.
const VERSION := 2
const CACHE_DIR := "user://texcache"

static var _grass: ImageTexture = null
static var _asphalt: ImageTexture = null


## Grass: a fine mottle with a slight grain direction.
##
## Deliberately only *slightly* directional. A photo of tall grass is strongly
## striated, but reproducing that at 8:1 with sharpened strands is wrong at this
## scale: seen from a chase camera the strands chain into smears metres long and
## the ground reads as brushed fur. Grass at driving distance is a fine mottle.
static func grass() -> ImageTexture:
	if _grass == null:
		_grass = _cached("grass", _build_grass)
	return _grass


## Asphalt: aggregate grain over patchy wear. Deliberately isotropic — road
## surfaces have no grain direction, and streaks would read as brushed metal.
static func asphalt() -> ImageTexture:
	if _asphalt == null:
		_asphalt = _cached("asphalt", _build_asphalt)
	return _asphalt


static func _build_grass() -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	for j in SIZE:
		var v: float = float(j) / float(SIZE)
		for i in SIZE:
			var u: float = float(i) / float(SIZE)
			# 96x48 lattice = tufts ~6 cm across and ~12 cm long: a 2:1 hint of grain,
			# not a stripe. Left unsharpened, so tufts stay separate instead of
			# chaining into streaks.
			var blade: float = _fbm(u, v, 96, 48, 2, 11)
			var clump: float = _fbm(u, v, 8, 8, 3, 27)   # ~75 cm patches
			var grain: float = _value(u * 128.0, v * 128.0, 128, 128, 53)
			var t: float = 0.44 * blade + 0.30 * clump + 0.26 * grain
			# Multiplies the height ramp, so this is shading depth, not colour: at
			# 0.66..1.0 it gives the ground body without washing it out.
			var g: float = 0.66 + 0.34 * clampf(t, 0.0, 1.0)
			# Only very slightly warm. The height ramp owns the hue — this texture
			# also covers bare rock, and a green tint would fight it there.
			img.set_pixel(i, j, Color(g, g, g * 0.94))
	return img


static func _build_asphalt() -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	for j in SIZE:
		var v: float = float(j) / float(SIZE)
		for i in SIZE:
			var u: float = float(i) / float(SIZE)
			var grit: float = _value(u * 128.0, v * 128.0, 128, 128, 71)  # ~2 cm chips
			var mottle: float = _fbm(u, v, 8, 8, 3, 89)
			var t: float = 0.58 * grit + 0.42 * mottle
			var g: float = 0.74 + 0.30 * clampf(t, 0.0, 1.0)
			img.set_pixel(i, j, Color(g, g, minf(g * 1.03, 1.0)))
	return img


## Build once, then reuse from disk. Generating these in GDScript costs the best
## part of a second — fine as a one-off, but not on every launch, and it would land
## as a freeze right when a scene is loading.
static func _cached(tex_name: String, builder: Callable) -> ImageTexture:
	var path := "%s/%s_v%d_%d.png" % [CACHE_DIR, tex_name, VERSION, SIZE]
	if FileAccess.file_exists(path):
		var cached := Image.load_from_file(path)
		if cached != null and cached.get_width() == SIZE:
			cached.generate_mipmaps()
			return ImageTexture.create_from_image(cached)
	var img: Image = builder.call()
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	img.save_png(path)  # before mipmaps: PNG stores level 0 only
	img.generate_mipmaps()  # the ground runs to the horizon; without these it boils
	return ImageTexture.create_from_image(img)


# --- Tileable value noise ---------------------------------------------------

## Fractal noise over [0,1) x [0,1). Each octave doubles the lattice, so every
## octave stays periodic and the result tiles with no seam.
static func _fbm(u: float, v: float, px: int, py: int, octaves: int, s: int) -> float:
	var sum := 0.0
	var amp := 1.0
	var norm := 0.0
	for i in octaves:
		var m: int = 1 << i
		sum += amp * _value(u * float(px * m), v * float(py * m), px * m, py * m, s + i * 101)
		norm += amp
		amp *= 0.5
	return sum / norm


## Value noise on a lattice that wraps at (px, py) — the periodicity is what makes
## the texture tileable. Separate x and y periods give the anisotropy.
static func _value(x: float, y: float, px: int, py: int, s: int) -> float:
	var x0 := floori(x)
	var y0 := floori(y)
	var fx: float = x - float(x0)
	var fy: float = y - float(y0)
	var ax := posmod(x0, px)
	var bx := posmod(x0 + 1, px)
	var ay := posmod(y0, py)
	var by := posmod(y0 + 1, py)
	var sx: float = fx * fx * (3.0 - 2.0 * fx)
	var sy: float = fy * fy * (3.0 - 2.0 * fy)
	var top: float = lerpf(_hash(ax, ay, s), _hash(bx, ay, s), sx)
	var bot: float = lerpf(_hash(ax, by, s), _hash(bx, by, s), sx)
	return lerpf(top, bot, sy)


static func _hash(xi: int, yi: int, s: int) -> float:
	var h: int = xi * 374761393 + yi * 668265263 + s * 1274126177
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFF) / 65535.0
