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

# packed by CablingBridge.PortStates
const LINE_BIT := 1
const FREE_BIT := 1 << 1
const FEED_SHIFT := 2

const POWER_STATE := {UNPOWERED = 0, SINGLE = 1, REDUNDANT = 2}
const ONLINE_BIT := 1 << 2
const ONE_FEED_BIT := 1 << 3

const REACH := 2.6           # metres: how far the player can plug something in
const PICK_CONE := 0.055     # radians-ish: half-angle the crosshair forgives
const MARKER := 0.009
const CABLE_R := 0.0025
const SAG := 0.16            # of the span, how far a loose cord droops
# must match tools/blender/dclib/units.py: the gaps between the duct's fingers
const SPINE_PITCH := 0.09
const SPINE_BASE := 0.10
const SPINE_CLIPS := 18
const CLIP_SPREAD := 0.004   # how far apart cords sit inside one gap
const CLIP_FULL := 16        # cords in one gap before it reads as stuffed
# outlets up a PDU strip; mirrors PDU_* in tools/blender/dclib/units.py
const OUTLETS := 24
const OUTLET_BASE := 0.08
const OUTLET_SPAN := 1.3

const COLOUR := {
	"free_power": Color(0.14, 0.15, 0.18),
	"free_network": Color(0.12, 0.18, 0.15),
	"feed_a": Color(0.78, 0.18, 0.14),
	"feed_b": Color(0.20, 0.38, 0.82),
	"network": Color(0.22, 0.62, 0.30),
	"hover": Color(1.0, 1.0, 1.0),
	"held": Color(1.0, 0.85, 0.2),
	"blocked": Color(1.0, 0.25, 0.2),
	"clip_free": Color(0.42, 0.45, 0.52),
	"clip_used": Color(0.30, 0.34, 0.40),
	"stuffed": Color(0.80, 0.45, 0.10),
	# lit while a cord is in hand
	"open_power": Color(0.90, 0.88, 0.60),
	"open_network": Color(0.55, 0.90, 0.70),
	"clip_open": Color(0.85, 0.90, 1.00),
}

const STATUS_COLOUR := {
	"dark": Color(0.35, 0.05, 0.05),
	"offline": Color(0.55, 0.2, 0.75),
	"exposed": Color(0.95, 0.62, 0.08),
	"single": Color(0.62, 0.56, 0.10),
	"ok": Color(0.10, 0.42, 0.16),
}

var _bridge: CablingBridge

# port -> world
var _port_pos := PackedVector3Array()
var _port_out := PackedVector3Array()   # outward normal, where a cable leaves the socket
var _port_line := PackedInt32Array()
var _port_rack := PackedInt32Array()   # index into _racks, for routing in rack space

# Attachment points on the vertical ducts. These are not devices and the core knows
# nothing about them: a cord works the same whether it is dressed in or thrown across
# the cabinet. What they change is whether the rack can be read at a glance.
var _clip_pos := PackedVector3Array()
var _clip_out := PackedVector3Array()
var _clip_load := PackedInt32Array()
var _states := PackedInt32Array()      # per port, packed by the bridge
var _routes := {}                      # link -> the clips a cord is dressed into
var _held_route := PackedInt32Array()

# device bookkeeping the scene needs and the core does not
var _servers := PackedInt32Array()
var _server_pos := PackedVector3Array()
var _server_out := PackedVector3Array()
var _racks: Array[Dictionary] = []

var _markers: MultiMeshInstance3D
var _clips: MultiMeshInstance3D
var _status: MultiMeshInstance3D
var _cables: MeshInstance3D
var _ghost: MeshInstance3D
var _held := -1
var _hover := -1
var _message := ""
var _message_at := 0.0


# ------------------------------------------------------------------ building

func attach(bridge: CablingBridge) -> void:
	## The bridge owns the hall's wiring and is handed in from outside, because this
	## node is a view of that state and has to be able to die without taking it along
	## (CLAUDE.md, rule 1).
	_bridge = bridge


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
		"clip_from": _clip_pos.size(),
		"clip_to": _clip_pos.size(),
		"slot": _racks.size(),
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


