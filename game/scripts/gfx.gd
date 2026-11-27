# Graphics modes that change how the world is built (Settings > Graphics, saved;
# changing one reloads the map because the world is generated on load):
#
#  low   - "Detail: Low (smooth)": for slow computers. Surfaces are smooth flat
#          colours (no noise or bump textures), trees have round ball crowns
#          instead of thousands of leaf cards, and the expensive screen effects
#          (SSAO, volumetric fog, glow, MSAA) are off with cheaper sun shadows.
#
#  baked - "Baked lighting": the light and shadow of the static world (ground,
#          road, trees, bushes, grass) is worked out once while the map builds
#          and stored in the mesh colours, then the world is drawn unshaded: no
#          per-pixel lighting and no shadow maps. At runtime only a single colour,
#          the current sun + sky light, multiplies it, so day/night and weather
#          still work. Tree shadows are baked into the ground as soft dark patches.
extends RefCounted

static var low := false
static var baked := false

# fixed direction towards the "baked" sun (high, from the south-west)
const BAKE_SUN := Vector3(0.45, 0.8, 0.4)
const SKY_K := 0.42      # share of light from the sky dome
const SUN_K := 0.75      # share of light from the baked sun
const TERRAIN_SCALE := 1.3   # baked ground light is stored /1.3 to fit a vertex colour

# runtime light colour -> how bright the baked world is drawn
const TINT_SUN := 0.7
const TINT_SKY := 0.5

static var tint := Color.WHITE
static var _mats: Array = []   # unshaded world materials that follow the tint

static func reset() -> void:
	_mats.clear()
	tint = Color.WHITE

# adds #define SMOOTH / BAKED to a world shader (they switch its code paths)
static func shader_code(code: String) -> String:
	var defs := ""
	if low:
		defs += "#define SMOOTH\n"
	if baked:
		defs += "#define BAKED\n"
	return code.replace("shader_type spatial;\n", "shader_type spatial;\n" + defs)

# baked light for a surface facing 'n': sky dome + the baked sun.
# ao darkens the sky part, shadow the sun part. ~1.0 for open flat ground.
static func light_at(n: Vector3, ao := 1.0, shadow := 1.0) -> float:
	var sky := 0.5 + 0.5 * n.y
	var sun := maxf(n.dot(BAKE_SUN.normalized()), 0.0)
	return SKY_K * sky * ao + SUN_K * sun * shadow

# A static world surface material. On Low its textures are replaced by the flat
# colour 'flat' (roughly the texture's average); with baked lighting it's drawn
# unshaded and follows the runtime light colour.
static func surface(m: StandardMaterial3D, flat := Color.WHITE) -> void:
	if low and m.albedo_texture != null:
		m.albedo_texture = null
		m.set_meta("flat", flat)
	if low:
		m.normal_enabled = false
		m.normal_texture = null
	if baked:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mats.append(m)
	set_albedo(m, m.albedo_color)

# use instead of setting albedo_color on a material passed to surface()
static func set_albedo(m: StandardMaterial3D, c: Color) -> void:
	m.set_meta("base", c)
	var out: Color = c * (m.get_meta("flat", Color.WHITE) as Color)
	if baked and m.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
		out = Color(out.r * tint.r, out.g * tint.g, out.b * tint.b, out.a)
	m.albedo_color = out

# called every frame by the environment controller with the current lights
static func update_light(sun: DirectionalLight3D, moon: DirectionalLight3D, env: Environment, sky: Color) -> void:
	if not baked:
		return
	var c := sky * env.ambient_light_energy * TINT_SKY
	if sun and sun.visible:
		c += sun.light_color * sun.light_energy * TINT_SUN
	if moon and moon.visible:
		c += moon.light_color * moon.light_energy * TINT_SUN
	tint = Color(c.r, c.g, c.b, 1.0)
	RenderingServer.global_shader_parameter_set("baked_tint", Vector3(c.r, c.g, c.b))
	for m in _mats:
		if is_instance_valid(m):
			set_albedo(m, m.get_meta("base", Color.WHITE))
