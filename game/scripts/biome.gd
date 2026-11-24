# Biomes: a purely cosmetic look for any map, picked on the start screen.
# Each one sets the ground colours, extra ground shape away from the road (dunes,
# rocks), the trees, the grass, the mountains on the horizon and, for the
# stadium, the grandstands. The roads, their heights and the driving are the same.
extends RefCounted

const LIST := ["Forest", "Desert dunes", "Grasslands", "Tundra", "Savannah", "Stadium"]
const INFO := [
	"woodland all around the road",
	"rolling sand dunes, hardly a plant in sight",
	"wide open plains of tall grass",
	"frozen ground, dark pines, mountains right beside you",
	"golden grass, red earth and flat-topped trees",
	"a race stadium: grandstands, floodlights, striped lawn",
]

static func get_biome(name: String) -> Dictionary:
	var b := {
		"name": "Forest",
		# ground
		"g_dark": Color(0.10, 0.15, 0.05), "g_lite": Color(0.22, 0.27, 0.09),
		"g_litter": Color(0.22, 0.16, 0.09), "litter_k": 0.75, "g_dirt": Color(0.26, 0.22, 0.16),
		"snow_base": 0.0, "stripes": 0.0, "ripples": 0.0, "shoulder": Color(1, 1, 1),
		# extra ground shape away from the road: amplitude (m), frequency, ridged?
		"bump_amp": 0.0, "bump_freq": 0.01, "bump_ridged": false,
		# trees and bushes
		"tree_k": 1.0, "tree_scale": Vector3(1, 1, 1), "leaf_tint": Color(1, 1, 1), "bush_k": 1.0,
		# grass tufts
		"grass_k": 1.0, "grass_h": 1.0, "grass_base": Color(0.04, 0.06, 0.02),
		"grass_tip_a": Color(0.12, 0.18, 0.06), "grass_tip_b": Color(0.21, 0.22, 0.09),
		# horizon mountains
		"mtn_show": true, "mtn_r": 1.0, "mtn_h": 1.0, "mtn_rock": Color(0.13, 0.15, 0.19), "mtn_snow": 390.0,
		"stadium": false,
	}
	match name:
		"Desert dunes":
			b.merge({"name": name, "g_dark": Color(0.62, 0.46, 0.29), "g_lite": Color(0.80, 0.63, 0.41),
				"g_litter": Color(0.68, 0.52, 0.34), "litter_k": 0.35, "g_dirt": Color(0.6, 0.48, 0.33),
				"ripples": 1.0, "shoulder": Color(1.3, 1.15, 0.92),
				"bump_amp": 8.0, "bump_freq": 0.011, "bump_ridged": true,
				"tree_k": 0.0, "bush_k": 0.2, "leaf_tint": Color(0.75, 0.62, 0.35),
				"grass_k": 0.1, "grass_h": 0.6, "grass_base": Color(0.3, 0.24, 0.12),
				"grass_tip_a": Color(0.55, 0.45, 0.25), "grass_tip_b": Color(0.62, 0.52, 0.3),
				"mtn_h": 0.5, "mtn_rock": Color(0.5, 0.34, 0.21), "mtn_snow": 99999.0}, true)
		"Grasslands":
			b.merge({"name": name, "g_dark": Color(0.18, 0.28, 0.07), "g_lite": Color(0.34, 0.40, 0.13),
				"g_litter": Color(0.38, 0.36, 0.15), "litter_k": 0.2,
				"bump_amp": 3.0, "bump_freq": 0.004,
				"tree_k": 0.0, "bush_k": 0.0,
				"grass_k": 1.8, "grass_h": 1.5, "grass_base": Color(0.06, 0.09, 0.02),
				"grass_tip_a": Color(0.28, 0.38, 0.1), "grass_tip_b": Color(0.46, 0.45, 0.17),
				"mtn_h": 0.35, "mtn_rock": Color(0.25, 0.31, 0.2), "mtn_snow": 99999.0}, true)
		"Tundra":
			b.merge({"name": name, "g_dark": Color(0.28, 0.29, 0.25), "g_lite": Color(0.44, 0.44, 0.38),
				"g_litter": Color(0.52, 0.52, 0.5), "litter_k": 0.45, "snow_base": 0.55,
				"bump_amp": 2.5, "bump_freq": 0.03, "bump_ridged": true,
				"tree_k": 0.22, "tree_scale": Vector3(0.7, 1.35, 0.7), "leaf_tint": Color(0.45, 0.62, 0.55), "bush_k": 0.4,
				"grass_k": 0.5, "grass_h": 0.6, "grass_base": Color(0.12, 0.13, 0.1),
				"grass_tip_a": Color(0.4, 0.42, 0.33), "grass_tip_b": Color(0.52, 0.52, 0.44),
				"mtn_r": 0.62, "mtn_h": 1.2, "mtn_rock": Color(0.2, 0.21, 0.24), "mtn_snow": 140.0}, true)
		"Savannah":
			b.merge({"name": name, "g_dark": Color(0.44, 0.36, 0.17), "g_lite": Color(0.62, 0.52, 0.25),
				"g_litter": Color(0.52, 0.32, 0.17), "litter_k": 0.45, "g_dirt": Color(0.58, 0.36, 0.2),
				"shoulder": Color(1.25, 1.0, 0.8), "bump_amp": 2.0, "bump_freq": 0.006,
				"tree_k": 0.1, "tree_scale": Vector3(1.75, 0.68, 1.75), "leaf_tint": Color(0.82, 0.88, 0.55), "bush_k": 0.5,
				"grass_k": 1.4, "grass_h": 1.35, "grass_base": Color(0.22, 0.19, 0.07),
				"grass_tip_a": Color(0.6, 0.5, 0.22), "grass_tip_b": Color(0.74, 0.62, 0.3),
				"mtn_h": 0.45, "mtn_rock": Color(0.42, 0.3, 0.2), "mtn_snow": 99999.0}, true)
		"Stadium":
			b.merge({"name": name, "g_dark": Color(0.10, 0.28, 0.07), "g_lite": Color(0.15, 0.35, 0.09),
				"litter_k": 0.0, "stripes": 1.0, "g_dirt": Color(0.2, 0.24, 0.12),
				"tree_k": 0.0, "bush_k": 0.0, "grass_k": 0.0, "mtn_show": false, "stadium": true}, true)
	return b