func add_strip(entry: Dictionary, at: Vector3, feed: int, outlets := OUTLETS) -> int:
	## A 0U strip down the back channel. Outlets face the aisle, which is where the
	## person doing the patching is standing.
	var device: int = _bridge.AddDevice(Kind.PDU, entry["index"], outlets, 0, feed)
	for i in outlets:
		var up := OUTLET_BASE + i * OUTLET_SPAN / float(maxi(outlets - 1, 1))
		_port(entry, device, at + Vector3(0.0, up, -0.030))
	if feed == FeedId.A:
		entry["feed_a"].append(device)
	else:
		entry["feed_b"].append(device)
	return device


func add_panel(entry: Dictionary, centre: Vector3, kind: int, ports: int,
		first_x: float, pitch: float, row_gap: float) -> int:
	## Sockets are placed where the model actually draws them, not spread evenly across
	## the panel: a switch's two rows of twelve start 60 mm in from the left edge and
	## are not centred (tools/blender/build_props.py). Guessing put markers 38 mm out.
	var device: int = _bridge.AddDevice(kind, entry["index"], 0, ports, FeedId.NONE)
	var rows := 2 if row_gap > 0.0 else 1
	var per_row := ports / rows
	for i in ports:
		var row := i / per_row
		var col := i % per_row
		var y := (row - (rows - 1) * 0.5) * row_gap
		_port(entry, device, centre + Vector3(first_x + col * pitch, y, 0.0))
	if kind == Kind.SWITCH:
		entry["uplinks"].append(device)
	return device


func add_spine(entry: Dictionary, at: Vector3) -> void:
	## The vertical finger duct. Every gap between two fingers is somewhere a cord can
	## be dressed in, and the numbers match tools/blender/dclib/units.py.
	var xform: Transform3D = entry["xform"]
	for i in SPINE_CLIPS:
		# 48 mm out, at the mouth of the duct: the fingers reach 51 mm and pins sunk
		# inside them are simply not visible, which is what made the clips look like
		# flat squares — the only part showing was their front face.
		var local := at + Vector3(0.0, SPINE_BASE + i * SPINE_PITCH, -0.048)
		_clip_pos.append(xform * local)
		_clip_out.append((xform.basis * Vector3(0, 0, -1)).normalized())
		_clip_load.append(0)
	entry["clip_to"] = _clip_pos.size()


func _port(entry: Dictionary, _device: int, local: Vector3) -> void:
	var xform: Transform3D = entry["xform"]
	_port_pos.append(xform * local)
	_port_rack.append(entry["slot"])
	entry["port_to"] = _port_pos.size()
	# sockets on a rear panel point back down the hot aisle; a PDU outlet points the
	# same way, which is why the strip is turned round when the scene places it
	_port_out.append((xform.basis * Vector3(0, 0, -1)).normalized())
	# the core hands out ports in the order devices are added, so its index and ours
	# are the same number; build() checks that before anything relies on it
	_port_line.append(_bridge.LineOf(_port_pos.size() - 1))


func build() -> void:
	# Our arrays are indexed by the core's port ids. Nothing enforces that but the
	# order of the calls above, so check it once rather than debug crossed cables.
	var expected := 0
	for device in _bridge.DeviceCount():
		expected += _bridge.PortCountOf(device)
		for i in _bridge.PortCountOf(device):
			var port: int = _bridge.PortOf(device, i)
			if port >= _port_pos.size() or _bridge.RackOf(device) != _racks[_port_rack[port]]["index"]:
				push_error("wiring: port %d of device %d is not where the scene put it"
					% [i, device])
				return
	if expected != _port_pos.size():
		push_error("wiring: %d ports in the core, %d placed in the scene"
			% [expected, _port_pos.size()])
		return

	print("wiring: %d racks, %d servers, %d ports, %d clips" % [
		_racks.size(), _servers.size(), _port_pos.size(), _clip_pos.size()])

	_markers = MultiMeshInstance3D.new()
	_markers.multimesh = _instances(_port_pos.size(), _pad_mesh(MARKER))
	_markers.material_override = _flat_material()
	add_child(_markers)

	_clips = MultiMeshInstance3D.new()
	_clips.multimesh = _instances(_clip_pos.size(), _clip_mesh())
	_clips.material_override = _part_material()
	add_child(_clips)

	_status = MultiMeshInstance3D.new()
	_status.multimesh = _instances(_servers.size(), _pad_mesh(0.009))
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
	for i in _clip_pos.size():
		_clips.multimesh.set_instance_transform(i, _facing(_clip_pos[i], _clip_out[i]))
	for i in _servers.size():
		_status.multimesh.set_instance_transform(i, _facing(_server_pos[i], _server_out[i]))

	refresh()


