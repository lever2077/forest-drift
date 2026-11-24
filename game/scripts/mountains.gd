# Distant mountain ranges on the horizon. A ring of ridged peaks 1.4-2.4 km out
# that travels with the camera (like a backdrop, so it works on the endless road
# too). It does its own atmospheric haze instead of the scene fog, so the peaks
# stay visible as a soft silhouette, and the snow line drops when it snows.
extends Node3D

const SEG := 720
const RADII := [1100.0, 1450.0, 1600.0, 1750.0, 1900.0, 2050.0, 2200.0, 2350.0]

var env: Environment
var envc
var mat: ShaderMaterial

const SHADER := """
shader_type spatial;
render_mode fog_disabled, cull_disabled, specular_disabled;
uniform vec3 haze_color = vec3(0.7, 0.75, 0.8);
uniform float haze = 0.6;
uniform float snow_line = 260.0;
uniform vec3 rock_col : source_color = vec3(0.13, 0.15, 0.19);
varying float hgt;
varying vec3 wpos;
void vertex() {
	hgt = VERTEX.y;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
float hash1(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
// smooth value noise (no blocky squares when the range is close by)
float hash(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash1(i), hash1(i + vec2(1.0, 0.0)), f.x), mix(hash1(i + vec2(0.0, 1.0)), hash1(i + vec2(1.0, 1.0)), f.x), f.y);
}
void fragment() {
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float up = clamp(wn.y, 0.0, 1.0);
	// streaky snow: lower on flatter faces, broken up a little
	float n = (hash(wpos.xz / 14.0) * 0.6 + hash(wpos.xz / 47.0) * 0.4) * 50.0;
	float line = snow_line + (1.0 - up) * 120.0 - n;
	float s = smoothstep(line - 25.0, line + 25.0, hgt);
	vec3 rock = mix(rock_col, rock_col * vec3(1.45, 1.45, 1.05), up);
	vec3 col = mix(rock, vec3(0.93, 0.95, 0.98), s);
	// thicker air low down
	float h = clamp(haze * mix(1.0, 0.5, clamp((hgt + 30.0) / 420.0, 0.0, 1.0)), 0.0, 1.0);
	ALBEDO = col * (1.0 - h);
	ROUGHNESS = 1.0;
	EMISSION = haze_color * h;
}
"""

var r_scale := 1.0
var h_scale := 1.0
var snow_base := 390.0

func build(p_env: Environment, p_envc, biome: Dictionary = {}) -> void:
	env = p_env
	envc = p_envc
	# biome: how far, how tall, rock colour, snow line - or none at all
	if not biome.get("mtn_show", true):
		visible = false
		set_process(false)
		return
	r_scale = biome.get("mtn_r", 1.0)
	h_scale = biome.get("mtn_h", 1.0)
	snow_base = biome.get("mtn_snow", 390.0) * h_scale
	# broad massifs + ridged detail on top
	var massif := FastNoiseLite.new()
	massif.seed = 4242
	massif.noise_type = FastNoiseLite.TYPE_SIMPLEX
	massif.fractal_type = FastNoiseLite.FRACTAL_FBM
	massif.fractal_octaves = 3
	massif.frequency = 0.00055
	var noise := FastNoiseLite.new()
	noise.seed = 77
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	noise.fractal_octaves = 4
	noise.frequency = 0.0016
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := RADII.size()
	var grid := []
	for j in rows:
		var r: float = RADII[j] * r_scale
		var row := []
		for i in SEG:
			var a := TAU * i / SEG
			var x := cos(a) * r
			var z := sin(a) * r
			var y: float
			if j == 0:
				y = -220.0                       # skirt hidden below the land
			else:
				# one continuous range all the way round: roughly the same height,
				# rolling gently up and down, with only small bumps on the ridgeline
				var m := clampf(massif.get_noise_2d(x, z) * 0.75 + 0.5, 0.0, 1.0)
				var ridge := clampf(noise.get_noise_2d(x, z) * 0.5 + 0.5, 0.0, 1.0)
				var k := float(j) / (rows - 1)
				var mh := lerpf(60.0, 480.0, k) * h_scale
				y = -30.0 + mh * (0.72 + 0.28 * m) * (0.93 + 0.07 * ridge)
			row.append(Vector3(x, y, z))
		grid.append(row)
	for j in rows - 1:
		for i in SEG:
			var i2 := (i + 1) % SEG
			var a: Vector3 = grid[j][i]
			var b: Vector3 = grid[j][i2]
			var c: Vector3 = grid[j + 1][i2]
			var d: Vector3 = grid[j + 1][i]
			st.add_vertex(a); st.add_vertex(c); st.add_vertex(b)
			st.add_vertex(a); st.add_vertex(d); st.add_vertex(c)
	if "--verbose" in OS.get_cmdline_user_args():
		var mx := -1e9
		var sum := 0.0
		for i in SEG:
			mx = max(mx, (grid[rows - 1][i] as Vector3).y)
			sum += (grid[rows - 1][i] as Vector3).y
		print("MOUNTAINS max=%.0f avg=%.0f" % [mx, sum / SEG])
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 4000.0
	var sh := Shader.new()
	sh.code = SHADER
	mat = ShaderMaterial.new()
	mat.shader = sh
	var rc: Color = biome.get("mtn_rock", Color(0.13, 0.15, 0.19))
	mat.set_shader_parameter("rock_col", Vector3(rc.r, rc.g, rc.b))
	mi.material_override = mat
	add_child(mi)
	_update()

func _process(_delta: float) -> void:
	_update()

func _update() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam:
		var p := cam.global_position
		global_position = Vector3(p.x, p.y - 40.0, p.z)
	if env == null:
		return
	# haze follows the weather: clear days show crisp peaks, fog hides them
	var fd: float = env.fog_density + env.volumetric_fog_density * 0.6
	var hz := 1.0 - exp(-fd * 170.0 * r_scale) * 0.85     # nearer mountains are less hazy
	mat.set_shader_parameter("haze", clampf(hz, 0.15, 1.0))
	# the haze is lit by the same daylight as the scene: dim under storm clouds
	var dk: float = envc.cur[1] if envc else 0.0
	mat.set_shader_parameter("haze_color", env.fog_light_color * (1.0 - 0.55 * dk))
	var snow: float = envc.cur[6] if envc else 0.0
	mat.set_shader_parameter("snow_line", lerpf(snow_base, 40.0, snow))
