# Grass: tufts of blades covering the land around the camera, kept cheap:
#  - only within a short radius (50 m on High, 34 m on Low), built in small
#    chunks that stream in around the camera and drop out behind it
#  - distant chunks draw only part of their tufts (instances are in random order,
#    so lowering the visible count thins them evenly) - no rebuilding needed
#  - two crossed cards per tuft, no shadows, a fixed time budget per frame
#  - each tuft sits exactly on the ground as it is drawn (track.surface_h), never
#    on the road or its gravel shoulder
# Quality: 0 = off, 1 = low, 2 = high (set from the Settings panel).
extends Node3D

const CHUNK := 12.0
const PER_M2 := 2.0            # tufts per square metre on High, before the map's multiplier
const BUILD_BUDGET_US := 1500  # time spent building chunks per frame
const CELL := 2.0              # height / road-distance sample spacing for maps with slow queries

var track
var quality := 2
var radius := 50.0
var density := 1.0
var map_density := 1.0
var height := 1.0
var fast_queries := false      # track.gd maps: exact surface + road distance are cheap lookups
var mesh: ArrayMesh
var mat: ShaderMaterial
var chunks := {}               # Vector2i -> MultiMeshInstance3D (or null when empty)
var pending: Array = []        # chunk keys still to build, nearest first
var last_cc := Vector2i(1 << 30, 0)
var lod_timer := 0.0

const SHADER := """
shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx, shadows_disabled;
uniform sampler2D blades : source_color, filter_linear_mipmap, repeat_disable;
uniform float fade_far = 50.0;
uniform float snow = 0.0;
uniform vec3 base_col : source_color = vec3(0.04, 0.06, 0.02);
uniform vec3 tip_a : source_color = vec3(0.12, 0.18, 0.06);
uniform vec3 tip_b : source_color = vec3(0.21, 0.22, 0.09);
varying float tip;
varying float hue;
void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float d = distance(origin, INV_VIEW_MATRIX[3].xyz);
	tip = 1.0 - UV.y;
	VERTEX.y *= smoothstep(fade_far, fade_far - 12.0, d);
	float w = sin(TIME * 1.6 + origin.x * 0.31 + origin.z * 0.23) * 0.6 + sin(TIME * 2.9 + origin.x * 0.83) * 0.25;
	VERTEX.xz += vec2(0.13, 0.07) * w * tip * tip;
	hue = fract(sin(dot(origin.xz, vec2(12.9898, 78.233))) * 43758.5453);
	NORMAL = vec3(0.0, 1.0, 0.0);
}
void fragment() {
	float a = texture(blades, UV).a;
	vec3 base = base_col;
	vec3 top = mix(tip_a, tip_b, hue);
	vec3 c = mix(base, top, smoothstep(0.0, 0.9, tip));
	ALBEDO = mix(c, vec3(0.86, 0.88, 0.92), snow * smoothstep(0.2, 1.0, tip) * 0.85);
	ALPHA = a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 0.85;
	SPECULAR = 0.25;
}
"""

func setup(p_track, vr_scale := 1.0, p_quality := 2) -> void:
	track = p_track
	var dv = track.get("grass_density")
	var hv = track.get("grass_height")
	map_density = (float(dv) if dv != null else 0.8) * vr_scale
	height = float(hv) if hv != null else 1.0
	# biome: how much grass, how tall, what colour
	var b = track.get("biome")
	if b is Dictionary:
		map_density *= float(b.get("grass_k", 1.0))
		height *= float(b.get("grass_h", 1.0))
	fast_queries = track.get("t_h") != null
	mesh = _tuft_mesh()
	var sh := Shader.new()
	sh.code = SHADER
	mat = ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("blades", _blade_texture())
	if b is Dictionary:
		for k in [["base_col", "grass_base"], ["tip_a", "grass_tip_a"], ["tip_b", "grass_tip_b"]]:
			var c: Color = b.get(k[1], Color.WHITE)
			mat.set_shader_parameter(k[0], Vector3(c.r, c.g, c.b))
	mesh.surface_set_material(0, mat)
	if "grass_mat" in track:
		track.grass_mat = mat
	set_quality(p_quality)

func set_quality(q: int) -> void:
	quality = clampi(q, 0, 2)
	radius = [0.0, 34.0, 50.0][quality]
	density = [0.0, 0.55, 1.0][quality] * map_density
	mat.set_shader_parameter("fade_far", radius)
	# throw away what's built; it rebuilds at the new density
	for k in chunks.keys():
		if chunks[k]:
			chunks[k].queue_free()
	chunks.clear()
	pending.clear()
	last_cc = Vector2i(1 << 30, 0)
	visible = quality > 0
	set_process(quality > 0)

# two crossed cards, ~0.7 m wide and 0.55 m tall (scaled per tuft)
func _tuft_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 2:
		var a := PI * 0.5 * k + 0.4
		var dx := Vector3(cos(a), 0, sin(a)) * 0.36
		var v := [-dx, dx, dx + Vector3(0, 0.55, 0), -dx + Vector3(0, 0.55, 0)]
		var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_normal(Vector3.UP)
			st.set_uv(uv[idx])
			st.add_vertex(v[idx])
	return st.commit()