# ------------------------------------------------------------------ actions

func wire_rack(entry: Dictionary, mistake_in := 0, seed_value := 1, quiet := false) -> void:
	var first_link: int = _bridge.LinkCount()
	var report: PackedInt32Array = _bridge.WireRack(
		entry["servers"], entry["feed_a"], entry["feed_b"], entry["uplinks"],
		mistake_in, seed_value)

	# whoever wires a rack also dresses it: the cords go into the ducts. Leaving them
	# hanging is something the player can do, not something the job produces.
	for link in range(first_link, _bridge.LinkCount()):
		if _bridge.LinkLive(link):
			_dress(link, _auto_route(entry, _bridge.LinkPortA(link),
				_bridge.OtherEnd(_bridge.LinkPortA(link))))
	_say("стойка %d: серверов %d, питание %d, сеть %d, промахов %d%s" % [
		entry["index"], report[0], report[1], report[2], report[3],
		"" if report[4] == 0 else ", не хватило портов: %d" % report[4]])
	if report[4] > 0 or report[5] > 0:
		push_warning("rack %d: %d ports short, %d refused" % [
			entry["index"], report[4], report[5]])
	if not quiet:
		refresh()


func _auto_route(entry: Dictionary, from_port: int, to_port: int) -> PackedInt32Array:
	if to_port < 0:
		return PackedInt32Array()
	var inv: Transform3D = entry["xform"].affine_inverse()
	var a := inv * _port_pos[from_port]
	var b := inv * _port_pos[to_port]
	# down the duct nearest the far end — a PDU strip sits beside one of them, and a
	# switch in the middle is reached from whichever side the server already uses
	var side := signf(b.x) if absf(b.x) > 0.05 else signf(a.x)
	if side == 0.0:
		side = 1.0

	# A gap outside the span between the two ends would send the cord down past it and
	# back up — a 180 degree turn, which is both wrong and what threw spikes off the
	# tube. Short hops stay undressed instead, which is what happens in a real rack.
	var low := minf(a.y, b.y)
	var high := maxf(a.y, b.y)
	var enter := _nearest_clip(entry, inv, side, a.y, low, high)
	var leave := _nearest_clip(entry, inv, side, b.y, low, high)
	if enter < 0:
		return PackedInt32Array()
	if leave < 0 or leave == enter:
		return PackedInt32Array([enter])
	return PackedInt32Array([enter, leave])


func _nearest_clip(entry: Dictionary, inv: Transform3D, side: float, height: float,
		low: float, high: float) -> int:
	var best := -1
	var best_gap := INF
	for clip in range(entry["clip_from"], entry["clip_to"]):
		var local := inv * _clip_pos[clip]
		if signf(local.x) != side or local.y < low or local.y > high:
			continue
		# a stuffed gap is passed over rather than packed tighter
		var gap := absf(local.y - height) + (0.4 if _clip_load[clip] >= CLIP_FULL else 0.0)
		if gap < best_gap:
			best_gap = gap
			best = clip
	return best


func racks() -> Array[Dictionary]:
	return _racks


func is_bare(entry: Dictionary) -> bool:
	## No server in the rack has a single cord in it.
	for server in entry["servers"]:
		for i in _bridge.PortCountOf(server):
			if not _bridge.IsFree(_bridge.PortOf(server, i)):
				return false
	return true


