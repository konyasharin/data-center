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
const MARKER := 0.014   # ring around a socket, so it is wider than the socket
const CABLE_R := 0.0025
# Where the cord starts, measured off the socket face. It has to clear the boot at
# the back of the connector: starting inside it, a cord that then turns sideways cuts
# out through the boot's wall, which is the cable passing through the plug.
const PLUG_OUT := 0.042
# How far in front of a panel a cord may run sideways. A connector reaches 46 mm off
# the face, so anything shorter than that plus the cord's own radius threads the run
# through the plugs of every socket it passes.
const CLEAR_OF_PLUGS := 0.090
# must match make_cable_manager in tools/blender/build_room.py
const MANAGER_RINGS := 5
const MANAGER_SPAN := 0.120
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
	"clip_free": Color(0.26, 0.28, 0.33),
	"clip_used": Color(0.34, 0.38, 0.45),
	"stuffed": Color(0.80, 0.45, 0.10),
	# lit while a cord is in hand
	"open_power": Color(0.90, 0.88, 0.60),
	"open_network": Color(0.55, 0.90, 0.70),
	"clip_open": Color(0.85, 0.90, 1.00),
}

# connector shells, which are a plastic part and not a piece of the cord
const PLUG_NETWORK := Color(0.62, 0.64, 0.60)
const PLUG_POWER := Color(0.09, 0.09, 0.10)

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

var _aim_ring: MeshInstance3D      # the socket the crosshair is on
var _held_ring: MeshInstance3D     # the end being held
var _clips: MultiMeshInstance3D
var _status: MultiMeshInstance3D
var _cables: Array[MeshInstance3D] = []   # one per rack, so a change is local
var _ghost: MeshInstance3D
var _held := -1
var _hover := -1
var _message := ""
var _message_at := 0.0

var _plug_in: AudioStream = preload("res://assets/audio/plug_in.wav")
var _plug_out: AudioStream = preload("res://assets/audio/plug_out.wav")
# the cord being seated: port, how far along, and which way
var _seating := -1
var _seat_t := 0.0
var _seat_in := true
var _seat_offset := 0.0
# a cord on its way out: pulled first, disconnected when the movement finishes
var _pending_link := -1
var _pending_slots := PackedInt32Array()


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
		"rings": PackedVector3Array(),
		"net_side": 1.0,      # the duct network shares, which is feed B's
		"slot": _racks.size(),
	}
	_racks.append(entry)
	return entry


func add_server(entry: Dictionary, at: Vector3, height: float, depth: float) -> int:
	## `at` is the chassis origin in rack space; the body runs from there toward -Z,
	## so every socket is on the plane just behind its back face.
	var device: int = _bridge.AddDevice(Kind.SERVER, entry["index"], 2, 1, FeedId.NONE)
	# The chassis rear itself, which is where the sockets stand: they are built out of
	# that face, not into it.
	var z := -depth
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
		_port(entry, device, at + Vector3(0.0, up, -0.023))
	if feed == FeedId.A:
		entry["feed_a"].append(device)
	else:
		entry["feed_b"].append(device)
		# network follows feed B, so it has to know which side that landed on — the
		# two rows face opposite ways and the feeds are keyed to the hall, not the
		# cabinet
		entry["net_side"] = signf(at.x) if not is_zero_approx(at.x) else 1.0
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
		# the mouth of the holder moulded into the duct, 42 mm out past its lips
		var local := at + Vector3(0.0, SPINE_BASE + i * SPINE_PITCH, -0.040)
		_clip_pos.append(xform * local)
		_clip_out.append((xform.basis * Vector3(0, 0, -1)).normalized())
		_clip_load.append(0)
	entry["clip_to"] = _clip_pos.size()


