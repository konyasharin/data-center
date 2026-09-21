class_name Wiring
extends Node3D

## Patching you can actually do: look at a socket, click, look at the other socket,
## click again.
##
## Every rule lives in the C# core (sim/Cabling) and is reached through CablingBridge.
## This file owns only what the core must never know about — where a port sits in the
## world, what colour a cable is, and which one the crosshair is on.
##
## Ports are not nodes and servers are not nodes (CLAUDE.md, rules 1 and 2). A port is
## an index into flat arrays here, exactly as it is an index into flat arrays over
## there, and the markers are one MultiMesh for the whole hall.

const Kind := {SERVER = 0, PDU = 1, SWITCH = 2, PATCH = 3}
const Line := {POWER = 0, NETWORK = 1}
const FeedId := {NONE = 0, A = 1, B = 2}

# mirrors ConnectResult in sim/Cabling/Cabling.cs
const RESULT_TEXT := [
	"подключено",
	"питание и сеть — разные кабели",
	"порт уже занят",
	"это то же самое устройство",
	"слишком далеко: питание не выходит из стойки, сеть достаёт до соседней",
	"свободных портов не осталось",
	"неизвестный порт",
	"питание берётся только из PDU",
]

const POWER_STATE := {UNPOWERED = 0, SINGLE = 1, REDUNDANT = 2}
const ONLINE_BIT := 1 << 2
const ONE_FEED_BIT := 1 << 3

const REACH := 2.6           # metres: how far the player can plug something in
const PICK_CONE := 0.055     # radians-ish: half-angle the crosshair forgives
const MARKER := 0.011
const CABLE_R := 0.003
const SAG := 0.16            # of the span, how far a loose cord droops
const CHANNEL_X := 0.25      # vertical cable channel, inside the frame upright
const CHANNEL_Z := -0.515    # as far back as a cord may sit before the rear door

const COLOUR := {
	"free_power": Color(0.42, 0.42, 0.45),
	"free_network": Color(0.30, 0.42, 0.38),
	"feed_a": Color(0.78, 0.18, 0.14),
	"feed_b": Color(0.20, 0.38, 0.82),
	"network": Color(0.22, 0.62, 0.30),
	"hover": Color(1.0, 1.0, 1.0),
	"held": Color(1.0, 0.85, 0.2),
	"blocked": Color(1.0, 0.25, 0.2),
}

const STATUS_COLOUR := {
	"dark": Color(0.35, 0.05, 0.05),
	"offline": Color(0.55, 0.2, 0.75),
	"exposed": Color(0.95, 0.62, 0.08),
	"single": Color(0.85, 0.78, 0.15),
	"ok": Color(0.15, 0.75, 0.25),
}

var _bridge := CablingBridge.new()

# port -> world
var _port_pos := PackedVector3Array()
var _port_out := PackedVector3Array()   # outward normal, where a cable leaves the socket
var _port_line := PackedInt32Array()
var _port_rack := PackedInt32Array()   # index into _racks, for routing in rack space

# device bookkeeping the scene needs and the core does not
var _servers := PackedInt32Array()
var _server_pos := PackedVector3Array()
var _server_out := PackedVector3Array()
var _racks: Array[Dictionary] = []

var _markers: MultiMeshInstance3D
var _status: MultiMeshInstance3D
var _cables: MeshInstance3D
var _ghost: MeshInstance3D
var _held := -1
var _hover := -1
var _message := ""
var _message_at := 0.0


# ------------------------------------------------------------------ building

func rack(index: int, xform: Transform3D) -> Dictionary:
	## Called by the scene builder once per cabinet, before any device is added.
	var entry := {
		"index": index,
		"xform": xform,
		"servers": PackedInt32Array(),
		"feed_a": PackedInt32Array(),
		"feed_b": PackedInt32Array(),
		"uplinks": PackedInt32Array(),
		"port_from": _port_pos.size(),
		"port_to": _port_pos.size(),
	}
	_racks.append(entry)
	return entry