func clear_message() -> void:
	_message = ""


func refresh() -> void:
	# anything that changes the patching from outside — wiring a rack, dropping a feed
	# — can have taken the port the player is holding, or killed a dressed cord
	if _held >= 0 and not _bridge.IsFree(_held):
		_drop_held()
	_prune_routes()

	_paint_markers()
	_paint_clips()
	_paint_status()
	_cables.mesh = _cable_mesh()
	_ghost.mesh = _ghost_mesh()


func _prune_routes() -> void:
	for link in _routes.keys():
		if not _bridge.LinkLive(link):
			_undress(link)


func _paint_clips() -> void:
	for clip in _clip_pos.size():
		_clips.multimesh.set_instance_color(clip, _clip_colour(clip))


func _clip_colour(clip: int) -> Color:
	if _held_route.has(clip):
		return COLOUR["held"]
	if _hover == clip_code(clip):
		return COLOUR["hover"]
	if _clip_load[clip] >= CLIP_FULL:
		return COLOUR["stuffed"]
	# same idea as the sockets: barely there until there is a cord to put away
	if _held >= 0:
		return COLOUR["clip_open"]
	if _clip_load[clip] > 0:
		return COLOUR["clip_used"]
	return COLOUR["clip_free"]


func _paint_markers() -> void:
	# one array across the bridge instead of five calls per port
	_states = _bridge.PortStates()
	for port in _port_pos.size():
		_markers.multimesh.set_instance_color(port, _marker_colour(port))
		var shown := (_states[port] & FREE_BIT) != 0 or port == _hover or port == _held
		_markers.multimesh.set_instance_transform(port,
			_facing(_port_pos[port], _port_out[port]) if shown
			# not zero: a degenerate basis has no usable normals and the rasteriser
			# throws long shards off it
			else Transform3D(Basis().scaled(Vector3.ONE * 0.001), _port_pos[port]))


func _marker_colour(port: int) -> Color:
	if port == _held:
		return COLOUR["held"]
	if port == _hover:
		if _held >= 0:
			var verdict: int = _bridge.CanConnect(_held, port)
			return COLOUR["hover"] if verdict == 0 else COLOUR["blocked"]
		return COLOUR["hover"]

	var bits: int = _states[port]
	if bits & FREE_BIT:
		# Idle, a free socket is a faint plate: three thousand lit squares is all the
		# player sees otherwise. With a cord in hand the ones it could go into light up,
		# which is the only moment they are worth looking at.
		var network := (bits & LINE_BIT) != 0
		if _held >= 0:
			return (COLOUR["open_network"] if network else COLOUR["open_power"]) 				if network == ((_states[_held] & LINE_BIT) != 0) 				else (COLOUR["free_network"] if network else COLOUR["free_power"])
		return COLOUR["free_network"] if network else COLOUR["free_power"]
	return _line_colour(port)


func _line_colour(port: int) -> Color:
	var bits: int = _states[port]
	if bits & LINE_BIT:
		return COLOUR["network"]
	var feed := (bits >> FEED_SHIFT) & 0x3
	return COLOUR["feed_a"] if feed == FeedId.A else (
		COLOUR["feed_b"] if feed == FeedId.B else COLOUR["free_power"])


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
	if _hover == -1:
		if _held >= 0:
			_drop_held()
			_say("кабель убран")
			refresh()
		return

	if is_clip(_hover):
		_clip_click(-_hover - 2)
		return

	if _held < 0:
		if not _bridge.IsFree(_hover):
			_say("порт занят — ПКМ, чтобы выдернуть")
			return
		_held = _hover
		_say("держим конец: %s" % _describe(_hover))
		# both the open sockets and the clips change appearance now
		_paint_markers()
		_paint_clips()
		return

	var result: int = _bridge.Connect(_held, _hover)
	_say(RESULT_TEXT[result] if result < RESULT_TEXT.size() else "отказ %d" % result)
	if result == 0:
		_dress(_bridge.LastLink, _held_route)
		_held = -1
		_held_route = PackedInt32Array()
	refresh()