func add_manager(entry: Dictionary, centre: Vector3) -> void:
	## The rings of a 1U horizontal manager. Patch leads pass through the one nearest
	## their socket's column before climbing, so the run up to a switch is several
	## short bundles instead of one fan spreading from a single point.
	var rings := PackedVector3Array()
	for i in MANAGER_RINGS:
		var x := (i / float(MANAGER_RINGS - 1) - 0.5) * MANAGER_SPAN
		rings.append(entry["xform"] * (centre + Vector3(x, 0.0, 0.0)))
	entry["rings"] = rings


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

	# Two plain nodes, not an instance per socket. Hiding a MultiMesh instance by
	# scaling its transform to nothing does not work — the scale is not kept, it reads
	# back as 1, and every socket in the hall stayed ringed.
	_aim_ring = MeshInstance3D.new()
	_aim_ring.mesh = _socket_mesh(MARKER)
	_aim_ring.material_override = _flat_material()
	_aim_ring.visible = false
	add_child(_aim_ring)

	_held_ring = MeshInstance3D.new()
	_held_ring.mesh = _socket_mesh(MARKER)
	_held_ring.material_override = _flat_material()
	_held_ring.visible = false
	add_child(_held_ring)

	_clips = MultiMeshInstance3D.new()
	_clips.multimesh = _instances(_clip_pos.size(), _clip_mesh())
	_clips.material_override = _flat_material()
	add_child(_clips)

	_status = MultiMeshInstance3D.new()
	_status.multimesh = _instances(_servers.size(), _pip_mesh(0.0045))
	_status.material_override = _flat_material()
	add_child(_status)

	# One mesh per rack rather than one for the hall: pulling a single cord used to
	# rebuild every cord in the room, which is a visible stall on each click.
	var cable_mat := _cable_material()
	for i in _racks.size():
		var node := MeshInstance3D.new()
		node.material_override = cable_mat
		add_child(node)
		_cables.append(node)

	# the cord being dragged is its own mesh: it is rebuilt every frame, and the other
	# few hundred are not
	_ghost = MeshInstance3D.new()
	_ghost.material_override = _cable_material()
	add_child(_ghost)

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
	# One duct per thing. A PDU strip stands beside one of them, so feed A goes left
	# and feed B right on its own. A switch spans both, and splitting its cords by
	# which half of the panel they land on fills each duct with two colours: the run
	# is barely shorter and the bundle is twice as hard to read. They all take the
	# same duct as feed B, so the left one carries feed A and nothing else.
	var side: float = entry["net_side"]
	if _port_line[from_port] == Line.POWER:
		side = signf(b.x)

	# A gap outside the span between the two ends would send the cord down past it and
	# back up — a 180 degree turn, which is both wrong and what threw spikes off the
	# tube. Short hops stay undressed instead, which is what happens in a real rack.
	var low := minf(a.y, b.y)
	var high := maxf(a.y, b.y)
	var enter := _nearest_clip(entry, inv, side, a.y, low, high)
	if enter < 0:
		return PackedInt32Array()

	# A switch or patch panel is a full 19" wide, so the duct stands on the same line
	# as some of its sockets: dressed in level with the panel, a cord walks through
	# the plugs standing there. It runs the duct as far as the horizontal manager
	# under the panel and leaves it there — held the whole way up, but clear of the
	# sockets. With no manager it is held at the server end only.
	var far_kind: int = _bridge.KindOf(_bridge.OwnerOf(to_port))
	if far_kind == Kind.SWITCH or far_kind == Kind.PATCH:
		var rings: PackedVector3Array = entry["rings"]
		if rings.is_empty():
			return PackedInt32Array([enter])
		var top := _nearest_clip(entry, inv, side, (inv * rings[0]).y, low, high)
		if top < 0 or top == enter:
			return PackedInt32Array([enter])
		return _clip_span(entry, enter, top)

	var leave := _nearest_clip(entry, inv, side, b.y, low, high)
	if leave < 0 or leave == enter:
		return PackedInt32Array([enter])
	return PackedInt32Array([enter, leave])


func _clip_span(entry: Dictionary, from_clip: int, to_clip: int) -> PackedInt32Array:
	## Every gap between the two, so a cord that runs a long way up the duct is held
	## along its whole length instead of passing the holders by.
	var span := PackedInt32Array()
	var step := 1 if to_clip >= from_clip else -1
	var clip := from_clip
	while clip != to_clip + step:
		span.append(clip)
		clip += step
	return span


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


