# The ocean (Beach biome): one flat water surface that follows the camera, so
# the sea runs on without a break to the horizon. Shallow water near the beach
# is turquoise and see-through with a line of foam, deep water dark blue
# (worked out from the scene depth behind the water). Used by Endless Road
# (sea on the left of the road) and the loop maps (sea outside the loop).
extends Node3D

const SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, specular_schlick_ggx;
uniform sampler2D ripple_a : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D ripple_b : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;
uniform vec3 shallow : source_color = vec3(0.12, 0.72, 0.7);
uniform vec3 deep : source_color = vec3(0.02, 0.16, 0.3);
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 vp = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	vp.xyz /= vp.w;
	float depth = clamp(VERTEX.z - vp.z, 0.0, 40.0);
	float k = smoothstep(0.0, 6.0, depth);
	vec3 c = mix(shallow, deep, k);
	float foam = 1.0 - smoothstep(0.0, 0.45, depth);
	foam *= 0.6 + 0.4 * sin(TIME * 1.5 + wpos.x * 0.7 + wpos.z * 0.5);
	ALBEDO = mix(c, vec3(0.95), foam * 0.8);
	ALPHA = clamp(0.45 + k * 0.55 + foam * 0.5, 0.0, 1.0);
	ROUGHNESS = 0.06;
	METALLIC = 0.0;
	SPECULAR = 0.6;
	vec2 uv = wpos.xz;
	vec3 n1 = texture(ripple_a, uv * 0.05 + vec2(TIME * 0.012, TIME * 0.007)).rgb;
	vec3 n2 = texture(ripple_b, uv * 0.11 - vec2(TIME * 0.009, -TIME * 0.013)).rgb;
	NORMAL_MAP = normalize(n1 + n2 - 1.0) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.6;
}
"""

var level := 0.0
var mi: MeshInstance3D

func setup(p_level: float) -> void:
	level = p_level
	var pm := PlaneMesh.new()
	pm.size = Vector2(9000, 9000)
	mi = MeshInstance3D.new()
	mi.name = "Water"
	mi.mesh = pm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sh := Shader.new()
	sh.code = SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("ripple_a", _ripples(0.06))
	m.set_shader_parameter("ripple_b", _ripples(0.11))
	mi.material_override = m
	add_child(mi)
	mi.position = Vector3(0, level, 0)

func _process(_delta: float) -> void:
	# keep the water under the camera (it's flat, so the move never shows)
	var cam := get_viewport().get_camera_3d()
	if cam and mi:
		mi.global_position = Vector3(round(cam.global_position.x), level, round(cam.global_position.z))

func _ripples(freq: float) -> NoiseTexture2D:
	var nt := NoiseTexture2D.new()
	var fn := FastNoiseLite.new()
	fn.frequency = freq
	fn.fractal_octaves = 4
	nt.noise = fn
	nt.width = 512
	nt.height = 512
	nt.seamless = true
	nt.as_normal_map = true
	nt.bump_strength = 4.0
	return nt