func _clip_click(clip: int) -> void:
	if _held < 0:
		return
	var at := _held_route.find(clip)
	if at >= 0:
		_held_route.remove_at(at)
		_say("вынули из крепления")
	else:
		_held_route.append(clip)
		_say("уложили в крепление (%d)" % _held_route.size())
	_paint_clips()


func _unplug() -> void:
	if _held >= 0:
		_drop_held()
		_say("кабель убран")
		refresh()
		return
	if _hover < 0 or is_clip(_hover):
		return
	var link: int = _bridge.LinkOf(_hover)
	if link < 0:
		_say("здесь ничего не воткнуто")
		return
	_undress(link)
	_bridge.Disconnect(link)
	_say("выдернуто")
	refresh()


func _drop_held() -> void:
	_held = -1
	_held_route = PackedInt32Array()


func _dress(link: int, clips: PackedInt32Array) -> void:
	if clips.is_empty():
		return
	_routes[link] = clips
	for clip in clips:
		_clip_load[clip] += 1


func _undress(link: int) -> void:
	if not _routes.has(link):
		return
	for clip in _routes[link]:
		_clip_load[clip] -= 1
	_routes.erase(link)


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
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
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


## Picking returns one number for two kinds of target: a port is its own index, a
## clip is -(index + 2), and -1 is nothing. Two parallel hover variables would have
## to be kept in step at every call site, and that is the bug this avoids.
static func clip_code(clip: int) -> int:
	return -(clip + 2)


static func is_clip(code: int) -> bool:
	return code <= -2


func _pick(camera: Camera3D) -> int:
	var origin := camera.global_position
	var forward := -camera.global_transform.basis.z
	var best := -1
	var best_score := INF
	# a hall is thousands of targets and this runs every frame, so only the cabinets
	# within arm's reach are worth walking
	for entry in _racks:
		if (entry["xform"].origin - origin).length() > REACH + 1.3:
			continue
		for port in range(entry["port_from"], entry["port_to"]):
			# a socket turned away from the player is behind a closed door and half a
			# rack of steel; letting the crosshair through it patches from the cold aisle
			if (_port_pos[port] - origin).dot(_port_out[port]) >= 0.0:
				continue
			var score := _aim(origin, forward, _port_pos[port])
			if score < best_score:
				best_score = score
				best = port
		# clips only matter while a cord is in hand, and letting them compete with
		# ports the rest of the time makes sockets hard to hit
		if _held >= 0:
			for clip in range(entry["clip_from"], entry["clip_to"]):
				var score := _aim(origin, forward, _clip_pos[clip])
				if score < best_score:
					best_score = score
					best = clip_code(clip)
	return best


func _aim(origin: Vector3, forward: Vector3, target: Vector3) -> float:
	var to_target := target - origin
	var along := to_target.dot(forward)
	if along < 0.12 or along > REACH:
		return INF
	# forgive a wider miss further away, or distant targets are unpickable
	var off := (to_target - forward * along).length()
	if off > PICK_CONE * along:
		return INF
	return off / along + along * 0.02


# ------------------------------------------------------------------ geometry

func _cable_mesh() -> ArrayMesh:
	if "--nocables" in OS.get_cmdline_user_args():
		return null
	## Rebuilt only when the patching changes (docs/10: cables are procedural geometry,
	## not a node per cord). One mesh for the hall, coloured per vertex.
	var links: PackedInt32Array = _bridge.LiveLinks()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var i := 0
	while i < links.size():
		var from_port: int = links[i]
		var link: int = _bridge.LinkOf(from_port)
		_tube(st, _cable_points(from_port, links[i + 1],
			_routes.get(link, PackedInt32Array())), _line_colour(from_port))
		i += 2

	st.generate_normals()
	return st.commit()