func debug_port(rack_index: int, nth: int) -> Array:
	## Where the nth occupied port of a rack is, so a diagnostic camera can be put in
	## front of it instead of being aimed by hand at coordinates worked out on paper.
	for entry in _racks:
		if int(entry["index"]) != rack_index:
			continue
		var seen := 0
		for port in range(entry["port_from"], entry["port_to"]):
			if _bridge.IsFree(port):
				continue
			if seen == nth:
				if "--portdump" in OS.get_cmdline_user_args():
					print("port %d of rack %d: pos %v out %v line %d owner kind %d" % [
						port, rack_index, _port_pos[port], _port_out[port],
						_port_line[port], _bridge.KindOf(_bridge.OwnerOf(port))])
					print("   plug body spans %v .. %v" % [
						_port_pos[port] - _port_out[port] * 0.004,
						_port_pos[port] + _port_out[port] * 0.016])
					print("   cord starts at %v" % [
						_port_pos[port] + _port_out[port] * PLUG_OUT])
				return [_port_pos[port], _port_out[port]]
			seen += 1
	return []


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


func refresh(slots: PackedInt32Array = PackedInt32Array()) -> void:
	# anything that changes the patching from outside — wiring a rack, dropping a feed
	# — can have taken the port the player is holding, or killed a dressed cord
	if _held >= 0 and not _bridge.IsFree(_held):
		_drop_held()
	_prune_routes()

	_paint_markers()
	_paint_clips()
	_paint_status()
	if slots.is_empty():
		for i in _racks.size():
			_cables[i].mesh = _cable_mesh(i)
	else:
		for slot in slots:
			_cables[slot].mesh = _cable_mesh(slot)
	_ghost.mesh = _ghost_mesh()



func _prune_routes() -> void:
	for link in _routes.keys():
		if not _bridge.LinkLive(link):
			_undress(link)


func _paint_clips() -> void:
	# emptied rather than scaled away, for the same reason the rings are nodes
	_clips.visible = _held >= 0
	if not _clips.visible:
		return
	for clip in _clip_pos.size():
		_clips.multimesh.set_instance_color(clip, _clip_colour(clip))
		_clips.multimesh.set_instance_transform(clip,
			_facing(_clip_pos[clip], _clip_out[clip]))


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
	## Two rings, not one per socket: the one the crosshair is on and the end being
	## held. Ringing every free socket lights up the whole rack and buries the
	## hardware under its own annotations — the ring answers "this one?", it is not a
	## map of the room.
	_states = _bridge.PortStates()
	_place_ring(_aim_ring, -1 if is_clip(_hover) else _hover)
	_place_ring(_held_ring, _held)


func _place_ring(ring: MeshInstance3D, port: int) -> void:
	ring.visible = port >= 0
	if port < 0:
		return
	ring.transform = _facing(_port_pos[port], _port_out[port])
	ring.material_override.albedo_color = _marker_colour(port)


func _marker_colour(port: int) -> Color:
	if port == _held:
		return COLOUR["held"]
	if port == _hover and _held >= 0:
		return (COLOUR["hover"] if _bridge.CanConnect(_held, port) == 0
			else COLOUR["blocked"])
	return COLOUR["hover"]


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

	var touched := PackedInt32Array([_port_rack[_held], _port_rack[_hover]])
	var result: int = _bridge.Connect(_held, _hover)
	_say(RESULT_TEXT[result] if result < RESULT_TEXT.size() else "отказ %d" % result)
	if result == 0:
		_dress(_bridge.LastLink, _held_route)
		_plugged(_hover, true)
		_held = -1
		_held_route = PackedInt32Array()
	refresh(touched)


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
	# Pulled now, disconnected when the movement ends. Cutting the cord on the click
	# leaves nothing to animate — it simply vanishes.
	_pending_link = link
	_pending_slots = PackedInt32Array([_port_rack[_hover],
		_port_rack[maxi(_bridge.OtherEnd(_hover), 0)]])
	_plugged(_hover, false)
	_say("выдернуто")


