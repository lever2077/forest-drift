# Mesh builder: collects triangles into named surfaces (one material each)
# and turns them into an ArrayMesh. Winding is fixed automatically so that
# the supplied normals always face the front side.
extends RefCounted

class Surf:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()

var surfaces := {}

func _s(key: String) -> Surf:
	if not surfaces.has(key):
		surfaces[key] = Surf.new()
	return surfaces[key]

func tri(key: String, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3,
		ca := Color.WHITE, cb := Color.WHITE, cc := Color.WHITE,
		ua := Vector2.ZERO, ub := Vector2.ZERO, uc := Vector2.ZERO) -> void:
	var s := _s(key)
	var fn := (b - a).cross(c - a)
	# Godot treats clockwise triangles as front faces.
	if fn.dot(na + nb + nc) > 0.0:
		s.v.append(a); s.v.append(c); s.v.append(b)
		s.n.append(na); s.n.append(nc); s.n.append(nb)
		s.c.append(ca); s.c.append(cc); s.c.append(cb)
		s.uv.append(ua); s.uv.append(uc); s.uv.append(ub)
	else:
		s.v.append(a); s.v.append(b); s.v.append(c)
		s.n.append(na); s.n.append(nb); s.n.append(nc)
		s.c.append(ca); s.c.append(cb); s.c.append(cc)
		s.uv.append(ua); s.uv.append(ub); s.uv.append(uc)

func quad(key: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, na: Vector3, nb: Vector3, nc: Vector3, nd: Vector3,
		col := Color.WHITE, ua := Vector2(0, 0), ub := Vector2(1, 0), uc := Vector2(1, 1), ud := Vector2(0, 1)) -> void:
	tri(key, a, b, c, na, nb, nc, col, col, col, ua, ub, uc)
	tri(key, a, c, d, na, nc, nd, col, col, col, ua, uc, ud)

func flat_quad(key: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3, col := Color.WHITE) -> void:
	var n := (b - a).cross(c - a).normalized()
	if n.dot(outward) < 0.0:
		n = -n
	quad(key, a, b, c, d, n, n, n, n, col)

static func xn(t: Transform3D, n: Vector3) -> Vector3:
	return (t.basis.inverse().transposed() * n).normalized()

func box(key: String, t: Transform3D, size: Vector3, col := Color.WHITE) -> void:
	var h := size * 0.5
	var axes := [[Vector3.RIGHT, Vector3.UP, Vector3.BACK], [Vector3.UP, Vector3.BACK, Vector3.RIGHT], [Vector3.BACK, Vector3.RIGHT, Vector3.UP]]
	for ax in axes:
		for sgn in [1.0, -1.0]:
			var d: Vector3 = (ax[0] as Vector3) * sgn
			var u: Vector3 = (ax[1] as Vector3) * h
			var w: Vector3 = (ax[2] as Vector3) * h
			var c0: Vector3 = d * h
			var nn := xn(t, d)
			quad(key, t * (c0 + u + w), t * (c0 + u - w), t * (c0 - u - w), t * (c0 - u + w), nn, nn, nn, nn, col)

# Solid of revolution around the local Y axis. profile = Array of Vector2(radius, y).
func lathe(key: String, t: Transform3D, profile: Array, seg: int, col := Color.WHITE, v_scale := 1.0) -> void:
	var cnt := profile.size()
	var pn := []
	for i in cnt:
		var a: Vector2 = profile[max(i - 1, 0)]
		var b: Vector2 = profile[min(i + 1, cnt - 1)]
		var tan := (b - a).normalized()
		pn.append(Vector2(tan.y, -tan.x))  # (dr, dy) normal in profile plane
	# orient normals away from the profile centroid
	var cen := Vector2.ZERO
	for p in profile:
		cen += p
	cen /= cnt
	for i in cnt:
		var p: Vector2 = profile[i]
		var nrm: Vector2 = pn[i]
		if nrm.dot(p - cen) < 0.0:
			pn[i] = -nrm
	for s in seg:
		var a0 := TAU * s / seg
		var a1 := TAU * (s + 1) / seg
		for i in cnt - 1:
			var p0: Vector2 = profile[i]
			var p1: Vector2 = profile[i + 1]
			var n0: Vector2 = pn[i]
			var n1: Vector2 = pn[i + 1]
			var v00 := Vector3(cos(a0) * p0.x, p0.y, sin(a0) * p0.x)
			var v10 := Vector3(cos(a1) * p0.x, p0.y, sin(a1) * p0.x)
			var v01 := Vector3(cos(a0) * p1.x, p1.y, sin(a0) * p1.x)
			var v11 := Vector3(cos(a1) * p1.x, p1.y, sin(a1) * p1.x)
			var m00 := Vector3(cos(a0) * n0.x, n0.y, sin(a0) * n0.x)
			var m10 := Vector3(cos(a1) * n0.x, n0.y, sin(a1) * n0.x)
			var m01 := Vector3(cos(a0) * n1.x, n1.y, sin(a0) * n1.x)
			var m11 := Vector3(cos(a1) * n1.x, n1.y, sin(a1) * n1.x)
			var u0 := float(s) / seg
			var u1 := float(s + 1) / seg
			quad(key, t * v00, t * v10, t * v11, t * v01, xn(t, m00), xn(t, m10), xn(t, m11), xn(t, m01), col,
				Vector2(u0, float(i) / (cnt - 1) * v_scale), Vector2(u1, float(i) / (cnt - 1) * v_scale),
				Vector2(u1, float(i + 1) / (cnt - 1) * v_scale), Vector2(u0, float(i + 1) / (cnt - 1) * v_scale))