func _ghost_mesh() -> ArrayMesh:
	if _held < 0:
		return null
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Previewed exactly the way it will be built, so the shape is not a surprise once
	# the second socket is clicked.
	var points: PackedVector3Array
	if _hover >= 0:
		points = _cable_points(_held, _hover, _held_route)
	elif _held_route.is_empty():
		points = _droop(_port_pos[_held], _port_out[_held],
			camera.global_position + (-camera.global_transform.basis.z) * 0.5, Vector3.UP)
	else:
		var lane := _lane(_held)
		var loose := PackedVector3Array()
		_step(loose, _port_pos[_held])
		var normal := _clip_out[_held_route[0]]
		var enter: Vector3 = _clip_pos[_held_route[0]] + normal * lane
		_step(loose, _onto(_port_pos[_held], enter, normal))
		_step(loose, Vector3(enter.x, _port_pos[_held].y, enter.z))
		for clip in _held_route:
			_step(loose, _clip_pos[clip] + _clip_out[clip] * lane)
		_step(loose, camera.global_position + (-camera.global_transform.basis.z) * 0.5)
		points = _smooth(_chamfer(loose, 0.010))

	_tube(st, points, COLOUR["held"])
	st.generate_normals()
	return st.commit()


func _cable_points(from_port: int, to_port: int,
		clips: PackedInt32Array) -> PackedVector3Array:
	## A cord dressed into the duct runs through the gaps it was pushed into; one that
	## was not simply hangs. That difference is the whole reason the ducts exist, so it
	## has to be visible from across the aisle.
	var from := _port_pos[from_port]
	var to := _port_pos[to_port]
	if clips.is_empty():
		return _droop(from, _port_out[from_port], to, _port_out[to_port])

	# A real cord leaves the socket straight back, turns once to the duct at its own
	# height, runs the duct vertically and turns once more into the far socket. Going
	# diagonally from socket to gap instead is what made a wired rack look like a
	# bird's nest: it is the right-angle runs that read as tidy.
	var lane := _lane(from_port)
	var enter: Vector3 = _clip_pos[clips[0]] + _clip_out[clips[0]] * lane
	var leave: Vector3 = _clip_pos[clips[clips.size() - 1]] \
		+ _clip_out[clips[clips.size() - 1]] * lane

	# Out of the socket, straight back to the depth the duct sits at, sideways at the
	# socket's own height, and into the gap. Every leg is square to the last.
	#
	# Everything happens at the duct's depth. Earlier versions ran the sideways legs
	# further back, past the front of the duct, and at that depth they go through the
	# 60 mm corner posts — which is what was vanishing into the geometry.
	var normal := _clip_out[clips[0]]
	var run: Vector3 = enter

	var points := PackedVector3Array()
	_step(points, from)
	_step(points, _onto(from, run, normal))
	_step(points, Vector3(enter.x, from.y, enter.z))
	for clip in clips:
		_step(points, _clip_pos[clip] + _clip_out[clip] * lane)
	_step(points, Vector3(leave.x, to.y, leave.z))
	_step(points, _onto(to, run, normal))
	_step(points, to)
	return _smooth(_chamfer(points, 0.012))


func _onto(point: Vector3, plane: Vector3, normal: Vector3) -> Vector3:
	## Slides a point along the normal until it lies on the plane through `plane`, so
	## the leg stays square whichever way the cabinet is turned.
	return point + normal * (plane - point).dot(normal)


func _step(points: PackedVector3Array, at: Vector3) -> void:
	## Corner points that land on top of each other turn into a kink once the path is
	## chamfered, so a step that goes nowhere is dropped.
	if points.is_empty() or points[points.size() - 1].distance_to(at) > 0.008:
		points.append(at)


func _lane(port: int) -> float:
	# How deep inside the gap a cord sits. Kept small: the dip into the duct and back
	# out is a visible zigzag, and a deep one loops around the finger.
	return 0.008 + (port % 6) * 0.004