func _plugged(port: int, going_in: bool) -> void:
	## The click, and the short movement that goes with it. A connector that simply
	## appears in a socket reads as a state flipping, not as a thing being pushed in.
	var sound := AudioStreamPlayer3D.new()
	sound.stream = _plug_in if going_in else _plug_out
	sound.position = _port_pos[port]
	sound.unit_size = 2.5
	sound.max_db = -4.0
	add_child(sound)
	sound.play()
	sound.finished.connect(sound.queue_free)

	_seating = port
	_seat_t = 0.0
	_seat_in = going_in


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
	if _seating >= 0:
		_seat_t += _delta / 0.16
		var done := _seat_t >= 1.0
		_seat_offset = (1.0 - minf(_seat_t, 1.0) if _seat_in else minf(_seat_t, 1.0)) * 0.05
		var slots := PackedInt32Array([_port_rack[_seating]])
		if done:
			_seating = -1
			_seat_t = 0.0
			_seat_offset = 0.0
			if _pending_link >= 0:
				_undress(_pending_link)
				_bridge.Disconnect(_pending_link)
				_pending_link = -1
				slots = _pending_slots
		refresh(slots)


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

func _cable_mesh(slot: int) -> ArrayMesh:
	## Rebuilt only when the patching changes (docs/10: cables are procedural geometry,
	## not a node per cord), and only for the rack that changed.
	if "--nocables" in OS.get_cmdline_user_args():
		return null
	var links: PackedInt32Array = _bridge.LiveLinks()
	# Written straight into arrays rather than through SurfaceTool. SurfaceTool is a
	# call per vertex plus a normal-generation pass, and a rack is tens of thousands
	# of vertices — that is the stall felt on every unplug.
	var mesh := _Buffer.new()

	var i := 0
	while i < links.size():
		var from_port: int = links[i]
		var to_port: int = links[i + 1]
		i += 2
		# drawn by the rack the cord starts in, so a cord between two racks is drawn
		# exactly once
		if _port_rack[from_port] != slot:
			continue
		var link: int = _bridge.LinkOf(from_port)
		var colour := _line_colour(from_port)
		_tube(mesh, _cable_points(from_port, to_port,
			_routes.get(link, PackedInt32Array())), colour)
		_plug(mesh, from_port, colour, _seat_shift(from_port))
		_plug(mesh, to_port, colour, _seat_shift(to_port))

	if "--clash" in OS.get_cmdline_user_args():
		_report_clashes(slot, links)
	return mesh.commit()


func _report_clashes(slot: int, links: PackedInt32Array) -> void:
	## Every point of every cord against the body of every connector that is not its
	## own. A cord through a neighbour's plug is the one fault that is obvious on
	## screen and invisible in the numbers unless something looks for it.
	var entry: Dictionary = _racks[slot]
	var i := 0
	while i < links.size():
		var a: int = links[i]
		var b: int = links[i + 1]
		i += 2
		if _port_rack[a] != slot:
			continue
		var pts := _cable_points(a, b, _routes.get(_bridge.LinkOf(a), PackedInt32Array()))
		for point in pts:
			for other in range(entry["port_from"], entry["port_to"]):
				if other == a or other == b or _bridge.IsFree(other):
					continue
				var along := (point - _port_pos[other]).dot(_port_out[other])
				if along < 0.002 or along > 0.050:
					continue
				var side := (point - _port_pos[other] - _port_out[other] * along).length()
				if side < 0.009:
					push_warning("cord %d->%d through plug %d at %v (along %.3f side %.3f)" % [
						a, b, other, point, along, side])
					break


class _Buffer:
	## Vertices, normals and colours for one rack's cords, plus the one call that
	## turns them into a mesh.
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()

	func tri(a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3,
			colour: Color) -> void:
		verts.append(a)
		verts.append(b)
		verts.append(c)
		norms.append(na)
		norms.append(nb)
		norms.append(nc)
		cols.append(colour)
		cols.append(colour)
		cols.append(colour)

	func commit() -> ArrayMesh:
		if verts.is_empty():
			return null
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = norms
		arrays[Mesh.ARRAY_COLOR] = cols
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh


