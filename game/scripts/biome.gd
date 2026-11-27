# Biomes: a purely cosmetic look for any map, picked on the start screen.
# Each one sets the ground colours, extra ground shape away from the road (dunes,
# rocks), the trees, the grass and the mountains on the horizon. The roads,
# their heights and the driving are the same.
extends RefCounted

const LIST := ["Forest", "Desert dunes", "Grasslands", "Tundra", "Savannah",
	"Autumn forest", "Cherry blossom", "Canyon", "Volcanic", "Neon night", "Lavender fields", "Beach"]
const INFO := [
	"woodland all around the road",
	"rolling sand dunes, hardly a plant in sight",
	"wide open plains of tall grass",
	"frozen ground, dark pines, mountains right beside you",
	"golden grass, red earth and flat-topped trees",
	"orange, red and gold leaves over a carpet of fallen leaves",
	"pink blossom trees and petal-strewn grass",
	"red sandstone ridges and mesas, barely a plant",
	"black ash, dead trees and glowing lava cracks",
	"dark ground with a glowing neon grid - best after dark",
	"rolling fields of purple lavender",
	"sand and the open sea: on the left of Endless Road, all round the outside of the circuits",
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
		# leaves redrawn in this colour (a = 0: the normal green), and glow:
		# leaf_glow / line_glow make the leaves / road lines glow in glow_col;
		# glow_mode 1 = neon grid on the ground, 2 = lava cracks (glow_k = strength)
		"leaf_color": Color(0, 0, 0, 0), "leaf_glow": 0.0, "line_glow": 0.0,
		"glow_mode": 0, "glow_k": 0.0, "glow_col": Color(0, 0, 0),
	}
	match name:
		"Desert dunes":
			b.merge({"name": name, "g_dark": Color(0.62, 0.46, 0.29), "g_lite": Color(0.80, 0.63, 0.41),
				"g_litter": Color(0.68, 0.52, 0.34), "litter_k": 0.35, "g_dirt": Color(0.6, 0.48, 0.33),
				"ripples": 1.0, "shoulder": Color(1.3, 1.15, 0.92),
				"bump_amp": 7.0, "bump_freq": 0.009, "bump_ridged": true, "bump_soft": 0.035, "bump_octaves": 2,
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
		"Autumn forest":
			b.merge({"name": name, "g_dark": Color(0.22, 0.14, 0.06), "g_lite": Color(0.36, 0.22, 0.08),
				"g_litter": Color(0.55, 0.26, 0.06), "litter_k": 1.0, "g_dirt": Color(0.3, 0.22, 0.14),
				"leaf_color": Color(0.85, 0.38, 0.08), "bush_k": 0.8, "fx": "leaves",
				"grass_k": 0.7, "grass_base": Color(0.12, 0.08, 0.03),
				"grass_tip_a": Color(0.45, 0.3, 0.1), "grass_tip_b": Color(0.6, 0.38, 0.12),
				"mtn_rock": Color(0.2, 0.17, 0.16)}, true)
		"Cherry blossom":
			b.merge({"name": name, "g_dark": Color(0.16, 0.26, 0.09), "g_lite": Color(0.28, 0.38, 0.14),
				"g_litter": Color(0.85, 0.55, 0.65), "litter_k": 0.55,
				"tree_k": 0.65, "tree_scale": Vector3(1.25, 0.85, 1.25), "leaf_color": Color(1.0, 0.62, 0.78), "bush_k": 0.5, "fx": "petals",
				"grass_k": 0.9, "grass_h": 0.8,
				"grass_tip_a": Color(0.3, 0.42, 0.14), "grass_tip_b": Color(0.62, 0.45, 0.5),
				"mtn_rock": Color(0.28, 0.27, 0.34), "mtn_snow": 260.0}, true)
		"Canyon":
			b.merge({"name": name, "g_dark": Color(0.36, 0.11, 0.05), "g_lite": Color(0.52, 0.18, 0.07),
				"g_litter": Color(0.6, 0.3, 0.14), "litter_k": 0.5, "g_dirt": Color(0.45, 0.2, 0.1),
				"shoulder": Color(1.3, 0.9, 0.7),
				"bump_amp": 9.0, "bump_freq": 0.012, "bump_ridged": true, "bump_octaves": 3,
				"tree_k": 0.03, "tree_scale": Vector3(0.9, 0.7, 0.9), "leaf_color": Color(0.36, 0.38, 0.2), "bush_k": 0.3,
				"grass_k": 0.15, "grass_h": 0.6, "grass_base": Color(0.3, 0.2, 0.1),
				"grass_tip_a": Color(0.55, 0.45, 0.25), "grass_tip_b": Color(0.6, 0.5, 0.3),
				"mtn_r": 0.75, "mtn_h": 0.8, "mtn_rock": Color(0.45, 0.16, 0.07), "mtn_snow": 99999.0}, true)
		"Volcanic":
			b.merge({"name": name, "g_dark": Color(0.05, 0.05, 0.055), "g_lite": Color(0.13, 0.12, 0.12),
				"g_litter": Color(0.22, 0.2, 0.19), "litter_k": 0.5, "g_dirt": Color(0.1, 0.09, 0.09),
				"shoulder": Color(0.5, 0.48, 0.48),
				"bump_amp": 3.5, "bump_freq": 0.02, "bump_ridged": true,
				"tree_k": 0.3, "no_leaves": true, "bark_col": Color(0.06, 0.055, 0.05), "bush_k": 0.0, "fx": "ash",
				"grass_k": 0.0,
				"glow_mode": 2, "glow_k": 1.0, "glow_col": Color(2.2, 0.7, 0.1),
				"mtn_r": 0.7, "mtn_h": 1.1, "mtn_rock": Color(0.07, 0.065, 0.07), "mtn_snow": 99999.0}, true)
		"Neon night":
			b.merge({"name": name, "g_dark": Color(0.02, 0.02, 0.04), "g_lite": Color(0.05, 0.04, 0.09),
				"g_litter": Color(0.08, 0.04, 0.12), "litter_k": 0.3, "g_dirt": Color(0.04, 0.04, 0.06),
				"shoulder": Color(0.35, 0.35, 0.45),
				"bump_amp": 1.5, "bump_freq": 0.006,
				"tree_k": 0.22, "buildings": true, "tree_clear": 8.0, "bush_k": 0.0,
				"tree_tries": 10, "tree_spread": 1.0, "tree_reach": 290.0,
				"glow_col2": Color(1.6, 0.2, 1.3),
				"grass_k": 0.0,
				"glow_mode": 1, "glow_k": 1.0, "glow_col": Color(0.2, 1.4, 1.6), "line_glow": 2.0,
				"mtn_rock": Color(0.04, 0.03, 0.07), "mtn_snow": 99999.0}, true)
		"Lavender fields":
			b.merge({"name": name, "g_dark": Color(0.18, 0.15, 0.24), "g_lite": Color(0.3, 0.24, 0.4),
				"g_litter": Color(0.22, 0.3, 0.12), "litter_k": 0.35,
				"bump_amp": 3.0, "bump_freq": 0.004,
				"tree_k": 0.0, "bush_k": 0.0, "flowers": 1.0, "flower_col": Color(0.52, 0.3, 0.9),
				"grass_k": 2.6, "grass_h": 0.85, "grass_base": Color(0.08, 0.1, 0.05),
				"grass_tip_a": Color(0.58, 0.4, 0.9), "grass_tip_b": Color(0.72, 0.52, 1.0),
				"mtn_h": 0.4, "mtn_rock": Color(0.26, 0.25, 0.34), "mtn_snow": 99999.0}, true)
		"Beach":
			# sea / sea_y / sea_start: the ocean on the left of Endless Road;
			# road_hills flattens the road to just above the water; land_k /
			# land_add keep the land side low but always above sea level
			b.merge({"name": name, "g_dark": Color(0.74, 0.64, 0.44), "g_lite": Color(0.88, 0.79, 0.58),
				"g_litter": Color(0.45, 0.52, 0.28), "litter_k": 0.35, "g_dirt": Color(0.82, 0.73, 0.52),
				"ripples": 0.6, "shoulder": Color(1.3, 1.2, 1.0),
				"bump_amp": 2.0, "bump_freq": 0.012, "bump_ridged": true, "bump_soft": 0.05, "bump_octaves": 2,
				"tree_k": 0.12, "tree_scale": Vector3(0.55, 1.45, 0.55), "leaf_color": Color(0.3, 0.55, 0.2), "bush_k": 0.3,
				"grass_k": 0.35, "grass_h": 0.8, "grass_base": Color(0.3, 0.3, 0.15),
				"grass_tip_a": Color(0.55, 0.6, 0.3), "grass_tip_b": Color(0.7, 0.68, 0.42),
				"mtn_show": false,
				"sea": true, "sea_y": -2.4, "sea_start": 28.0,
				"road_hills": 0.08, "land_k": 0.25, "land_add": 3.0}, true)
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
	_noise.fractal_octaves = int(b.get("bump_octaves", 3))
	_noise.frequency = b["bump_freq"]
	var n := _noise.get_noise_2d(x, z)
	if b["bump_ridged"]:
		# crests like dunes / rock ridges; bump_soft rounds the crest off instead
		# of a sharp crease (sqrt(n^2 + s) is a smooth |n|)
		var soft: float = b.get("bump_soft", 0.0)
		n = 1.0 - sqrt(n * n + soft) * 2.0
		n = n * n * 0.9 - 0.2
	var k := clampf((d - 22.0) / 40.0, 0.0, 1.0)
	return n * amp * k * k * (3.0 - 2.0 * k)

# ground shader shared by every map
const TERRAIN_SHADER := """
shader_type spatial;
#ifdef BAKED
render_mode cull_back, unshaded;
global uniform vec3 baked_tint;
#else
render_mode cull_back;
#endif
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
uniform int glow_mode = 0;
uniform float glow_k = 0.0;
uniform vec3 glow_col : source_color = vec3(0.0);
varying vec3 wpos;
varying float road_k;
varying float bake_k;   // baked light (Gfx.baked): vertex colour green, x1.3
varying vec3 wnrm;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	road_k = COLOR.r;
	bake_k = COLOR.g;
	wnrm = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}
void fragment() {
	float n1 = texture(noise_a, wpos.xz * 0.004).r;
	float n2 = texture(noise_b, wpos.xz * 0.035).r;
	vec3 c = mix(g_dark, g_lite, smoothstep(0.3, 0.7, n1));
#ifdef SMOOTH
	// low detail: only the big soft colour patches, no fine grain or bumps
	c = mix(c, g_litter, smoothstep(0.45, 0.85, n2) * litter_k * 0.6);
	float n3 = 0.5;
#else
	float n3 = texture(noise_b, wpos.xz * 0.31).r;
	c = mix(c, g_litter, smoothstep(0.5, 0.75, n2) * litter_k);
	c *= 0.75 + 0.5 * n3;
	// wind ripples in the sand
	c *= 1.0 + ripples * 0.07 * sin(wpos.x * 2.1 + wpos.z * 0.7 + n2 * 6.0);
#endif
	// mown stripes (stadium lawn)
	c *= 1.0 + stripes * 0.12 * sign(sin(wpos.x * 0.35 + wpos.z * 0.12));
	c = mix(g_dirt, c * tint, smoothstep(0.0, 0.6, road_k));
	float sn = snow * smoothstep(0.55, 0.9, normalize(wnrm).y) * (0.8 + 0.2 * n3);
	c = mix(c, vec3(0.86, 0.88, 0.93), sn);
	// glowing ground (biome glow_mode): 1 = neon grid lines, 2 = lava cracks.
	// Kept off the road and its gravel edge.
	float glow = 0.0;
	if (glow_mode == 1) {
		vec2 g = abs(fract(wpos.xz / 9.0) - 0.5);
		glow = smoothstep(0.455, 0.49, max(g.x, g.y));
	} else if (glow_mode == 2) {
		float cn = texture(noise_b, wpos.xz * 0.018).r;
		glow = 1.0 - smoothstep(0.0, 0.035, abs(cn - 0.5));
		glow *= 0.75 + 0.25 * sin(TIME * 1.3 + wpos.x * 0.05 + wpos.z * 0.04);
	}
	glow *= smoothstep(0.3, 0.9, road_k) * glow_k;
	c = mix(c, c * 0.4, glow);   // the glowing line itself is dark in daylight
#ifdef BAKED
	ALBEDO = c * bake_k * 1.3 * baked_tint + glow_col * glow;
#else
	ALBEDO = c;
	EMISSION = glow_col * glow;
	ROUGHNESS = 0.95;
#ifndef SMOOTH
	NORMAL_MAP = texture(detail_n, wpos.xz * 0.25).rgb;
	NORMAL_MAP_DEPTH = 0.6 * (1.0 - stripes * 0.7);
#endif
#endif
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
	mat.set_shader_parameter("glow_mode", int(b.get("glow_mode", 0)))
	mat.set_shader_parameter("glow_k", float(b.get("glow_k", 0.0)))
	var gc: Color = b.get("glow_col", Color.BLACK)
	mat.set_shader_parameter("glow_col", Vector3(gc.r, gc.g, gc.b))