func add_server(entry: Dictionary, at: Vector3, height: float, depth: float) -> int:
	## `at` is the chassis origin in rack space; the body runs from there toward -Z,
	## so every socket is on the plane just behind its back face.
	var device: int = _bridge.AddDevice(Kind.SERVER, entry["index"], 2, 1, FeedId.NONE)
	var z := -(depth + 0.003)
	var y := height * 0.5
	# two PSU inlets where the supplies actually are, NIC between them
	_port(entry, device, at + Vector3(-0.142, y, z))
	_port(entry, device, at + Vector3(0.142, y, z))
	_port(entry, device, at + Vector3(0.0, y - 0.008, z))

	entry["servers"].append(device)
	_servers.append(device)
	_server_pos.append(entry["xform"] * (at + Vector3(0.0, y + 0.010, z)))
	_server_out.append(entry["xform"].basis * Vector3(0, 0, -1))
	return device


func add_strip(entry: Dictionary, at: Vector3, feed: int, outlets := 16) -> int:
	## A 0U strip down the back channel. Outlets face the aisle, which is where the
	## person doing the patching is standing.
	var device: int = _bridge.AddDevice(Kind.PDU, entry["index"], outlets, 0, feed)
	var span := 1.5 - 0.2
	for i in outlets:
		var z := 0.08 + i * span / float(outlets - 1)
		_port(entry, device, at + Vector3(0.0, z, -0.030))
	if feed == FeedId.A:
		entry["feed_a"].append(device)
	else:
		entry["feed_b"].append(device)
	return device


func add_panel(entry: Dictionary, centre: Vector3, kind: int, ports: int,
		width: float, row_gap: float) -> int:
	## `centre` is the middle of the port face in rack space. One row when row_gap is
	## zero, two when it is not — which is how the models are drawn.
	var device: int = _bridge.AddDevice(kind, entry["index"], 0, ports, FeedId.NONE)
	var rows := 2 if row_gap > 0.0 else 1
	var per_row := ports / rows
	for i in ports:
		var row := i / per_row
		var col := i % per_row
		var x := (col - (per_row - 1) * 0.5) * (width / per_row)
		var y := (row - (rows - 1) * 0.5) * row_gap
		_port(entry, device, centre + Vector3(x, y, 0.0))
	if kind == Kind.SWITCH:
		entry["uplinks"].append(device)
	return device


func _port(entry: Dictionary, _device: int, local: Vector3) -> void:
	var xform: Transform3D = entry["xform"]
	_port_pos.append(xform * local)
	_port_rack.append(_racks.size() - 1)
	entry["port_to"] = _port_pos.size()
	# sockets on a rear panel point back down the hot aisle; a PDU outlet points the
	# same way, which is why the strip is turned round when the scene places it
	_port_out.append((xform.basis * Vector3(0, 0, -1)).normalized())
	# the core hands out ports in the order devices are added, so its index and ours
	# are the same number — asserted in build()
	_port_line.append(_bridge.LineOf(_port_pos.size() - 1))


func build() -> void:
	# Our arrays are indexed by the core's port ids. Nothing enforces that but the
	# order of the calls above, so check it once rather than debug crossed cables.
	var expected := 0
	for device in _bridge.DeviceCount():
		expected += _bridge.PortCountOf(device)
	if expected != _port_pos.size():
		push_error("wiring: %d ports in the core, %d placed in the scene"
			% [expected, _port_pos.size()])

	print("wiring: %d racks, %d servers, %d ports" % [
		_racks.size(), _servers.size(), _port_pos.size()])

	_markers = MultiMeshInstance3D.new()
	_markers.multimesh = _sprite_mesh(_port_pos.size())
	_markers.material_override = _flat_material()
	add_child(_markers)

	_status = MultiMeshInstance3D.new()
	_status.multimesh = _sprite_mesh(_servers.size(), 0.014)
	_status.material_override = _flat_material()
	add_child(_status)

	_cables = MeshInstance3D.new()
	_cables.material_override = _cable_material()
	add_child(_cables)

	# the cord being dragged is its own mesh: it is rebuilt every frame, and the other
	# few hundred are not
	_ghost = MeshInstance3D.new()
	_ghost.material_override = _cable_material()
	add_child(_ghost)

	for i in _port_pos.size():
		_markers.multimesh.set_instance_transform(i, _facing(_port_pos[i], _port_out[i]))
	for i in _servers.size():
		_status.multimesh.set_instance_transform(i, _facing(_server_pos[i], _server_out[i]))

	refresh()


# ------------------------------------------------------------------ actions

