class_name Delivery
extends Node3D

## What happens between paying for a cabinet and standing one up.
##
## A lorry comes down the street, slows, stops level with the gate; the gate slides
## open; it reverses through to the bay and its rear door swings up. The cabinet is
## inside, in pieces, and the player takes them out of the back of the lorry one at a
## time and carries them to a marked place. When the lorry is empty it shuts up and
## leaves, and the gate closes behind it.
##
## Nothing here is a job in the queue. The crew does the work the player delegates;
## this is the work the player does.

const ORDER := ["rack_part_base", "rack_part_upright", "rack_part_upright",
	"rack_part_upright", "rack_part_upright", "rack_part_side", "rack_part_side"]
const NAMED := {
	"rack_part_base": "основание",
	"rack_part_upright": "стойка-профиль",
	"rack_part_side": "боковина",
}
# Where each piece rides in the box, in the lorry's own space. The floor of the body
# is 0.64 up, it is 2.3 wide and the rear opening is at +Z.
const BED := 0.70
const STOWED := [
	Vector3(0.0, 0.0, 0.5),
	Vector3(-0.62, 0.0, 1.3), Vector3(0.62, 0.0, 1.3),
	Vector3(-0.62, 0.0, 2.1), Vector3(0.62, 0.0, 2.1),
	Vector3(-0.92, 0.0, -0.4), Vector3(0.92, 0.0, -0.4),
]

const APPROACH := 9.0        # seconds from the far end of the street to the gate
const RUN_UP := 40.0
const BACK_IN := 5.5
const GATE_SLIDE := 3.0      # an electric gate is slow, and that is what reads as one
const DOOR_SWING := 1.2
const REACH := 3.0
const CARRY := Vector3(0.34, -0.40, -0.72)

var _site: Object
var _eye: Camera3D
var _lorry: Node3D
var _door: Node3D
var _outline: Outline
var _parts: Array[Dictionary] = []
var _taken := -1
var _carried: Node3D
var _open := false
var _parked := false
var _at := Vector3.ZERO              # the bay
var _street := 0.0
var _gate_x := 0.0
var _aimed := -1
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
	if _lorry != null and is_instance_valid(_lorry):
		return "машина %v, поворот %.0f°, дверь %s, деталей %d, в руках %d" % [
			_lorry.global_position, rad_to_deg(_lorry.rotation.y), _open,
			_parts.size(), _taken]
	return "машины нет, деталей %d, в руках %d" % [_parts.size(), _taken]


func hud_text() -> String:
	if _taken >= 0:
		return ("в руках %s · X — поставить на размеченное место, V — бросить"
			% _name(_taken))
	if _aimed >= 0 and _aimed < _parts.size():
		return "X — взять %s" % _name(_parts[_aimed]["kind"])
	if _parked and _aiming_at_doors():
		return "E — %s кузов" % ("закрыть" if _open else "открыть")
	return _message


func has_crate() -> bool:
	return _parked


func busy() -> bool:
	return _lorry != null or _taken >= 0


# ------------------------------------------------------------------ the lorry

func deliver(_seconds: float) -> void:
	if _lorry != null:
		return
	_lorry = Assets.instance("delivery/lorry")
	add_child(_lorry)
	_door = Assets.instance("delivery/lorry_door")
	_lorry.add_child(_door)
	_door.position = Vector3(0, 0.64 + 2.3, 3.0)
	_load()

	var start := Vector3(_gate_x - RUN_UP, 0, _street)
	var halt := Vector3(_gate_x + 9.0, 0, _street)
	var lined := Vector3(_gate_x + 8.0, 0, _street - 2.5)
	var parked := Vector3(_gate_x, 0, _at.z - 3.2)
	_drive(start, halt, -PI * 0.5)
	_message = "машина в пути"

	var run := create_tween()
	# in fast and slowing to a stop, which is most of what makes it read as driving
	run.tween_method(func(t: float) -> void: _drive(start, halt, -PI * 0.5, t),
		0.0, 1.0, APPROACH).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	run.tween_callback(func() -> void:
		_message = "ворота открываются"
		_site.slide_gate(true))
	run.tween_interval(GATE_SLIDE)
	# One reversing path from the road to the bay, and the lorry points along it. Yaw
	# turned on its own while the body slid down a curve is what read as flying: a
	# vehicle that is not facing where it is going is not driving anywhere.
	run.tween_method(func(t: float) -> void: _back(halt, lined, parked, t),
		0.0, 1.0, BACK_IN).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	run.tween_callback(func() -> void:
		_parked = true
		_swing(true)
		_message = "кузов открыт — забирайте")


