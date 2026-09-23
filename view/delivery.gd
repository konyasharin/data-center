class_name Delivery
extends Node3D

## What happens between paying for a cabinet and standing one up.
##
## A lorry comes in off the street, stops at the bay, and a crate is left there. The
## crate is opened by hand, and what is inside is the cabinet in pieces: a base, four
## uprights, two sides. The player carries them to a marked place one at a time, in
## the order they go together, and the cabinet grows as they arrive.
##
## Nothing here is a job in the queue. The crew does work the player delegates; this
## is the work the player does, and the difference is the whole reason the crate is
## opened by hand rather than by somebody in a hi-vis.

const ORDER := ["rack_part_base", "rack_part_upright", "rack_part_upright",
	"rack_part_upright", "rack_part_upright", "rack_part_side", "rack_part_side"]
const NAMED := {
	"rack_part_base": "основание",
	"rack_part_upright": "стойка-профиль",
	"rack_part_side": "боковина",
}
const DRIVE_IN := 7.0        # seconds the lorry takes to arrive and leave again
const REACH := 2.6
const LID_OPEN := -100.0
const CARRY := Vector3(0.36, -0.42, -0.78)

var _site: Object
var _eye: Camera3D
var _lorry: Node3D
var _crate: Node3D
var _lid: Node3D
var _parts: Array[Node3D] = []       # what is still in the crate, in reverse order
var _taken := -1                     # index of the part in the player's hands
var _carried: Node3D
var _open := false
var _at := Vector3.ZERO
var _message := ""


func setup(site: Object, eye: Camera3D, bay: Vector3) -> void:
	_site = site
	_eye = eye
	_at = bay


func report() -> String:
	return "ящик %s, деталей %d, в руках %d, сообщение «%s»" % [
		_crate != null, _parts.size(), _taken, _message]


func hud_text() -> String:
	if _taken >= 0:
		return "в руках %s · наведитесь на размеченное место, X — поставить" % _name(_taken)
	if _crate != null and _aiming_at_crate():
		return "E — %s ящик" % ("закрыть" if _open else "открыть")
	if _open and not _parts.is_empty() and _aiming_at_crate(true):
		return "X — взять %s" % _name(_parts.size() - 1)
	return _message


func busy() -> bool:
	return _crate != null or _lorry != null or _taken >= 0


func deliver(seconds: float) -> void:
	## A lorry in off the street. It is never driven — it slides along the road, stops
	## at the bay for as long as unloading takes, and slides off again.
	if _lorry != null:
		return
	_lorry = Assets.instance("delivery/lorry")
	add_child(_lorry)
	var road := _at + Vector3(0, 0, -9.0)
	var away := road + Vector3(46, 0, 0)
	_lorry.rotation.y = PI * 0.5
	_lorry.global_position = road - Vector3(46, 0, 0)
	_message = "машина в пути"

	var run := create_tween()
	run.tween_property(_lorry, "global_position", road, DRIVE_IN * 0.45) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	run.tween_callback(func() -> void:
		_drop_crate()
		_message = "разгрузка")
	run.tween_interval(maxf(1.0, seconds))
	run.tween_property(_lorry, "global_position", away, DRIVE_IN * 0.45) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	run.tween_callback(func() -> void:
		_lorry.queue_free()
		_lorry = null
		_message = "ящик на площадке: E — открыть")


func _drop_crate() -> void:
	# added to the tree before being placed: a node that is not in it has no global
	# transform, and Godot answers the question with an identity and an error
	_crate = Assets.instance("delivery/crate_body")
	add_child(_crate)
	_crate.global_position = _at
	_lid = Assets.instance("delivery/crate_lid")
	add_child(_lid)
	# the hinge line is the crate's back top edge, and the model is authored about it
	_lid.global_position = _at + Vector3(0, 2.14, 0.64)

	for i in ORDER.size():
		var part := Assets.instance("delivery/%s" % ORDER[i])
		part.visible = false
		add_child(part)
		_parts.append(part)
	_stack()


func _stack() -> void:
	## What is left, standing in the crate. Only the top one is reachable, so the rest
	## are there to show the crate emptying.
	for i in _parts.size():
		var part: Node3D = _parts[i]
		part.visible = _open
		part.global_position = _at + Vector3(0.0, 0.16, -0.24 + i * 0.07)
		part.rotation = Vector3(0, 0, 0)


# -------------------------------------------------------------------- input

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
		elif _open and not _parts.is_empty() and _aiming_at_crate(true):
			_take_part()


func _swing(open: bool) -> void:
	_open = open
	var turn := create_tween()
	turn.tween_property(_lid, "rotation:x", deg_to_rad(LID_OPEN if open else 0.0), 0.5) \
		.set_trans(Tween.TRANS_CUBIC)
	_stack()


func _take_part() -> void:
	_taken = _parts.size() - 1
	var part: Node3D = _parts[_taken]
	part.visible = false
	_carried = Assets.instance("delivery/%s" % ORDER[_taken])
	_carried.position = CARRY
	_carried.scale = Vector3.ONE * 0.5
	_eye.add_child(_carried)


func _place_part() -> void:
	var spot: Dictionary = _site.spot_under(_eye.global_position,
		-_eye.global_transform.basis.z, REACH * 2.0)
	if spot.is_empty():
		_message = "ставить надо на размеченное место"
		return
	if not _site.can_build(spot, ORDER.size() - _taken - 1):
		_message = "сначала ставится %s" % _name(_next_for(spot))
		return
	_site.build_step(spot, ORDER.size() - _taken - 1, ORDER[_taken])
	_parts.remove_at(_taken)
	_taken = -1
	if _carried != null and is_instance_valid(_carried):
		_carried.queue_free()
	_carried = null
	_message = ""
	if _parts.is_empty():
		_clear_crate()


func _next_for(spot: Dictionary) -> int:
	var done: int = _site.built_steps(spot)
	return ORDER.size() - done - 1


func _clear_crate() -> void:
	if _crate != null:
		_crate.queue_free()
	if _lid != null:
		_lid.queue_free()
	_crate = null
	_lid = null
	_open = false
	_message = ""


# ------------------------------------------------------------------ helpers

func _name(index: int) -> String:
	if index < 0 or index >= ORDER.size():
		return "деталь"
	return NAMED.get(ORDER[index], ORDER[index])


func _aiming_at_crate(inside := false) -> bool:
	if _crate == null or _eye == null or not is_instance_valid(_eye):
		return false
	# generous: a crate is a big thing at arm's length, and a tight cone means hunting
	# for the one spot on it the game agrees is the crate
	var centre := _at + Vector3(0, 1.1 if not inside else 1.8, 0)
	if _eye.global_position.distance_to(centre) > REACH:
		return false
	var towards := (centre - _eye.global_position).normalized()
	return -_eye.global_transform.basis.z.dot(towards) > 0.55


func solid_boxes() -> Array:
	## What the crate stops the crosshair seeing through, handed to whoever asks.
	if _crate == null:
		return []
	return [{"xform": Transform3D(Basis(), _at + Vector3(0, 1.07, 0)),
		"half": Vector3(0.45, 1.07, 0.68)}]