func cylinder(key: String, t: Transform3D, r0: float, r1: float, h: float, seg: int, caps := true, col := Color.WHITE) -> void:
	var y0 := -h * 0.5
	var y1 := h * 0.5
	for s in seg:
		var a0 := TAU * s / seg
		var a1 := TAU * (s + 1) / seg
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var slope := (r0 - r1) / h
		var n0 := xn(t, (d0 + Vector3(0, slope, 0)).normalized())
		var n1 := xn(t, (d1 + Vector3(0, slope, 0)).normalized())
		quad(key, t * (d0 * r0 + Vector3(0, y0, 0)), t * (d1 * r0 + Vector3(0, y0, 0)),
			t * (d1 * r1 + Vector3(0, y1, 0)), t * (d0 * r1 + Vector3(0, y1, 0)), n0, n1, n1, n0, col,
			Vector2(float(s) / seg, 0), Vector2(float(s + 1) / seg, 0), Vector2(float(s + 1) / seg, 1), Vector2(float(s) / seg, 1))
		if caps:
			var up := xn(t, Vector3.UP)
			var dn := -up
			tri(key, t * Vector3(0, y1, 0), t * (d0 * r1 + Vector3(0, y1, 0)), t * (d1 * r1 + Vector3(0, y1, 0)), up, up, up, col, col, col)
			tri(key, t * Vector3(0, y0, 0), t * (d1 * r0 + Vector3(0, y0, 0)), t * (d0 * r0 + Vector3(0, y0, 0)), dn, dn, dn, col, col, col)

func ellipsoid(key: String, t: Transform3D, r: Vector3, seg_u := 16, seg_v := 10, col := Color.WHITE, y_min := -1.0) -> void:
	for j in seg_v:
		var b0 := lerpf(-PI / 2, PI / 2, float(j) / seg_v)
		var b1 := lerpf(-PI / 2, PI / 2, float(j + 1) / seg_v)
		if sin(b1) < y_min:
			continue
		for i in seg_u:
			var a0 := TAU * i / seg_u
			var a1 := TAU * (i + 1) / seg_u
			var u := [Vector3(cos(a0) * cos(b0), sin(b0), sin(a0) * cos(b0)), Vector3(cos(a1) * cos(b0), sin(b0), sin(a1) * cos(b0)),
				Vector3(cos(a1) * cos(b1), sin(b1), sin(a1) * cos(b1)), Vector3(cos(a0) * cos(b1), sin(b1), sin(a0) * cos(b1))]
			var pts := []
			var nrm := []
			for q in u:
				var qv: Vector3 = q
				pts.append(t * (qv * r))
				nrm.append(xn(t, Vector3(qv.x / r.x, qv.y / r.y, qv.z / r.z)))
			quad(key, pts[0], pts[1], pts[2], pts[3], nrm[0], nrm[1], nrm[2], nrm[3], col)

func torus(key: String, t: Transform3D, R: float, r: float, seg := 32, seg2 := 10, col := Color.WHITE) -> void:
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		for j in seg2:
			var b0 := TAU * j / seg2
			var b1 := TAU * (j + 1) / seg2
			var pts := []
			var nrm := []
			for ab in [[a0, b0], [a1, b0], [a1, b1], [a0, b1]]:
				var a: float = ab[0]
				var b: float = ab[1]
				var cdir := Vector3(cos(a), 0, sin(a))
				var nn := cdir * cos(b) + Vector3(0, sin(b), 0)
				pts.append(t * (cdir * R + nn * r))
				nrm.append(xn(t, nn))
			quad(key, pts[0], pts[1], pts[2], pts[3], nrm[0], nrm[1], nrm[2], nrm[3], col)

# A tapered beam between two points (used for wheel spokes etc.)
func beam(key: String, a: Vector3, b: Vector3, up: Vector3, w0: float, w1: float, h0: float, h1: float, col := Color.WHITE) -> void:
	var dir := (b - a).normalized()
	var side := dir.cross(up).normalized()
	var u2 := side.cross(dir).normalized()
	var c := []
	for e in [[a, w0, h0], [b, w1, h1]]:
		var p: Vector3 = e[0]
		var w: float = e[1]
		var h: float = e[2]
		c.append(p + side * w * 0.5 + u2 * h * 0.5)
		c.append(p - side * w * 0.5 + u2 * h * 0.5)
		c.append(p - side * w * 0.5 - u2 * h * 0.5)
		c.append(p + side * w * 0.5 - u2 * h * 0.5)
	var mid := (a + b) * 0.5
	flat_quad(key, c[0], c[1], c[5], c[4], u2, col)
	flat_quad(key, c[3], c[2], c[6], c[7], -u2, col)
	flat_quad(key, c[0], c[3], c[7], c[4], side, col)
	flat_quad(key, c[1], c[2], c[6], c[5], -side, col)
	flat_quad(key, c[4], c[5], c[6], c[7], dir, col)
	flat_quad(key, c[0], c[1], c[2], c[3], -dir, col)

func build(materials: Dictionary) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for key in surfaces.keys():
		var s: Surf = surfaces[key]
		if s.v.size() == 0:
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = s.v
		arrays[Mesh.ARRAY_NORMAL] = s.n
		arrays[Mesh.ARRAY_COLOR] = s.c
		arrays[Mesh.ARRAY_TEX_UV] = s.uv
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var idx := mesh.get_surface_count() - 1
		if materials.has(key):
			mesh.surface_set_material(idx, materials[key])
		mesh.surface_set_name(idx, key)
	return mesh
