class_name Delivery
extends Node3D

## What happens between paying for a cabinet and standing one up.
##
## A lorry comes down the street, slows, stops level with the gate; the gate slides
## open; the lorry reverses through it to the bay, the crate comes off the back, and
## it pulls out again. The crate is opened from the front by hand, and what is inside
## is the cabinet in pieces. The player carries them to a marked place one at a time,
## in the order they go together, and the cabinet grows there.
##
## Nothing here is a job in the queue. The crew does the work the player delegates;
## this is the work the player does, and the difference is the whole reason the crate
## is opened by hand rather than by somebody in a hi-vis.

const ORDER := ["rack_part_base", "rack_part_upright", "rack_part_upright",
	"rack_part_upright", "rack_part_upright", "rack_part_side", "rack_part_side"]
const NAMED := {
	"rack_part_base": "основание",
	"rack_part_upright": "стойка-профиль",
	"rack_part_side": "боковина",
}
const APPROACH := 6.0        # seconds from the far end of the street to the gate
const BACK_IN := 4.5         # and reversing through it
const GATE_SLIDE := 3.0      # an electric gate is slow, and that is what reads as one
const REACH := 2.6
const CARRY := Vector3(0.34, -0.40, -0.72)
# Where each piece stands in the crate: the base flat on the bottom, the uprights in
# the corners, the sides against the walls — which is how a flat-packed cabinet
# actually travels, and what makes each piece its own thing to aim at. How big each
# one is comes from its mesh, not from numbers written here: a box typed out by hand
# is a box that is wrong the first time a model changes, and it was already half a
# metre too big in every direction.
const PART_SLOT := [
	Vector3(0.0, 0.0, 0.0),
	Vector3(-0.26, 0.10, -0.46), Vector3(0.26, 0.10, -0.46),
	Vector3(-0.26, 0.10, 0.46), Vector3(0.26, 0.10, 0.46),
	Vector3(-0.36, 0.10, 0.0), Vector3(0.36, 0.10, 0.0),
]

var _site: Object
var _eye: Camera3D
var _lorry: Node3D
var _crate: Node3D
var _door: Node3D
var _outline: Outline
# Each piece keeps the slot it was packed in, because pieces leave the crate and the
# ones left behind must not shuffle along to fill the gap — a crate whose contents
# rearrange themselves every time something is taken out is not a crate.
var _parts: Array[Dictionary] = []
var _taken := -1
var _carried: Node3D
var _open := false
var _at := Vector3.ZERO              # the bay
var _street := 0.0                   # z of the road outside the gate
var _gate_x := 0.0
var _aimed := -1                     # part under the crosshair, or -1
var _message := ""


func setup(site: Object, eye: Camera3D, bay: Vector3, street: float) -> void:
	_site = site
	_eye = eye
	_at = bay
	_street = street
	_gate_x = bay.x
	_outline = Outline.make(Outline.COOL)
	add_child(_outline)


func report() -> String:
	return "ящик %s, открыт %s, деталей %d, в руках %d, под прицелом %d" % [
		_crate != null, _open, _parts.size(), _taken, _aimed]


func hud_text() -> String:
	if _taken >= 0:
		return ("в руках %s · X — поставить на размеченное место, V — бросить"
			% _name(_taken))
	if _aimed >= 0:
		return "X — взять %s" % _name(_parts[_aimed]["kind"])
	if _crate != null and _aiming_at_crate():
		return "E — %s ящик" % ("закрыть" if _open else "открыть")
	return _message


func has_crate() -> bool:
	return _crate != null


func busy() -> bool:
	return _crate != null or _lorry != null or _taken >= 0


# ------------------------------------------------------------------ the lorry

