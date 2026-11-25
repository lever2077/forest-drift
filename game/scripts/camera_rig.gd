# Desktop camera: chase / hood / cockpit (cycle with C). Mouse drag orbits in chase view.
extends Camera3D

var car
var mode := 0           # 0 chase, 1 hood, 2 cockpit
var smooth_dir := Vector3.FORWARD
var orbit := 0.0
var orbit_pitch := 0.0
var dragging := false
var base_fov := 70.0     # the view without the crash kick

const DRIVER_EYE := Vector3(-0.37, 1.07, 0.36)

func setup(p_car) -> void:
	car = p_car
	near = 0.05
	far = 2500.0
	fov = 70.0
	smooth_dir = -car.global_transform.basis.z
	global_position = car.global_position + Vector3(0, 2.5, 7)
	car.model.set_mirrors_active.call_deferred(mode == 2)

func cycle() -> void:
	mode = (mode + 1) % 3
	orbit = 0.0
	orbit_pitch = 0.0
	car.model.set_mirrors_active(mode == 2)   # the mirrors only draw from the driver's seat

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		dragging = event.pressed
	elif event is InputEventMouseMotion and dragging and mode == 0:
		orbit -= event.relative.x * 0.006
		orbit_pitch = clampf(orbit_pitch + event.relative.y * 0.004, -0.3, 0.8)

func _process(delta: float) -> void:
	if car == null or not current:
		return
	var ct: Transform3D = car.global_transform
	var spd: float = car.speed
	match mode:
		0:
			# follow a blend of heading and travel direction so drift angle is visible
			var head := -ct.basis.z
			head.y = 0
			head = head.normalized()
			var vdir: Vector3 = car.vel.normalized() if spd > 3.0 else head
			var want := head.lerp(vdir, 0.55).normalized()
			smooth_dir = smooth_dir.slerp(want, min(1.0, delta * 3.5)).normalized()
			if not dragging:
				orbit = lerpf(orbit, 0.0, min(1.0, delta * 1.5))
				orbit_pitch = lerpf(orbit_pitch, 0.0, min(1.0, delta * 1.5))
			var d := smooth_dir.rotated(Vector3.UP, orbit)
			var dist := 6.3 + spd * 0.025
			var target: Vector3 = car.global_position + Vector3(0, 1.0, 0)
			var pos := target - d * dist * cos(orbit_pitch) + Vector3(0, 1.4 + dist * sin(orbit_pitch), 0)
			var gh: float = car.track.ground_h(pos.x, pos.z) + 0.6
			pos.y = max(pos.y, gh)
			global_position = global_position.lerp(pos, min(1.0, delta * 9.0))
			look_at(target + smooth_dir * 2.0, Vector3.UP)
			base_fov = lerpf(base_fov, 68.0 + clampf(spd * 0.25, 0.0, 16.0), min(1.0, delta * 2.0))
		1:
			global_transform = Transform3D(ct.basis, ct * Vector3(0, 1.02, -0.6))
			base_fov = 75.0
		2:
			var b: Basis = car.model.body.global_transform.basis
			global_transform = Transform3D(b, car.model.body.global_transform * DRIVER_EYE)
			base_fov = 72.0
	fov = base_fov
	# crash shake: a sharp jolt that dies away (strongest from inside the car)
	var s: float = car.shake
	if s > 0.001:
		var k := s * s * (0.28 if mode == 0 else 0.12)
		var t := Time.get_ticks_msec() * 0.001
		global_position += Vector3(sin(t * 61.0) + sin(t * 23.0) * 0.5, sin(t * 53.0 + 1.3), sin(t * 47.0 + 2.1)) * k
		rotate_object_local(Vector3.FORWARD, sin(t * 37.0) * s * s * 0.05)
		rotate_object_local(Vector3.RIGHT, sin(t * 43.0 + 0.7) * s * s * 0.03)
		# a small kick on top of the normal view (it used to add up every frame
		# and zoom far out on a big crash)
		fov = base_fov + s * 1.5