func _seat_shift(port: int) -> float:
	return _seat_offset if port == _seating else 0.0


func _plug(mesh: _Buffer, port: int, colour: Color, shift := 0.0) -> void:
	## The connector on the end of the cord. Without it the cable is a bare tube
	## disappearing into a hole, and no cord ends like that — the moulded body sitting
	## in the socket is most of what makes it read as plugged in rather than poked in.
	var normal: Vector3 = _port_out[port]
	var up := Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var basis := Basis.looking_at(-normal, up)
	var seat := normal * shift
	# The rim of a socket stands 7 mm proud, so a 20 mm body clears it by two and
	# reads as flush — a connector you can see is one that stands well out of it.
	var body := 0.032
	var network := _port_line[port] == Line.NETWORK

	# A connector is a moulded shell, not a length of the cable: tinting it from the
	# cord makes it read as the cord swelling up at the end. Clear-ish grey for a
	# network plug, near-black for a power one, as the real parts are.
	var shell := PLUG_NETWORK if network else PLUG_POWER
	_prism(mesh, _port_pos[port] + seat + normal * (body * 0.5 - 0.004), basis,
		Vector3(0.0055 if network else 0.0060, 0.0045 if network else 0.0050, body * 0.5),
		shell)
	# the boot, which is the one part coloured like the cable
	_prism(mesh, _port_pos[port] + seat + normal * (body + 0.006), basis,
		Vector3(0.0040, 0.0040, 0.008), colour.darkened(0.35))
	if network:
		# the latch tab, which is what says "network" at a glance
		_prism(mesh, _port_pos[port] + seat + normal * (body * 0.5) + basis.y * 0.0055, basis,
			Vector3(0.0022, 0.0018, body * 0.34), shell.lightened(0.10))


func _prism(mesh: _Buffer, centre: Vector3, basis: Basis, half: Vector3,
		colour: Color) -> void:
	## Flat-shaded, with the face normal given rather than averaged. Averaged, a
	## connector sitting inside the cord and the socket picks up their normals and is
	## lit as if it were made of glass.
	var corners := PackedVector3Array()
	for i in 8:
		corners.append(centre + basis * Vector3(
			half.x * (1.0 if (i & 1) else -1.0),
			half.y * (1.0 if (i & 2) else -1.0),
			half.z * (1.0 if (i & 4) else -1.0)))
	# Wound the opposite way round to _solid's boxes: Godot takes clockwise as the
	# front face, and wound the other way the part is culled to its inside.
	var faces := [[0, 2, 6, 4], [1, 5, 7, 3], [0, 4, 5, 1],
		[2, 3, 7, 6], [0, 1, 3, 2], [4, 6, 7, 5]]
	var axes := [-basis.x, basis.x, -basis.y, basis.y, -basis.z, basis.z]
	for f in faces.size():
		var face: Array = faces[f]
		var n: Vector3 = axes[f]
		_quad(mesh, corners[face[0]], corners[face[1]], corners[face[2]],
			corners[face[3]], colour, n, n, n, n)


func _ghost_mesh() -> ArrayMesh:
	if _held < 0:
		return null
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null
	var mesh := _Buffer.new()

	# Previewed exactly the way it will be built, so the shape is not a surprise once
	# the second socket is clicked.
	var points: PackedVector3Array
	if _hover >= 0:
		points = _cable_points(_held, _hover, _held_route)
	elif _held_route.is_empty():
		points = _droop(_port_pos[_held] + _port_out[_held] * PLUG_OUT, _port_out[_held],
			camera.global_position + (-camera.global_transform.basis.z) * 0.5, Vector3.UP)
	else:
		var lane := _lane(_held)
		var loose := PackedVector3Array()
		_step(loose, _port_pos[_held] + _port_out[_held] * PLUG_OUT)
		var normal := _clip_out[_held_route[0]]
		var enter: Vector3 = _clip_pos[_held_route[0]] - normal * lane
		_step(loose, _onto(_port_pos[_held] + _port_out[_held] * PLUG_OUT, enter, normal))
		_step(loose, Vector3(enter.x, _port_pos[_held].y, enter.z))
		for clip in _held_route:
			_step(loose, _clip_pos[clip] - _clip_out[clip] * lane)
		_step(loose, camera.global_position + (-camera.global_transform.basis.z) * 0.5)
		points = _smooth(_smooth(_chamfer(loose, 0.020)))

	_tube(mesh, points, COLOUR["held"])
	return mesh.commit()