func deliver(_seconds: float) -> void:
	if _lorry != null:
		return
	_lorry = Assets.instance("delivery/lorry")
	add_child(_lorry)
	# the model faces along -Z, so heading east down the street is a quarter turn
	var start := Vector3(_gate_x - 70.0, 0, _street)
	var halt := Vector3(_gate_x + 9.0, 0, _street)
	_pose(start, -PI * 0.5)
	_message = "машина в пути"

	# Lined up on the far side of the road and then reversed straight in. The turn
	# happens entirely on the road, because a lorry swinging round while its tail is
	# already inside the gate is a lorry going through the fence — which is what the
	# single curve did.
	var lined := Vector3(_gate_x, 0, _street - 2.4)
	var backed := Vector3(_gate_x, 0, _at.z - 3.4)

	var run := create_tween()
	# in fast and slowing to a stop, which is most of what makes it read as driving
	run.tween_method(func(t: float) -> void: _pose(start.lerp(halt, t), -PI * 0.5),
		0.0, 1.0, APPROACH).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	run.tween_callback(func() -> void:
		_message = "ворота открываются"
		_site.slide_gate(true))
	run.tween_interval(GATE_SLIDE)
	run.tween_method(func(t: float) -> void: _line_up(halt, lined, t),
		0.0, 1.0, BACK_IN * 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	run.tween_method(func(t: float) -> void: _pose(lined.lerp(backed, t), 0.0),
		0.0, 1.0, BACK_IN).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	run.tween_callback(func() -> void:
		_drop_crate()
		_message = "разгрузка")
	run.tween_interval(2.5)
	run.tween_method(func(t: float) -> void: _pose(backed.lerp(lined, t), 0.0),
		0.0, 1.0, BACK_IN).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	run.tween_callback(func() -> void: _site.slide_gate(false))
	run.tween_method(func(t: float) -> void: _line_up(halt, lined, 1.0 - t),
		0.0, 1.0, BACK_IN * 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	run.tween_method(func(t: float) -> void:
		_pose(halt.lerp(Vector3(_gate_x + 80.0, 0, _street), t), -PI * 0.5),
		0.0, 1.0, APPROACH * 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	run.tween_callback(func() -> void:
		if _lorry != null and is_instance_valid(_lorry):
			_lorry.queue_free()
		_lorry = null
		_message = "ящик на площадке: E — открыть")


func _line_up(halt: Vector3, lined: Vector3, t: float) -> void:
	## Swinging the tail round onto the gate's axis, on the road and nowhere near the
	## fence. One quadratic, with its corner where the lorry would actually pivot.
	var bend := Vector3(_gate_x + 7.0, 0, _street - 3.0)
	var a := halt.lerp(bend, t)
	var b := bend.lerp(lined, t)
	_pose(a.lerp(b, t), lerp_angle(-PI * 0.5, 0.0, clampf(t * 1.2, 0.0, 1.0)))


func _pose(at: Vector3, yaw: float) -> void:
	if _lorry == null or not is_instance_valid(_lorry):
		return
	_lorry.global_position = at
	_lorry.rotation.y = yaw


# ------------------------------------------------------------------ the crate

func _drop_crate() -> void:
	_crate = Assets.instance("delivery/crate_body")
	add_child(_crate)
	_crate.global_position = _at
	_door = Assets.instance("delivery/crate_lid")
	add_child(_door)
	# hinged on the left edge of the front face, on the floor
	_door.global_position = _at + Vector3(-0.41, 0.14, -0.64)

	for i in ORDER.size():
		var part := Assets.instance("delivery/%s" % ORDER[i])
		part.visible = false
		add_child(part)
		_parts.append({"node": part, "kind": i, "loose": null})
	_stack()


func _stack() -> void:
	## The pieces are in the crate from the moment it is set down, not conjured when it
	## is opened: a crate whose contents appear on opening is a box with a spawn in it.
	## What the closed front does is stop you reaching them, which is what a front does.
	for piece in _parts:
		if piece["loose"] != null:
			continue
		var part: Node3D = piece["node"]
		part.visible = true
		part.global_position = _part_stand(piece["kind"])
		part.rotation = Vector3(0, 0, 0)


func _part_stand(kind: int) -> Vector3:
	## Where the piece's own origin goes, which is what the model is placed at.
	return _at + Vector3(0, 0.14, 0) + PART_SLOT[mini(kind, PART_SLOT.size() - 1)]


func _part_at(kind: int) -> Vector3:
	## The middle of the piece as it stands, which is what the crosshair aims at. A
	## piece that has been thrown down is wherever it came to rest instead.
	for piece in _parts:
		if piece["kind"] == kind and piece["loose"] != null:
			return (piece["loose"] as Node3D).global_position + part_box(kind).get_center()
	return _part_stand(kind) + part_box(kind).get_center()


func _part_half(kind: int) -> Vector3:
	return part_box(kind).size * 0.5


static func part_box(kind: int) -> AABB:
	## The piece's own bounds, straight off its mesh.
	var mesh := Assets.mesh("delivery/%s" % ORDER[mini(kind, ORDER.size() - 1)])
	return mesh.get_aabb() if mesh != null else AABB(Vector3.ZERO, Vector3.ONE * 0.2)


func part_aim() -> Vector3:
	## Where to point to take the piece that goes on next. The checks aim with this
	## rather than at a guessed height, so what they prove is that pointing at a part
	## takes that part.
	var next := -1
	for piece in _parts:
		if next < 0 or piece["kind"] < next:
			next = piece["kind"]
	return _part_at(next) if next >= 0 else _at


func _swing(open: bool) -> void:
	_open = open
	var turn := create_tween()
	turn.tween_property(_door, "rotation:y", deg_to_rad(-110.0 if open else 0.0), 0.6) \
		.set_trans(Tween.TRANS_CUBIC)
	_stack()


func _clear_crate() -> void:
	for node in [_crate, _door]:
		if node != null and is_instance_valid(node):
			node.queue_free()
	_crate = null
	_door = null
	_open = false
	_aimed = -1
	_message = ""


# ------------------------------------------------------------------- pointing

func _process(_delta: float) -> void:
	if _taken >= 0:
		_show_target()
		return
	_aimed = _pick_part()
	if _aimed < 0:
		_outline.visible = false
		return
	var kind: int = _parts[_aimed]["kind"]
	_outline.show_at(Transform3D(Basis().scaled(_part_half(kind) * 2.0),
		_part_at(kind)), Outline.COOL)


func _show_target() -> void:
	## Where the piece in your hands would go. Carrying something to a place and being
	## told no only once you press the key is a guessing game; the outline is the
	## answer given before the question.
	var spot: Dictionary = _site.spot_under(_eye.global_position,
		-_eye.global_transform.basis.z, REACH * 2.0)
	if spot.is_empty():
		_outline.visible = false
		return
	var bounds := part_box(_taken)
	var at: Vector3 = _site.part_place(spot, _taken) + bounds.get_center()
	_outline.show_at(Transform3D(Basis().scaled(bounds.size), at),
		Outline.COOL if _site.can_build(spot, _taken) else Outline.WARM)


func _pick_part() -> int:
	## The part the crosshair is actually on, as a box. A cone aimed at the middle of
	## the crate meant hunting for the one spot the game agreed was a part.
	if _parts.is_empty() or _eye == null or not is_instance_valid(_eye) or _taken >= 0:
		return -1
	var origin := _eye.global_position
	var dir := -_eye.global_transform.basis.z
	var best := -1
	var best_at := REACH
	for i in _parts.size():
		# what is still in the crate can only be reached once it is open; what is lying
		# on the ground is lying on the ground
		if _parts[i]["loose"] == null and not _open:
			continue
		var kind: int = _parts[i]["kind"]
		var half := _part_half(kind)
		var t := _enters(origin - _part_at(kind), dir, -half, half)
		if t >= 0.05 and t < best_at:
			best_at = t
			best = i
	return best


func _enters(from: Vector3, along: Vector3, low: Vector3, high: Vector3) -> float:
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


func _aiming_at_crate() -> bool:
	if _crate == null or _eye == null or not is_instance_valid(_eye):
		return false
	var centre := _at + Vector3(0, 1.1, 0)
	if _eye.global_position.distance_to(centre) > REACH:
		return false
	var towards := (centre - _eye.global_position).normalized()
	return -_eye.global_transform.basis.z.dot(towards) > 0.55


# ---------------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if _site.reading_screen():
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_E and _crate != null and _aiming_at_crate():
		_swing(not _open)
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_X:
		if _taken >= 0:
			_place_part()
		elif _aimed >= 0:
			_take_part(_aimed)
	elif event.keycode == KEY_V and _taken >= 0:
		_throw()


func _take_part(index: int) -> void:
	_taken = _parts[index]["kind"]
	var loose = _parts[index]["loose"]
	if loose != null and is_instance_valid(loose):
		loose.queue_free()
	_parts[index]["loose"] = null
	(_parts[index]["node"] as Node3D).visible = false
	_carried = Assets.instance("delivery/%s" % ORDER[_taken])
	_carried.position = CARRY
	_carried.scale = Vector3.ONE * 0.5
	_eye.add_child(_carried)
	_outline.visible = false


func _place_part() -> void:
	var spot: Dictionary = _site.spot_under(_eye.global_position,
		-_eye.global_transform.basis.z, REACH * 2.0)
	if spot.is_empty():
		_message = "ставить надо на размеченное место"
		return
	if not _site.can_build(spot, _taken):
		_message = "сначала ставится %s" % _name(_site.built_steps(spot))
		return
	_site.build_step(spot, _taken, ORDER[_taken])
	for i in _parts.size():
		if _parts[i]["kind"] == _taken:
			(_parts[i]["node"] as Node3D).queue_free()
			_parts.remove_at(i)
			break
	_hands_free()
	_message = ""
	_stack()
	if _parts.is_empty():
		_clear_crate()


func _throw() -> void:
	## Out of the hands and onto the ground, as a body that falls. Something carried
	## that can only be installed or carried forever is not a thing you are holding,
	## it is a state you are in.
	var kind := _taken
	var body := RigidBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var bounds := part_box(kind)
	box.size = bounds.size
	shape.shape = box
	shape.position = bounds.get_center()
	body.add_child(shape)
	body.add_child(Assets.instance("delivery/%s" % ORDER[kind]))
	body.mass = 14.0
	add_child(body)
	body.global_position = _eye.global_position + _eye.global_transform.basis * CARRY
	body.apply_central_impulse(-_eye.global_transform.basis.z * 26.0 + Vector3.UP * 5.0)

	for i in _parts.size():
		if _parts[i]["kind"] == kind:
			_parts[i]["loose"] = body
	_hands_free()
	_message = "положили на землю"


func _hands_free() -> void:
	_taken = -1
	if _carried != null and is_instance_valid(_carried):
		_carried.queue_free()
	_carried = null


func _name(index: int) -> String:
	if index < 0 or index >= ORDER.size():
		return "деталь"
	return NAMED.get(ORDER[index], ORDER[index])


func solid_boxes() -> Array:
	if _crate == null:
		return []
	return [{"xform": Transform3D(Basis(), _at + Vector3(0, 1.07, 0)),
		"half": Vector3(0.45, 1.07, 0.68)}]