func wire_rack(entry: Dictionary, mistake_in := 0, seed_value := 1) -> void:
	var report: PackedInt32Array = _bridge.WireRack(
		entry["servers"], entry["feed_a"], entry["feed_b"], entry["uplinks"],
		mistake_in, seed_value)
	_say("стойка %d: серверов %d, питание %d, сеть %d, промахов %d%s" % [
		entry["index"], report[0], report[1], report[2], report[3],
		"" if report[4] == 0 else ", не хватило портов: %d" % report[4]])
	if report[4] > 0 or report[5] > 0:
		push_warning("rack %d: %d ports short, %d refused" % [
			entry["index"], report[4], report[5]])
	refresh()


func racks() -> Array[Dictionary]:
	return _racks


func clear_message() -> void:
	_message = ""


func refresh() -> void:
	_paint_markers()
	_paint_status()
	_cables.mesh = _cable_mesh()
	_ghost.mesh = _ghost_mesh()


func _paint_markers() -> void:
	for port in _port_pos.size():
		_markers.multimesh.set_instance_color(port, _marker_colour(port))


func _marker_colour(port: int) -> Color:
	if port == _held:
		return COLOUR["held"]
	if port == _hover:
		if _held >= 0:
			var verdict: int = _bridge.CanConnect(_held, port)
			return COLOUR["hover"] if verdict == 0 else COLOUR["blocked"]
		return COLOUR["hover"]

	if _bridge.IsFree(port):
		return (COLOUR["free_power"] if _port_line[port] == Line.POWER
			else COLOUR["free_network"])
	return _line_colour(port)


func _line_colour(port: int) -> Color:
	if _port_line[port] == Line.NETWORK:
		return COLOUR["network"]
	# a power cord is coloured by the feed it lands on, which is the whole point of
	# being able to see the wiring at all
	var feed := _feed_of_link(port)
	return COLOUR["feed_a"] if feed == FeedId.A else (
		COLOUR["feed_b"] if feed == FeedId.B else COLOUR["free_power"])


func _feed_of_link(port: int) -> int:
	var mine: int = _bridge.FeedOf(_bridge.OwnerOf(port))
	if mine != FeedId.NONE:
		return mine
	var other: int = _bridge.OtherEnd(port)
	return FeedId.NONE if other < 0 else _bridge.FeedOf(_bridge.OwnerOf(other))


func _paint_status() -> void:
	for i in _servers.size():
		_status.multimesh.set_instance_color(i, _status_colour(_bridge.Status(_servers[i])))


func _status_colour(bits: int) -> Color:
	var power := bits & 0x3
	if power == POWER_STATE.UNPOWERED:
		return STATUS_COLOUR["dark"]
	if (bits & ONLINE_BIT) == 0:
		return STATUS_COLOUR["offline"]
	if (bits & ONE_FEED_BIT) != 0:
		return STATUS_COLOUR["exposed"]
	if power == POWER_STATE.SINGLE:
		return STATUS_COLOUR["single"]
	return STATUS_COLOUR["ok"]


func _click() -> void:
	if _hover < 0:
		if _held >= 0:
			_held = -1
			_say("кабель убран")
		return

	if _held < 0:
		if not _bridge.IsFree(_hover):
			_say("порт занят — ПКМ, чтобы выдернуть")
			return
		_held = _hover
		_say("держим конец: %s" % _describe(_hover))
		return

	var result: int = _bridge.Connect(_held, _hover)
	_say(RESULT_TEXT[result] if result < RESULT_TEXT.size() else "отказ %d" % result)
	if result == 0:
		_held = -1
	refresh()


func _unplug() -> void:
	if _held >= 0:
		_held = -1
		_say("кабель убран")
		return
	if _hover < 0:
		return
	var link: int = _bridge.LinkOf(_hover)
	if link < 0:
		_say("здесь ничего не воткнуто")
		return
	_bridge.Disconnect(link)
	_say("выдернуто")
	refresh()


func drop_feed(feed: int) -> void:
	var pulled: int = _bridge.DisconnectFeed(feed)
	_say("луч %s уведён на обслуживание: снято %d шнуров" % [
		"A" if feed == FeedId.A else "B", pulled])
	refresh()