func leave() -> void:
	## Empty, so it goes. Called when the last piece comes out of the back.
	if _lorry == null or not _parked:
		return
	_parked = false
	_swing(false)
	var halt := Vector3(_gate_x + 9.0, 0, _street)
	var lined := Vector3(_gate_x + 8.0, 0, _street - 2.5)
	var parked := Vector3(_gate_x, 0, _at.z - 3.2)
	var run := create_tween()
	run.tween_interval(DOOR_SWING)
	run.tween_method(func(t: float) -> void: _back(halt, lined, parked, 1.0 - t, false),
		0.0, 1.0, BACK_IN).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	run.tween_callback(func() -> void: _site.slide_gate(false))
	run.tween_method(func(t: float) -> void:
		_drive(halt, Vector3(_gate_x + RUN_UP, 0, _street), -PI * 0.5, t),
		0.0, 1.0, APPROACH * 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	run.tween_callback(func() -> void:
		if _lorry != null and is_instance_valid(_lorry):
			_lorry.queue_free()
		_lorry = null
		_door = null
		_message = "")


func _drive(from: Vector3, to: Vector3, yaw: float, t := 0.0) -> void:
	_pose(from.lerp(to, t), yaw)


func _back(halt: Vector3, lined: Vector3, parked: Vector3, t: float,
		reversing := true) -> void:
	## A quadratic through the road and into the yard, with the lorry pointing along
	## it. Reversing means the cab faces backwards along the path, which is the only
	## difference between coming in and going out.
	var here := _curve(halt, lined, parked, t)
	var ahead := _curve(halt, lined, parked, clampf(t + 0.02, 0.0, 1.0))
	var step := ahead - here
	if t > 0.98:
		step = here - _curve(halt, lined, parked, t - 0.02)
	if step.length_squared() < 1e-6:
		return
	step = step.normalized()
	# the model looks along -Z, so driving forwards points -Z at the step and
	# reversing points it the other way
	_pose(here, atan2(step.x, step.z) if reversing else atan2(-step.x, -step.z))


func _curve(a: Vector3, b: Vector3, d: Vector3, t: float) -> Vector3:
	## A cubic, and its third point sits on the gate's axis behind the bay on purpose:
	## the tangent at the end is then straight down that axis, so the lorry finishes
	## square instead of parking at forty-eight degrees to everything.
	var c := Vector3(d.x, 0, _street - 1.0)
	var ab := a.lerp(b, t)
	var bc := b.lerp(c, t)
	var cd := c.lerp(d, t)
	return ab.lerp(bc, t).lerp(bc.lerp(cd, t), t)


func _pose(at: Vector3, yaw: float) -> void:
	if _lorry == null or not is_instance_valid(_lorry):
		return
	_lorry.global_position = at
	_lorry.rotation.y = yaw


func _swing(open: bool) -> void:
	if _door == null or not is_instance_valid(_door):
		return
	_open = open
	var turn := create_tween()
	turn.tween_property(_door, "rotation:x", deg_to_rad(-96.0 if open else 0.0),
		DOOR_SWING).set_trans(Tween.TRANS_CUBIC)


# -------------------------------------------------------------------- the load

func _load() -> void:
	for i in ORDER.size():
		var part := Assets.instance("delivery/%s" % ORDER[i])
		_lorry.add_child(part)
		part.position = Vector3(0, BED, 0) + STOWED[i]
		_parts.append({"node": part, "kind": i, "loose": null})


static func part_box(kind: int) -> AABB:
	## The piece's own bounds, straight off its mesh: a box typed out by hand is wrong
	## the first time a model changes, and it was half a metre too big in every
	## direction.
	var mesh := Assets.mesh("delivery/%s" % ORDER[mini(kind, ORDER.size() - 1)])
	return mesh.get_aabb() if mesh != null else AABB(Vector3.ZERO, Vector3.ONE * 0.2)


func _piece_of(kind: int) -> Dictionary:
	for piece in _parts:
		if piece["kind"] == kind:
			return piece
	return {}


func _part_at(kind: int) -> Vector3:
	var piece := _piece_of(kind)
	if piece.is_empty():
		return _at
	var node: Node3D = piece["loose"] if piece["loose"] != null else piece["node"]
	return node.global_position + part_box(kind).get_center()


func aim_for(part: String) -> Vector3:
	## Where a piece of that kind is. Which of four identical uprights it is does not
	## matter to anybody, so it must not matter here either.
	for piece in _parts:
		if ORDER[piece["kind"]] == part:
			return _part_at(piece["kind"])
	return _at


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
	var bounds := part_box(kind)
	_outline.show_at(Transform3D(Basis().scaled(bounds.size), _part_at(kind)),
		Outline.COOL)


func _show_target() -> void:
	## Where the piece in your hands would go. Carrying something somewhere and being
	## told no only once you press the key is a guessing game.
	var spot: Dictionary = _site.spot_under(_eye.global_position,
		-_eye.global_transform.basis.z, REACH * 2.0)
	if spot.is_empty():
		_outline.visible = false
		return
	var bounds := part_box(_taken)
	var at: Vector3 = _site.part_place(spot) + bounds.get_center()
	_outline.show_at(Transform3D(Basis().scaled(bounds.size), at),
		Outline.COOL if _site.can_build(spot, ORDER[_taken]) else Outline.WARM)


func _pick_part() -> int:
	## The piece the crosshair is on, as a box. What is still in the lorry can only be
	## reached once the back is open; what has been put down is lying on the ground.
	if _parts.is_empty() or _eye == null or not is_instance_valid(_eye) or _taken >= 0:
		return -1
	var origin := _eye.global_position
	var dir := -_eye.global_transform.basis.z
	var best := -1
	var best_at := REACH
	for i in _parts.size():
		if _parts[i]["loose"] == null and not _open:
			continue
		var kind: int = _parts[i]["kind"]
		var half := part_box(kind).size * 0.5
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


func _aiming_at_doors() -> bool:
	if _lorry == null or not is_instance_valid(_lorry) or _eye == null:
		return false
	var back := _lorry.global_transform * Vector3(0, 1.6, 3.2)
	if _eye.global_position.distance_to(back) > REACH:
		return false
	var towards := (back - _eye.global_position).normalized()
	return -_eye.global_transform.basis.z.dot(towards) > 0.55


# ---------------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if _site.reading_screen():
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_E and _parked and _aiming_at_doors():
		_swing(not _open)
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_X:
		if _taken >= 0:
			_place_part()
		elif _aimed >= 0 and _aimed < _parts.size():
			_take_part(_aimed)
	elif event.keycode == KEY_V and _taken >= 0:
		_throw()


func open_crate(open: bool) -> void:
	if _parked and _open != open:
		_swing(open)


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
	_aimed = -1
	_outline.visible = false


func _place_part() -> void:
	var spot: Dictionary = _site.spot_under(_eye.global_position,
		-_eye.global_transform.basis.z, REACH * 2.0)
	if spot.is_empty():
		_message = "ставить надо на размеченное место"
		return
	if not _site.can_build(spot, ORDER[_taken]):
		_message = "сначала ставится %s" % _name(_site.built_steps(spot))
		return
	_site.build_step(spot, ORDER[_taken])
	_drop_piece(_taken)
	_hands_free()
	_message = ""
	if _parts.is_empty():
		leave()


func _drop_piece(kind: int) -> void:
	for i in _parts.size():
		if _parts[i]["kind"] == kind:
			(_parts[i]["node"] as Node3D).queue_free()
			var loose = _parts[i]["loose"]
			if loose != null and is_instance_valid(loose):
				loose.queue_free()
			_parts.remove_at(i)
			return


func _throw() -> void:
	## Out of the hands and onto the ground, as a body that falls. Something carried
	## that can only be installed or carried forever is not a thing you are holding, it
	## is a state you are in.
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
	body.apply_central_impulse(-_eye.global_transform.basis.z * 22.0 + Vector3.UP * 4.0)

	var piece := _piece_of(kind)
	if not piece.is_empty():
		piece["loose"] = body
	_hands_free()
	_message = "положили на землю"


func _hands_free() -> void:
	_taken = -1
	_aimed = -1
	if _carried != null and is_instance_valid(_carried):
		_carried.queue_free()
	_carried = null


func _name(kind: int) -> String:
	if kind < 0 or kind >= ORDER.size():
		return "деталь"
	return NAMED.get(ORDER[kind], ORDER[kind])


func solid_boxes() -> Array:
	if _lorry == null or not is_instance_valid(_lorry):
		return []
	return [{"xform": _lorry.global_transform.translated_local(Vector3(0, 1.8, -0.9)),
		"half": Vector3(1.2, 1.2, 2.1)}]
