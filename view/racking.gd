class_name Racking
extends Node3D

## Racking a box by hand: pull one out, carry it, slide it into an empty unit.
##
## The crosshair picks the unit analytically rather than with a collider — a rack is a
## mesh plus a MultiMesh of chassis and has no bodies in it at all (CLAUDE.md, rules 1
## and 2), and giving every server a collider to make picking easy is exactly the
## trade the whole project is built to refuse. The rack's own transform turns the
## camera ray into rack space, and the unit is then a division.
##
## What moves is a single MeshInstance3D borrowed for the slide; the chassis leaves
## the MultiMesh the moment it starts coming out and rejoins it when it is home.

const REACH := 2.4           # metres the crosshair carries
const SLIDE := 0.55          # seconds a unit takes to come out or go in
const OUT := 0.62            # how far a chassis is drawn before it is free
const HELD := Vector3(0.30, -0.26, -0.62)   # where it rides, in camera space
const U := 0.04445
const DEEP := 0.75           # how far back a chassis runs from the cabinet face
const TOP_U := 35            # the highest unit a server can take; 36+ is panels
const EDGE := Color(0.98, 0.78, 0.22)
const EDGE_TAKE := Color(0.40, 0.86, 0.58)

var _wiring: Wiring
var _site: Object
var _bays: Array[Dictionary] = []
var _eye: Camera3D
var _edges: MeshInstance3D
var _ghost: MeshInstance3D            # the chassis in motion
var _carried: MeshInstance3D          # and the one in the player's hands
var _held := -1                       # device being carried, or -1
var _busy := false
var _aim := {}
var _message := ""


func setup(wiring: Wiring, site: Object, bays: Array[Dictionary], eye: Camera3D) -> void:
	_wiring = wiring
	_site = site
	_bays = bays
	_eye = eye

	_edges = MeshInstance3D.new()
	_edges.mesh = _wire_box()
	_edges.material_override = _glow(EDGE)
	_edges.visible = false
	add_child(_edges)

	_ghost = MeshInstance3D.new()
	_ghost.mesh = Assets.mesh("hardware/server_1u")
	_ghost.visible = false
	add_child(_ghost)


func hud_text() -> String:
	if _busy:
		return _message
	if _held >= 0:
		return ("X — вставить сервер в подсвеченный юнит" if _aim.has("free")
			else "в руках сервер · наведитесь на свободный юнит, X — вставить")
	if _aim.has("device"):
		return "X — вынуть сервер"
	return _message


func report() -> String:
	return "в руках %d, под прицелом %s, занят %s" % [
		_held,
		("юнит %d (свободен)" % _aim["slot"] if _aim.has("free")
			else ("сервер %d в юните %d" % [_aim["device"], _aim["slot"]]
				if _aim.has("device") else "ничего")),
		_busy]


func _process(_delta: float) -> void:
	if _eye == null or not is_instance_valid(_eye):
		return
	_aim = _pick()
	_edges.visible = not _aim.is_empty() and not _busy
	if not _edges.visible:
		return
	_edges.global_transform = _aim["box"]
	_edges.material_override = _glow(EDGE_TAKE if _aim.has("device") else EDGE)


func _unhandled_input(event: InputEvent) -> void:
	# Not gated on the pointer being captured: the checks run without grabbing it, and
	# the one thing that really must not answer X is a player sitting at the laptop.
	if _busy or _site.reading_screen():
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode != KEY_X:
		return
	if _held >= 0:
		if _aim.has("free"):
			_put_in()
	elif _aim.has("device"):
		_take_out()


# ------------------------------------------------------------------- picking