func rack_at(point: Vector3) -> Dictionary:
	var best := {}
	var best_d := 2.5
	for entry in _racks:
		var d: float = (entry["xform"].origin - point).length()
		if d < best_d:
			best_d = d
			best = entry
	return best


# ------------------------------------------------------------------ input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_click()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_unplug()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_R:
				var camera := get_viewport().get_camera_3d()
				if camera != null:
					var entry := rack_at(camera.global_position)
					if entry.is_empty():
						_say("встаньте у стойки")
					else:
						wire_rack(entry)
			KEY_T:
				drop_feed(FeedId.A)


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var found := _pick(camera)
	if found != _hover:
		_hover = found
		_paint_markers()
	if _held >= 0:
		_ghost.mesh = _ghost_mesh()


func _pick(camera: Camera3D) -> int:
	var origin := camera.global_position
	var forward := -camera.global_transform.basis.z
	var best := -1
	var best_score := INF
	# a hall is thousands of ports and this runs every frame, so only the cabinets
	# within arm's reach are worth walking
	for entry in _racks:
		if (entry["xform"].origin - origin).length() > REACH + 1.3:
			continue
		for port in range(entry["port_from"], entry["port_to"]):
			var to_port: Vector3 = _port_pos[port] - origin
			var along := to_port.dot(forward)
			if along < 0.12 or along > REACH:
				continue
			# forgive a wider miss further away, or distant ports are unpickable
			var off := (to_port - forward * along).length()
			if off > PICK_CONE * along:
				continue
			var score := off / along + along * 0.02
			if score < best_score:
				best_score = score
				best = port
	return best


# ------------------------------------------------------------------ geometry

func _cable_mesh() -> ArrayMesh:
	## Rebuilt only when the patching changes (docs/10: cables are procedural geometry,
	## not a node per cord). One mesh for the hall, coloured per vertex.
	var links: PackedInt32Array = _bridge.LiveLinks()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var i := 0
	while i < links.size():
		_tube(st, _route(links[i], links[i + 1]), _line_colour(links[i]))
		i += 2

	st.generate_normals()
	return st.commit()


func _ghost_mesh() -> ArrayMesh:
	if _held < 0:
		return null
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null
	var tip: Vector3 = _port_pos[_hover] if _hover >= 0 else (
		camera.global_position + (-camera.global_transform.basis.z) * 0.5)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_run(st, _port_pos[_held], _port_out[_held], tip,
		_port_out[_hover] if _hover >= 0 else Vector3.UP, COLOUR["held"])
	st.generate_normals()
	return st.commit()


func _route(from_port: int, to_port: int) -> PackedVector3Array:
	## Cords do not fly across a cabinet: they leave the socket, go sideways into the
	## vertical channel at the edge of the rack, run up or down it, and come back in.
	## Routing them properly is also what stops forty cables reading as one grey mush.
	var entry: Dictionary = _racks[_port_rack[from_port]]
	var xform: Transform3D = entry["xform"]
	var inv := xform.affine_inverse()
	var a := inv * _port_pos[from_port]
	var b := inv * _port_pos[to_port]

	# the channel on the side the far end is already on, and a depth that depends on
	# the port so a bundle looks like many cords rather than one slab
	var side := signf(b.x if absf(b.x) > absf(a.x) else a.x)
	var channel := CHANNEL_X * (1.0 if side == 0.0 else side)
	var z := maxf(minf(a.z, b.z) - 0.02 - (from_port % 5) * 0.004, CHANNEL_Z)

	var points := PackedVector3Array([
		a,
		Vector3(a.x, a.y, a.z - 0.02),
		Vector3(channel, a.y, z),
		Vector3(channel, b.y, z),
		Vector3(b.x, b.y, b.z - 0.02),
		b,
	])
	points = _smooth(_smooth(points))
	for i in points.size():
		points[i] = xform * points[i]
	return points


func _smooth(points: PackedVector3Array) -> PackedVector3Array:
	## Chaikin: cuts every corner and leaves the two ends where the sockets are.
	var out := PackedVector3Array([points[0]])
	for i in points.size() - 1:
		var p: Vector3 = points[i]
		var q: Vector3 = points[i + 1]
		out.append(p.lerp(q, 0.25))
		out.append(p.lerp(q, 0.75))
	out.append(points[points.size() - 1])
	return out