func _cable_points(from_port: int, to_port: int,
		clips: PackedInt32Array) -> PackedVector3Array:
	## A cord dressed into the duct runs through the gaps it was pushed into; one that
	## was not simply hangs. That difference is the whole reason the ducts exist, so it
	## has to be visible from across the aisle.
	# The run starts where the cord leaves the connector body, not at the socket: a
	# tube drawn from the socket face runs straight through the connector standing in
	# front of it, and the first bend then happens inside it.
	var from: Vector3 = _port_pos[from_port] + _port_out[from_port] * PLUG_OUT
	var to: Vector3 = _port_pos[to_port] + _port_out[to_port] * PLUG_OUT
	if clips.is_empty():
		return _droop(from, _port_out[from_port], to, _port_out[to_port])

	# A real cord leaves the socket straight back, turns once to the duct at its own
	# height, runs the duct vertically and turns once more into the far socket. Going
	# diagonally from socket to gap instead is what made a wired rack look like a
	# bird's nest: it is the right-angle runs that read as tidy.
	var lane := _lane(from_port)
	var enter: Vector3 = _clip_pos[clips[0]] - _clip_out[clips[0]] * lane
	var leave: Vector3 = _clip_pos[clips[clips.size() - 1]] \
		- _clip_out[clips[clips.size() - 1]] * lane

	# Out of the socket, straight back to the depth the duct sits at, sideways at the
	# socket's own height, and into the gap. Every leg is square to the last.
	#
	# Everything happens at the duct's depth. Earlier versions ran the sideways legs
	# further back, past the front of the duct, and at that depth they go through the
	# 60 mm corner posts — which is what was vanishing into the geometry.
	var normal := _clip_out[clips[0]]
	var run: Vector3 = enter

	var points := PackedVector3Array()
	# Straight out of the connector first — a cord leaves a connector in line with it
	# and bends further along. Never past the plane it is heading for, though: on a
	# PDU outlet the duct is only some 35 mm behind the socket, and a fixed 45 mm run
	# overshoots it and doubles the cord back on itself.
	# Where the duct is closer to the panel than the connector is long — a switch sits
	# some 25 mm off it and the plug stands 48 — the cord cannot turn onto the duct's
	# plane without doubling back. It runs sideways in front of the connectors
	# instead: level with them it goes straight through the plugs of every socket it
	# passes, which is a row of cords skewered on their neighbours.
	var clear_from: Vector3 = _port_pos[from_port] + normal * CLEAR_OF_PLUGS
	# measured from the socket, not from the start of the cord: the cord already
	# stands PLUG_OUT off the face, so comparing from there says the duct is far
	# enough away when it is not, and the run ends up inside the row of plugs
	var plane_from := run if absf((run - _port_pos[from_port]).dot(normal)) 		>= CLEAR_OF_PLUGS else clear_from
	_step(points, from)
	_step(points, from + _port_out[from_port] * _lead(from, plane_from, normal))
	_step(points, _onto(from, plane_from, normal))
	# sideways at the depth the cord is already on, then into the gap — turning onto
	# the duct's plane first is the doubling back
	_step(points, _onto(Vector3(enter.x, from.y, enter.z), plane_from, normal))
	_step(points, Vector3(enter.x, from.y, enter.z))
	for clip in clips:
		_step(points, _clip_pos[clip] - _clip_out[clip] * lane)
	_step(points, Vector3(leave.x, to.y, leave.z))
	var clear_to: Vector3 = _port_pos[to_port] + normal * CLEAR_OF_PLUGS
	var plane_to := run if absf((run - _port_pos[to_port]).dot(normal)) 		>= CLEAR_OF_PLUGS else clear_to
	# Out of the gap to the clear plane first, and only then up to the socket's own
	# height. Rising at the duct's own depth walks the cord through whatever plugs
	# stand on that line — which a full-width switch always has.
	_step(points, _onto(leave, plane_to, normal))

	var far_kind: int = _bridge.KindOf(_bridge.OwnerOf(to_port))
	var rings: PackedVector3Array = _racks[_port_rack[from_port]]["rings"]
	if (far_kind == Kind.SWITCH or far_kind == Kind.PATCH) and not rings.is_empty():
		var ring := rings[0]
		for candidate in rings:
			if absf(candidate.x - to.x) < absf(ring.x - to.x):
				ring = candidate
		_step(points, _onto(Vector3(leave.x, ring.y, leave.z), plane_to, normal))
		_step(points, _onto(Vector3(ring.x, ring.y, ring.z), plane_to, normal))
		_step(points, _onto(Vector3(to.x, ring.y, ring.z), plane_to, normal))
	else:
		_step(points, _onto(Vector3(leave.x, to.y, leave.z), plane_to, normal))
	_step(points, _onto(to, plane_to, normal))
	_step(points, to + _port_out[to_port] * _lead(to, plane_to, normal))
	_step(points, to)
	# Chamfer, then smooth twice. One pass leaves a visible corner where the cord
	# turns out of the connector, which is the kink at the top row of patch leads.
	return _smooth(_smooth(_chamfer(_unkink(points), 0.020)))