func _pick() -> Dictionary:
	## The first unit the crosshair actually enters, as a box and not as a height on a
	## plane. A plane gives the right answer only for a level ray: looking down at a
	## rack from standing height, the chassis face is eighty millimetres further along
	## than the cabinet face, and eighty millimetres of depth at that angle is most of
	## a unit.
	##
	## Anything standing in front of a cabinet hides it — another cabinet, a crate,
	## the parts of one being built. Only unit boxes were tested before, so the
	## crosshair read straight through whatever was in the way.
	var origin := _eye.global_position
	var dir := -_eye.global_transform.basis.z

	var shell := PackedFloat32Array()
	for bay in _bays:
		var inv := (bay["at_xform"] as Transform3D).affine_inverse()
		var face: float = bay["face_z"]
		var t := _enters(inv * origin, inv.basis * dir,
			Vector3(-0.32, 0.0, face - DEEP - 0.12), Vector3(0.32, 2.1, face + 0.06))
		shell.append(REACH if t < 0.05 else t)

	var loose := REACH
	for box in _site.solid_boxes():
		var inv: Transform3D = (box["xform"] as Transform3D).affine_inverse()
		var t := _enters(inv * origin, inv.basis * dir, -(box["half"] as Vector3),
			box["half"])
		if t >= 0.05:
			loose = minf(loose, t)

	var solid := {}
	var solid_at := REACH
	var open := {}
	var open_at := REACH
	for i in _bays.size():
		var bay: Dictionary = _bays[i]
		if _site.rack_busy(int(bay["entry"]["index"])):
			continue
		# anything nearer than this cabinet, other than this cabinet, is in the way
		var limit := loose
		for j in shell.size():
			if j != i:
				limit = minf(limit, shell[j])
		var xform: Transform3D = bay["at_xform"]
		var inv := xform.affine_inverse()
		var from := inv * origin
		var along := inv.basis * dir
		var face: float = bay["face_z"]
		var free: PackedInt32Array = bay["free"]
		for slot in range(1, TOP_U + 1):
			var low := 0.051 + slot * U
			var t := _enters(from, along, Vector3(-0.22, low, face - DEEP),
				Vector3(0.22, low + U, face))
			if t < 0.05 or t > limit + 0.02:
				continue
			if free.has(slot):
				if t < open_at:
					open = {"bay": bay, "xform": xform, "slot": slot}
					open_at = t
			elif t < solid_at:
				solid = {"bay": bay, "xform": xform, "slot": slot}
				solid_at = t

	## An open unit is air — looking down at a rack the ray crosses every open unit
	## above the one being aimed at, and treating those as walls meant nothing could
	## be picked from above. A blanking panel is not air, so it still blocks.
	if _held >= 0:
		if open.is_empty() or open_at > solid_at:
			return {}
		return _unit(open["bay"], open["slot"], open["xform"])
	if solid.is_empty():
		return {}
	return _unit(solid["bay"], solid["slot"], solid["xform"])


func _enters(from: Vector3, along: Vector3, low: Vector3, high: Vector3) -> float:
	## Slab test: where the ray goes into the box, or -1. Written out rather than given
	## an Area3D, for the same reason the rack has no colliders at all.
	var near := -INF
	var far := INF
	for axis in 3:
		if absf(along[axis]) < 1e-6:
			if from[axis] < low[axis] or from[axis] > high[axis]:
				return -1.0
			continue
		var a := (low[axis] - from[axis]) / along[axis]
		var b := (high[axis] - from[axis]) / along[axis]
		near = maxf(near, minf(a, b))
		far = minf(far, maxf(a, b))
	if far < maxf(near, 0.0):
		return -1.0
	return near


func _unit(bay: Dictionary, slot: int, xform: Transform3D) -> Dictionary:
	var y: float = 0.05 + slot * U + 0.001
	# The whole unit, not just its face: the part you look at when you mean to pull a
	# box is the box, and outlining a five-centimetre slab of it makes the rest look
	# like it is not the target.
	var box := Transform3D(Basis().scaled(Vector3(0.44, U * 0.86, 0.74)),
		Vector3(0.0, y + U * 0.5, float(bay["face_z"]) - 0.375))
	if _held >= 0:
		if not PackedInt32Array(bay["free"]).has(slot):
			return {}
		return {"bay": bay, "slot": slot, "free": true, "box": xform * box}
	var nth := _server_at(bay, y)
	if nth < 0:
		return {}
	var devices: PackedInt32Array = bay["server_dev"]
	if nth >= devices.size():
		return {}
	return {"bay": bay, "slot": slot, "nth": nth, "device": devices[nth],
		"box": xform * box}


func _server_at(bay: Dictionary, y: float) -> int:
	var placed: Array[Transform3D] = bay["server_tf"]
	for i in placed.size():
		if absf(placed[i].origin.y - y) < U * 0.4:
			return i
	return -1


# -------------------------------------------------------------------- moving