func _run(st: SurfaceTool, from: Vector3, from_out: Vector3, to: Vector3,
		to_out: Vector3, colour: Color) -> void:
	# the cord being dragged has no rack to route through yet, so it just droops
	var span := from.distance_to(to)
	var lift := from + from_out * minf(0.06, span * 0.3)
	var land := to + to_out * minf(0.06, span * 0.3)
	var sag := Vector3.DOWN * (span * SAG)

	var points := PackedVector3Array()
	var steps := 9
	for i in steps + 1:
		var t := float(i) / steps
		points.append(_bezier(from, lift + sag, land + sag, to, t))
	_tube(st, points, colour)


func _bezier(a: Vector3, b: Vector3, c: Vector3, d: Vector3, t: float) -> Vector3:
	var u := 1.0 - t
	return (a * (u * u * u) + b * (3.0 * u * u * t) + c * (3.0 * u * t * t)
		+ d * (t * t * t))


func _tube(st: SurfaceTool, points: PackedVector3Array, colour: Color) -> void:
	## Square section: four sides read as round at cable thickness and cost a third of
	## what a real ring does, across a hall full of cords.
	var sides := 4
	var rings: Array[PackedVector3Array] = []
	for i in points.size():
		var ahead: Vector3 = points[mini(i + 1, points.size() - 1)]
		var behind: Vector3 = points[maxi(i - 1, 0)]
		var dir := (ahead - behind).normalized()
		if dir.length_squared() < 0.5:
			dir = Vector3.FORWARD
		var right := dir.cross(Vector3.UP)
		if right.length_squared() < 1e-6:
			right = Vector3.RIGHT
		right = right.normalized()
		var up := right.cross(dir).normalized()

		var ring := PackedVector3Array()
		for s in sides:
			var a := TAU * s / sides
			ring.append(points[i] + (right * cos(a) + up * sin(a)) * CABLE_R)
		rings.append(ring)

	for i in rings.size() - 1:
		for s in sides:
			var n := (s + 1) % sides
			_quad(st, rings[i][s], rings[i][n], rings[i + 1][n], rings[i + 1][s], colour)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		colour: Color) -> void:
	for v in [a, b, c, a, c, d]:
		st.set_color(colour)
		st.add_vertex(v)


func _sprite_mesh(count: int, size := MARKER) -> MultiMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = count
	return mm


func _facing(at: Vector3, normal: Vector3) -> Transform3D:
	var up := Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	return Transform3D(Basis.looking_at(-normal, up), at + normal * 0.002)


func _flat_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.billboard_keep_scale = true
	mat.no_depth_test = false
	return mat


func _cable_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.75
	mat.metallic = 0.0
	return mat


# ------------------------------------------------------------------ readout

func _describe(port: int) -> String:
	var device: int = _bridge.OwnerOf(port)
	var kind: int = _bridge.KindOf(device)
	var names := ["сервер", "PDU", "коммутатор", "патч-панель"]
	var line := "питание" if _port_line[port] == Line.POWER else "сеть"
	var feed: int = _bridge.FeedOf(device)
	var tail := ""
	if feed == FeedId.A:
		tail = " (луч A)"
	elif feed == FeedId.B:
		tail = " (луч B)"
	return "%s, %s%s, стойка %d" % [names[kind], line, tail, _bridge.RackOf(device)]


func _say(text: String) -> void:
	_message = text
	_message_at = Time.get_ticks_msec() / 1000.0


func hud_text() -> String:
	var lines := PackedStringArray()
	if _hover >= 0:
		var state := "свободен" if _bridge.IsFree(_hover) else "занят"
		lines.append("%s — %s" % [_describe(_hover), state])
		if _held >= 0:
			var verdict: int = _bridge.CanConnect(_held, _hover)
			lines.append("ЛКМ: %s" % RESULT_TEXT[verdict])
	elif _held >= 0:
		lines.append("держим кабель — наведитесь на порт")
	else:
		lines.append("наведитесь на порт: ЛКМ — взять, ПКМ — выдернуть")
	lines.append("R — подключить стойку целиком, T — увести луч A")
	if not _message.is_empty() and Time.get_ticks_msec() / 1000.0 - _message_at < 6.0:
		lines.append("» %s" % _message)
	return "\n".join(lines)