# a handful of tapered, slightly leaning blades on a transparent card
func _blade_texture() -> ImageTexture:
	var W := 128
	var H := 256
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for b in 30:
		var x0 := rng.randf_range(8, W - 8)
		var lean := rng.randf_range(-26, 26)
		var hgt := rng.randf_range(0.45, 1.0) * H
		var w0 := rng.randf_range(1.6, 2.8)
		for yy in int(hgt):
			var t := yy / hgt
			var cx := x0 + lean * t * t
			var hw := w0 * (1.0 - t * 0.92)
			var y := H - 1 - yy
			for xx in range(int(cx - hw - 2), int(cx + hw + 3)):
				if xx >= 0 and xx < W:
					var a := clampf(hw + 0.5 - abs(xx + 0.5 - cx), 0.0, 1.0)
					if a > img.get_pixel(xx, y).a:
						img.set_pixel(xx, y, Color(1, 1, 1, a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or track == null:
		return
	var p := cam.global_position
	var cc := Vector2i(int(floor(p.x / CHUNK)), int(floor(p.z / CHUNK)))
	if cc != last_cc:
		last_cc = cc
		_rescan(p)
	# build nearest chunks first, within a fixed time budget
	var t0 := Time.get_ticks_usec()
	while not pending.is_empty() and Time.get_ticks_usec() - t0 < BUILD_BUDGET_US:
		var k: Vector2i = pending.pop_front()
		if not chunks.has(k):
			_build_chunk(k)
	# thin out distant chunks a few times a second
	lod_timer -= delta
	if lod_timer <= 0.0:
		lod_timer = 0.2
		_update_lod(p)

func _rescan(p: Vector3) -> void:
	var cr := int(ceil(radius / CHUNK))
	var want := []
	for dz in range(-cr, cr + 1):
		for dx in range(-cr, cr + 1):
			var k := Vector2i(last_cc.x + dx, last_cc.y + dz)
			var dd := _chunk_dist(k, p)
			if dd < radius + CHUNK * 0.6 and not chunks.has(k):
				want.append([dd, k])
	want.sort_custom(func(a, b): return a[0] < b[0])
	pending.clear()
	for w in want:
		pending.append(w[1])
	for k in chunks.keys():
		if _chunk_dist(k, p) > radius + CHUNK * 2.0:
			if chunks[k]:
				chunks[k].queue_free()
			chunks.erase(k)

func _chunk_dist(k: Vector2i, p: Vector3) -> float:
	return Vector2((k.x + 0.5) * CHUNK, (k.y + 0.5) * CHUNK).distance_to(Vector2(p.x, p.z))

func _update_lod(p: Vector3) -> void:
	for k in chunks.keys():
		var mmi = chunks[k]
		if mmi == null:
			continue
		var mm: MultiMesh = mmi.multimesh
		var f := clampf(1.0 - (_chunk_dist(k, p) - 16.0) / (radius - 16.0), 0.3, 1.0)
		mm.visible_instance_count = int(mm.instance_count * f)

func _build_chunk(k: Vector2i) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(k)
	var n := int(CHUNK * CHUNK * PER_M2 * density)
	var x0 := k.x * CHUNK
	var z0 := k.y * CHUNK
	var clear_d: float = track.HALF_W + 1.9     # past the 1.4 m gravel shoulder
	# maps with slow queries: sample height + road distance on a small grid
	var gh := PackedFloat32Array()
	var gd := PackedFloat32Array()
	var gn := int(CHUNK / CELL) + 1
	if not fast_queries:
		gh.resize(gn * gn)
		gd.resize(gn * gn)
		for j in gn:
			for i in gn:
				var sx := x0 + i * CELL
				var sz := z0 + j * CELL
				gd[j * gn + i] = track.road_dist(sx, sz)
				gh[j * gn + i] = track.surface_h(sx, sz) if track.has_method("surface_h") else track.terrain_h(sx, sz)
		# whole chunk is road: nothing to plant
		var any := false
		for v in gd:
			if v > clear_d - CELL:
				any = true
				break
		if not any:
			chunks[k] = null
			return
	var xforms := []
	for i in n:
		var lx := rng.randf() * CHUNK
		var lz := rng.randf() * CHUNK
		var x := x0 + lx
		var z := z0 + lz
		var d: float
		var h: float
		if fast_queries:
			d = track.road_dist(x, z)
			if d < clear_d:
				continue
			h = track.surface_h(x, z)
		else:
			d = _bilerp(gd, gn, lx / CELL, lz / CELL)
			if d < clear_d:
				continue
			h = _bilerp(gh, gn, lx / CELL, lz / CELL)
		var s := rng.randf_range(0.75, 1.3)
		var hs := s * height * rng.randf_range(0.75, 1.25) * (0.6 if d < clear_d + 1.5 else 1.0)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, hs, s))
		xforms.append(Transform3D(b, Vector3(x, h - 0.04, z)))
	if xforms.is_empty():
		chunks[k] = null
		return
	var centre := Vector3(x0 + CHUNK * 0.5, xforms[0].origin.y, z0 + CHUNK * 0.5)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		var t: Transform3D = xforms[i]
		t.origin -= centre
		mm.set_instance_transform(i, t)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.position = centre
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	chunks[k] = mmi

static func _bilerp(g: PackedFloat32Array, n: int, fx: float, fz: float) -> float:
	var ix := clampi(int(fx), 0, n - 2)
	var iz := clampi(int(fz), 0, n - 2)
	var tx := fx - ix
	var tz := fz - iz
	var a := lerpf(g[iz * n + ix], g[iz * n + ix + 1], tx)
	var b := lerpf(g[(iz + 1) * n + ix], g[(iz + 1) * n + ix + 1], tx)
	return lerpf(a, b, tz)