func _chamfer(points: PackedVector3Array, radius: float) -> PackedVector3Array:
	## Replaces each corner with two points a little way down its legs. A plain
	## smoothing pass over right angles cuts them into long diagonals; chamfering first
	## keeps the straight runs straight and leaves only the corner rounded.
	if points.size() < 3:
		return points
	var out := PackedVector3Array([points[0]])
	for i in range(1, points.size() - 1):
		var here: Vector3 = points[i]
		var back: Vector3 = points[i - 1]
		var ahead: Vector3 = points[i + 1]
		var in_len := here.distance_to(back)
		var out_len := here.distance_to(ahead)
		out.append(here + (back - here).normalized() * minf(radius, in_len * 0.45))
		out.append(here + (ahead - here).normalized() * minf(radius, out_len * 0.45))
	out.append(points[points.size() - 1])
	return out


func _droop(from: Vector3, from_out: Vector3, to: Vector3,
		to_out: Vector3) -> PackedVector3Array:
	var span := from.distance_to(to)
	var lift := from + from_out * minf(0.06, span * 0.3)
	var land := to + to_out * minf(0.06, span * 0.3)
	var sag := Vector3.DOWN * (span * SAG)

	var points := PackedVector3Array()
	var steps := 9
	for i in steps + 1:
		var t := float(i) / steps
		points.append(_bezier(from, lift + sag, land + sag, to, t))
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
	##
	## The frame is carried along the curve rather than rebuilt from the world up at
	## each point. Rebuilt, it flips where the run turns from vertical to horizontal —
	## the section twists inside out and throws a long spike off the cable, which is
	## what those shards along the ducts were.
	points = _dedupe(points)
	if points.size() < 2:
		return

	if "--cablecheck" in OS.get_cmdline_user_args():
		for i in points.size():
			var p: Vector3 = points[i]
			if not (is_finite(p.x) and is_finite(p.y) and is_finite(p.z)):
				push_warning("cable point %d is not finite: %v" % [i, p])
			elif p.length() > 60.0:
				push_warning("cable point %d is far away: %v" % [i, p])
			elif i > 0 and points[i - 1].distance_to(p) > 0.35:
				push_warning("cable leg %.2f m from %v to %v" % [
					points[i - 1].distance_to(p), points[i - 1], p])
		for i in range(1, points.size() - 1):
			var d1: Vector3 = (points[i] - points[i - 1]).normalized()
			var d2: Vector3 = (points[i + 1] - points[i]).normalized()
			if d1.dot(d2) < -0.3:
				push_warning("cable reverses at %v (dot %.2f) in a run of %d" % [
					points[i], d1.dot(d2), points.size()])

	var sides := 4
	var rings: Array[PackedVector3Array] = []
	var right := Vector3.ZERO
	for i in points.size():
		var ahead: Vector3 = points[mini(i + 1, points.size() - 1)]
		var behind: Vector3 = points[maxi(i - 1, 0)]
		var dir := (ahead - behind).normalized()
		if dir.length_squared() < 0.5:
			dir = (points[points.size() - 1] - points[0]).normalized()
			if dir.length_squared() < 0.5:
				dir = Vector3.FORWARD

		# keep as much of the previous frame as is still perpendicular
		right = right - dir * right.dot(dir)
		if right.length_squared() < 1e-8:
			right = dir.cross(Vector3.UP)
			if right.length_squared() < 1e-8:
				right = Vector3.RIGHT
		right = right.normalized()
		var up := right.cross(dir).normalized()

		var ring := PackedVector3Array()
		for s in sides:
			var a := TAU * s / sides
			ring.append(points[i] + (right * cos(a) + up * sin(a)) * CABLE_R)
		rings.append(ring)

	for i in rings.size() - 1:
		# A run that doubles back has no continuous section through the turn; carrying
		# one across it is what threw metre-long shards off the cable. Skip the joint.
		var d1: Vector3 = (points[i] - points[maxi(i - 1, 0)]).normalized()
		var d2: Vector3 = (points[i + 1] - points[i]).normalized()
		if i > 0 and d1.dot(d2) < -0.3:
			continue
		for s in sides:
			var n := (s + 1) % sides
			_quad(st, rings[i][s], rings[i][n], rings[i + 1][n], rings[i + 1][s], colour)