func _take_out() -> void:
	var bay: Dictionary = _aim["bay"]
	var nth: int = _aim["nth"]
	var slot: int = _aim["slot"]
	var device: int = _aim["device"]
	if device < 0:
		return
	var placed: Array[Transform3D] = bay["server_tf"]
	var seat := placed[nth]
	placed.remove_at(nth)
	var devices: PackedInt32Array = bay["server_dev"]
	devices.remove_at(nth)
	bay["server_dev"] = devices
	_refill(bay)

	_wiring.stow_server(device, true)
	var pulled := _wiring.unplug_device(device)
	_message = ("вынимаем сервер" if pulled == 0
		else "вынимаем сервер, снято шнуров: %d" % pulled)
	_wiring.refresh()

	var xform: Transform3D = bay["at_xform"]
	_ghost.global_transform = xform * seat
	_ghost.visible = true
	_slide(_ghost.global_transform, xform * seat.translated_local(Vector3(0, 0, OUT)),
		func() -> void:
			_ghost.visible = false
			_held = device
			_carry(true)
			var free: PackedInt32Array = bay["free"]
			free.append(slot)
			free.sort()
			bay["free"] = free
			_message = "")


func _put_in() -> void:
	var bay: Dictionary = _aim["bay"]
	var slot: int = _aim["slot"]
	var device := _held
	var seat := Transform3D(Basis(), Vector3(0, 0.05 + slot * U + 0.001, bay["face_z"]))
	var xform: Transform3D = bay["at_xform"]
	_carry(false)
	_held = -1
	_message = "ставим сервер"

	_ghost.global_transform = xform * seat.translated_local(Vector3(0, 0, OUT))
	_ghost.visible = true
	_slide(_ghost.global_transform, xform * seat,
		func() -> void:
			_ghost.visible = false
			var placed: Array[Transform3D] = bay["server_tf"]
			placed.append(seat)
			var devices: PackedInt32Array = bay["server_dev"]
			devices.append(device)
			bay["server_dev"] = devices
			_refill(bay)
			_wiring.move_server(bay["entry"], device, seat.origin, U, 0.75)
			_wiring.stow_server(device, false)
			_wiring.grew()
			var free: PackedInt32Array = bay["free"]
			var at := free.find(slot)
			if at >= 0:
				free.remove_at(at)
				bay["free"] = free
			_message = "сервер на месте — его ещё надо развести")


func _slide(from: Transform3D, to: Transform3D, then: Callable) -> void:
	_busy = true
	_edges.visible = false
	var move := create_tween()
	move.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	move.tween_method(
		func(t: float) -> void: _ghost.global_transform = from.interpolate_with(to, t),
		0.0, 1.0, SLIDE)
	move.finished.connect(func() -> void:
		then.call()
		_busy = false)


func _carry(on: bool) -> void:
	if not on:
		if _carried != null and is_instance_valid(_carried):
			_carried.queue_free()
		_carried = null
		return
	_carried = MeshInstance3D.new()
	_carried.mesh = Assets.mesh("hardware/server_1u")
	# tipped and held low, the way a 1U box is carried with two hands rather than
	# floating level in front of the face
	_carried.position = HELD
	_carried.rotation = Vector3(deg_to_rad(-12), deg_to_rad(14), 0)
	_eye.add_child(_carried)


func _refill(bay: Dictionary) -> void:
	var placed: Array[Transform3D] = bay["server_tf"]
	for key in ["servers", "servers_far"]:
		var pool: MultiMeshInstance3D = bay[key]
		pool.multimesh.instance_count = placed.size()
		for i in placed.size():
			pool.multimesh.set_instance_transform(i, placed[i])


# ------------------------------------------------------------------ geometry

func _wire_box() -> ArrayMesh:
	## Edges only: a filled highlight over a chassis hides the thing being pointed at,
	## and Godot's line width is one pixel whatever is asked for, which at this size is
	## exactly the thin outline wanted.
	var corners := PackedVector3Array()
	for i in 8:
		corners.append(Vector3(
			-0.5 + float(i & 1), -0.5 + float((i >> 1) & 1), -0.5 + float((i >> 2) & 1)))
	var lines := PackedVector3Array()
	for a in 8:
		for b in range(a + 1, 8):
			# neighbours on the cube differ in exactly one coordinate
			if (a ^ b) in [1, 2, 4]:
				lines.append(corners[a])
				lines.append(corners[b])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = lines
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return mesh


func _glow(colour: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Drawn through everything, because everything is in the way: from the front the
	# cabinet door, from the back the door and the cords. A depth-tested outline is
	# invisible exactly when it is needed. Its back edges did once read as a second
	# unit being lit, but that was the pick being wrong, not the drawing.
	mat.no_depth_test = true
	mat.render_priority = 8
	return mat