# extra ground shape (dunes, rocky lumps) that fades in away from the road
static var _noise: FastNoiseLite
static func extra_height(b: Dictionary, x: float, z: float, d: float) -> float:
	var amp: float = b.get("bump_amp", 0.0)
	if amp <= 0.0 or d < 22.0:
		return 0.0
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.seed = 404
		_noise.fractal_octaves = 3
	_noise.frequency = b["bump_freq"]
	var n := _noise.get_noise_2d(x, z)
	if b["bump_ridged"]:
		n = 1.0 - abs(n) * 2.0      # sharp crests like dunes / rock ridges
		n = n * n * 0.9 - 0.2
	var k := clampf((d - 22.0) / 40.0, 0.0, 1.0)
	return n * amp * k * k * (3.0 - 2.0 * k)

# ground shader shared by every map
const TERRAIN_SHADER := """
shader_type spatial;
render_mode cull_back;
uniform sampler2D noise_a : repeat_enable, filter_linear_mipmap;
uniform sampler2D noise_b : repeat_enable, filter_linear_mipmap;
uniform sampler2D detail_n : hint_normal, repeat_enable, filter_linear_mipmap;
uniform float snow = 0.0;
uniform float litter_k = 0.75;
uniform vec3 tint = vec3(1.0);
uniform vec3 g_dark : source_color = vec3(0.10, 0.15, 0.05);
uniform vec3 g_lite : source_color = vec3(0.22, 0.27, 0.09);
uniform vec3 g_litter : source_color = vec3(0.22, 0.16, 0.09);
uniform vec3 g_dirt : source_color = vec3(0.26, 0.22, 0.16);
uniform float stripes = 0.0;
uniform float ripples = 0.0;
varying vec3 wpos;
varying float road_k;
varying vec3 wnrm;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	road_k = COLOR.r;
	wnrm = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}
void fragment() {
	float n1 = texture(noise_a, wpos.xz * 0.004).r;
	float n2 = texture(noise_b, wpos.xz * 0.035).r;
	float n3 = texture(noise_b, wpos.xz * 0.31).r;
	vec3 c = mix(g_dark, g_lite, smoothstep(0.3, 0.7, n1));
	c = mix(c, g_litter, smoothstep(0.5, 0.75, n2) * litter_k);
	c *= 0.75 + 0.5 * n3;
	// mown stripes (stadium lawn)
	c *= 1.0 + stripes * 0.12 * sign(sin(wpos.x * 0.35 + wpos.z * 0.12));
	// wind ripples in the sand
	c *= 1.0 + ripples * 0.07 * sin(wpos.x * 2.1 + wpos.z * 0.7 + n2 * 6.0);
	c = mix(g_dirt, c * tint, smoothstep(0.0, 0.6, road_k));
	float sn = snow * smoothstep(0.55, 0.9, normalize(wnrm).y) * (0.8 + 0.2 * n3);
	c = mix(c, vec3(0.86, 0.88, 0.93), sn);
	ALBEDO = c;
	ROUGHNESS = 0.95;
	NORMAL_MAP = texture(detail_n, wpos.xz * 0.25).rgb;
	NORMAL_MAP_DEPTH = 0.6 * (1.0 - stripes * 0.7);
}
"""

static func apply_terrain(mat: ShaderMaterial, b: Dictionary) -> void:
	for k in ["g_dark", "g_lite", "g_litter", "g_dirt"]:
		var c: Color = b[k]
		mat.set_shader_parameter(k, Vector3(c.r, c.g, c.b))
	mat.set_shader_parameter("litter_k", b["litter_k"])
	mat.set_shader_parameter("stripes", b["stripes"])
	mat.set_shader_parameter("ripples", b["ripples"])
	mat.set_shader_parameter("snow", b["snow_base"])