func _dedupe(points: PackedVector3Array) -> PackedVector3Array:
	## Chamfering and smoothing both leave near-coincident points behind, and a zero
	## length segment has no direction to build a section from.
	var out := PackedVector3Array()
	for p in points:
		if out.is_empty() or out[out.size() - 1].distance_to(p) > 0.001:
			out.append(p)
	return out


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		colour: Color) -> void:
	for v in [a, b, c, a, c, d]:
		st.set_color(colour)
		st.add_vertex(v)


func _instances(count: int, mesh: Mesh) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = count
	return mm


func _pad_mesh(size: float) -> Mesh:
	## A socket marker has to sit on a panel and still read as a part of it, so it is a
	## shallow block rather than a decal: it catches the room light and has an edge.
	var box := BoxMesh.new()
	box.size = Vector3(size, size, size * 0.35)
	return box


func _clip_mesh() -> Mesh:
	## A pair of pins with heads on them, 13 mm apart, sticking 22 mm out of the duct.
	## A cord goes in between them and the heads keep it there — which is the shape the
	## thing is named after. A block with a bump on it, which is what was here before,
	## reads as a square from any distance a player actually stands at.
	##
	## Built in code rather than Blender: it is four boxes and it has to be tinted per
	## instance, which a glb surface cannot be.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0, 1.0]:
		var y: float = side * 0.008
		_solid(st, Vector3(0, y, 0.014), Vector3(0.0026, 0.0026, 0.014))
		_solid(st, Vector3(0, y, 0.030), Vector3(0.0048, 0.0048, 0.003))
	st.generate_normals()
	return st.commit()


func _solid(st: SurfaceTool, centre: Vector3, half: Vector3) -> void:
	## Vertex colour stays white: the tint comes from the MultiMesh instance colour,
	## which multiplies into it.
	var corners := PackedVector3Array()
	for i in 8:
		corners.append(centre + Vector3(
			half.x * (1.0 if (i & 1) else -1.0),
			half.y * (1.0 if (i & 2) else -1.0),
			half.z * (1.0 if (i & 4) else -1.0)))
	# Wound so the faces look outward. Reversed, the whole part is inside out: back-face
	# culling drops every surface that should be visible and leaves a flat silhouette —
	# which is exactly why these read as squares no matter what shape they were given.
	var faces := [[4, 6, 2, 0], [3, 7, 5, 1], [1, 5, 4, 0],
		[6, 7, 3, 2], [2, 3, 1, 0], [5, 7, 6, 4]]
	for face in faces:
		_quad(st, corners[face[0]], corners[face[1]], corners[face[2]], corners[face[3]],
			Color.WHITE)


func _facing(at: Vector3, normal: Vector3) -> Transform3D:
	var up := Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	return Transform3D(Basis.looking_at(-normal, up), at + normal * 0.002)


func _flat_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	return mat


func _part_material() -> StandardMaterial3D:
	## Lit, unlike the markers: a clip is a moulded part and its shape has to read.
	## Unshaded turned it into a flat silhouette, which is what looked like a square.
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.55
	# It is pitch dark behind a rack. Lit only by the room, a part this size is a black
	# smudge; a little emission keeps the shading that shows its shape while making sure
	# there is something to see at all.
	mat.emission_enabled = true
	mat.emission = Color(1, 1, 1)
	mat.emission_energy_multiplier = 0.30
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
			lines.append("ЛКМ: %s" % (RESULT_TEXT[verdict]
				if verdict < RESULT_TEXT.size() else "отказ %d" % verdict))
	elif _held >= 0:
		lines.append("держим кабель — наведитесь на порт")
	else:
		lines.append("наведитесь на порт: ЛКМ — взять, ПКМ — выдернуть")
	lines.append("R — подключить стойку целиком, T — увести луч A")
	if not _message.is_empty() and Time.get_ticks_msec() / 1000.0 - _message_at < 6.0:
		lines.append("» %s" % _message)
	return "\n".join(lines)