func _lead(from: Vector3, plane: Vector3, normal: Vector3) -> float:
	## How far the cord may run straight out of its connector: at most half the way to
	## the plane it then turns onto, so it never has to come back — but always enough
	## to be clear of the connector before it starts bending.
	# The floor is generous because the path is smoothed afterwards, and smoothing
	# cuts corners inward: too short a lead and the curve dips back into the row of
	# connectors it was supposed to clear.
	return clampf(absf((plane - from).dot(normal)) * 0.5, 0.026, 0.040)


func _onto(point: Vector3, plane: Vector3, normal: Vector3) -> Vector3:
	## Slides a point along the normal until it lies on the plane through `plane`, so
	## the leg stays square whichever way the cabinet is turned.
	return point + normal * (plane - point).dot(normal)


func _unkink(points: PackedVector3Array) -> PackedVector3Array:
	## Drops any point the path has to double back through. A tube has no continuous
	## cross-section across a 180 degree turn: it either tears a hole or throws a
	## spike, and both have been visible on these cords.
	if points.size() < 3:
		return points
	var out := PackedVector3Array([points[0]])
	for i in range(1, points.size() - 1):
		var back: Vector3 = (points[i] - out[out.size() - 1]).normalized()
		var ahead: Vector3 = (points[i + 1] - points[i]).normalized()
		if back.length_squared() > 0.5 and ahead.length_squared() > 0.5 				and back.dot(ahead) < -0.25:
			continue
		out.append(points[i])
	out.append(points[points.size() - 1])
	return out


func _step(points: PackedVector3Array, at: Vector3) -> void:
	## Corner points that land on top of each other turn into a kink once the path is
	## chamfered, so a step that goes nowhere is dropped.
	if points.is_empty() or points[points.size() - 1].distance_to(at) > 0.008:
		points.append(at)


func _lane(port: int) -> float:
	## How far *in* from the holder's mouth a cord sits — between the lips and the
	## floor, so it is inside the recess rather than resting on the outside of it.
	##
	## Power takes the front of the gap and network the back, with a small spread
	## inside each. Mixed together the bundle is one rope of three colours and there
	## is no following a single cord through it; in two layers you can see which is
	## which before you touch anything.
	# The recess itself runs from 4 to 16 mm in from the mouth — the floor of the
	# holder is at 24 mm and its lips at 41. Network sat at 17 to 24 and so lay behind
	# the floor, through the body of the holder instead of in it.
	var network := _port_line[port] == Line.NETWORK
	return (0.0105 if network else 0.0045) + (port % 3) * 0.0018





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


