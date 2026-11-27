# Another player's car in an online game: just the look (their car model, skin
# and a name tag above it), following the positions net.gd receives. It glides
# between updates and keeps going a moment if one is late, so it moves
# smoothly. It has no physics of its own: cars pass through each other.
extends Node3D

const CarModel = preload("res://scripts/car_model.gd")
const CarModelExt = preload("res://scripts/car_model_ext.gd")
const Profile = preload("res://scripts/profile.gd")
const WHEEL_R := 0.33

var model
var tag: Label3D
var car_id := ""
var skin := ""
var target := Transform3D()
var have_target := false
var steer := 0.0
var speed := 0.0

func setup(p_name: String, p_car: String, p_skin: String) -> void:
	_build_model(p_car, p_skin)
	tag = Label3D.new()
	tag.text = p_name
	tag.font_size = 56
	tag.pixel_size = 0.006
	tag.outline_size = 10
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.fixed_size = false
	tag.modulate = Color(1.0, 0.85, 0.4)
	tag.position = Vector3(0, 2.1, 0)
	add_child(tag)

func _build_model(p_car: String, p_skin: String) -> void:
	if model:
		model.queue_free()
	car_id = p_car
	skin = p_skin
	var def: Dictionary = Profile.CARS.get(p_car, Profile.CARS[Profile.STOCK_CAR])
	if String(def.get("model", "")) != "":
		model = CarModelExt.new()
		model.def = def
	else:
		model = CarModel.new()
	add_child(model)
	model.build()
	model.set_paint(Profile.skin_color(p_skin), Profile.skin_neon(p_skin))

# called by main every frame with this player's latest info from net.gd
func apply(info: Dictionary, delta: float) -> void:
	if String(info.get("car", car_id)) != car_id or String(info.get("skin", skin)) != skin:
		_build_model(String(info.get("car", car_id)), String(info.get("skin", skin)))
	if tag and String(info.get("name", "")) != "" and tag.text != info["name"]:
		tag.text = info["name"]
	if info.has("xf"):
		var xf: Transform3D = info["xf"]
		speed = float(info.get("speed", 0.0))
		steer = float(info.get("steer", 0.0))
		# a little ahead along its heading for the time since the last update
		# (they come 20 times a second), so it doesn't stutter
		var age := (Time.get_ticks_msec() - int(info.get("t", 0))) / 1000.0
		var fwd := -xf.basis.z
		xf.origin += fwd * speed * clampf(age, 0.0, 0.25)
		target = xf
		if not have_target:
			global_transform = target
			have_target = true
		if model:
			model.set_brake(bool(info.get("brake", false)))
	if have_target:
		var k := 1.0 - exp(-delta * 14.0)
		var gt := global_transform
		var q := gt.basis.get_rotation_quaternion().slerp(target.basis.get_rotation_quaternion(), k)
		global_transform = Transform3D(Basis(q), gt.origin.lerp(target.origin, k))
		# a big jump (they reset to the road): snap
		if gt.origin.distance_to(target.origin) > 12.0:
			global_transform = target
	if model:
		var spin := speed / WHEEL_R
		model.update_visuals(steer, spin, spin, 0.0, 0.0, delta)
