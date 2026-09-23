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
	if _busy or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
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
	## The unit the crosshair is on: a free one to fill, or a chassis to pull. Only one
	## of the two is offered at a time, because only one of them can be done.
	## The nearest cabinet the crosshair touches, and then that cabinet only. Taking
	## the nearest cabinet that happens to hold a takeable chassis instead means a
	## blanking panel is see-through: you look at it and a server in the rack behind
	## lights up.
	var origin := _eye.global_position
	var dir := -_eye.global_transform.basis.z
	var front := {}
	var front_at := REACH
	for bay in _bays:
		if _site.rack_busy(int(bay["entry"]["index"])):
			continue
		var xform: Transform3D = bay["at_xform"]
		var inv := xform.affine_inverse()
		var from := inv * origin
		var along := inv.basis * dir
		if absf(along.z) < 0.001:
			continue
		var t := (float(bay["face_z"]) - from.z) / along.z
		if t <= 0.05 or t >= front_at:
			continue
		var hit := from + along * t
		if absf(hit.x) > 0.26 or hit.y < 0.05 or hit.y > 0.05 + 41.0 * U:
			continue
		front = {"bay": bay, "xform": xform, "slot": floori((hit.y - 0.051) / U)}
		front_at = t
	if front.is_empty():
		return {}
	return _unit(front["bay"], front["slot"], front["xform"])


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
	# Depth-tested, unlike most highlights. Drawn through everything, the back edges of
	# a 750 mm box sit low on the screen and over the units below it — which is what
	# read as the wrong unit being picked.
	mat.render_priority = 8
	return mat