func _bezier(a: Vector3, b: Vector3, c: Vector3, d: Vector3, t: float) -> Vector3:
	var u := 1.0 - t
	return (a * (u * u * u) + b * (3.0 * u * u * t) + c * (3.0 * u * t * t)
		+ d * (t * t * t))


func _tube(mesh: _Buffer, points: PackedVector3Array, colour: Color) -> void:
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
	var normals: Array[PackedVector3Array] = []
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
		var ring_n := PackedVector3Array()
		for s in sides:
			var a := TAU * s / sides
			var out_dir := (right * cos(a) + up * sin(a)).normalized()
			ring.append(points[i] + out_dir * CABLE_R)
			ring_n.append(out_dir)
		rings.append(ring)
		normals.append(ring_n)

	for i in rings.size() - 1:
		for s in sides:
			var n := (s + 1) % sides
			_quad(mesh, rings[i][s], rings[i][n], rings[i + 1][n], rings[i + 1][s], colour,
				normals[i][s], normals[i][n], normals[i + 1][n], normals[i + 1][s])


func _dedupe(points: PackedVector3Array) -> PackedVector3Array:
	## Chamfering and smoothing both leave near-coincident points behind, and a zero
	## length segment has no direction to build a section from.
	var out := PackedVector3Array()
	for p in points:
		if out.is_empty() or out[out.size() - 1].distance_to(p) > 0.001:
			out.append(p)
	return out


func _st_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	## For the handful of meshes built once at start-up, where SurfaceTool's cost does
	## not matter and its normal generation is convenient.
	for v in [a, b, c, a, c, d]:
		st.set_color(Color.WHITE)
		st.add_vertex(v)


func _quad(mesh: _Buffer, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		colour: Color, na: Vector3, nb: Vector3, nc: Vector3, nd: Vector3) -> void:
	mesh.tri(a, b, c, na, nb, nc, colour)
	mesh.tri(a, c, d, na, nc, nd, colour)


func _instances(count: int, mesh: Mesh) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = count
	return mm


func _pip_mesh(radius: float) -> Mesh:
	## The per-server status light: a round lens, because a square one reads as a
	## sticker on the chassis rather than as an indicator on it.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 8
	var depth := 0.0018
	for i in sides:
		var a := TAU * i / sides
		var b := TAU * (i + 1) / sides
		var p1 := Vector3(cos(a) * radius, sin(a) * radius, 0.0)
		var p2 := Vector3(cos(b) * radius, sin(b) * radius, 0.0)
		# lens face, then the rim, so it catches an edge highlight
		_st_quad(st, Vector3(0, 0, depth), p1 + Vector3(0, 0, depth),
			p2 + Vector3(0, 0, depth), Vector3(0, 0, depth))
		_st_quad(st, p1, p2, p2 + Vector3(0, 0, depth), p1 + Vector3(0, 0, depth))
	st.generate_normals()
	return st.commit()


func _socket_mesh(size: float) -> Mesh:
	## A ring around the socket, not a plate over it. Filled, the marker covers the
	## connector the model already draws and the panel turns into a grid of coloured
	## squares — which is what these looked like. Open, the socket stays visible and
	## the ring only says what may be done with it.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := size * 0.5
	var t := 0.0016
	var d := 0.0022
	for side in [-1.0, 1.0]:
		_solid(st, Vector3(side * (half - t), 0.0, d), Vector3(t, half, d))
		_solid(st, Vector3(0.0, side * (half - t), d), Vector3(half - t * 2.0, t, d))
	st.generate_normals()
	return st.commit()


func _clip_mesh() -> Mesh:
	## The holder itself is moulded into cable_spine — a part the scene drops in front
	## of the duct has nothing to attach to and floats. What is left here is the mark on
	## its mouth, shown only while a cord is in hand, so it is the same open ring the
	## sockets use.
	return _socket_mesh(0.013)


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
		_st_quad(st, corners[face[0]], corners[face[1]], corners[face[2]], corners[face[3]])


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
	mat.emission_energy_multiplier = 0.12
	return mat


func _cable_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.75
	mat.metallic = 0.0
	if "--cullcheck" in OS.get_cmdline_user_args():
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
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

