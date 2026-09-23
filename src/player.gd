class_name ShowroomPlayer
extends CharacterBody3D

## Throwaway first-person camera for looking at the asset library.
## The real player controller belongs with the vertical slice, not here.

const SPEED := 2.6
const RUN := 6.0
const CROUCH_SPEED := 1.2
const FLY := 4.5
const MOUSE := 0.0022
const EYE := 1.65
const CROUCH_EYE := 0.95   # low enough to work the bottom of a rack
const STAND_H := 1.75
const CROUCH_H := 1.05

@export var flying := false
## Off for the automated checks. They drive the game with synthesised key events and
## do not need the pointer, and grabbing it locks the desktop out from under whoever
## is using the machine — the taskbar stops answering the mouse until the run ends.
@export var grab_mouse := true
## Set while the player is using something in the world — at the laptop, the keys and
## the mouse belong to that screen and not to walking around.
var frozen := false

var _camera: Camera3D
var _shape: CollisionShape3D
var _capsule: CapsuleShape3D
var _pitch := 0.0
var _crouching := false


func _ready() -> void:
	_shape = CollisionShape3D.new()
	_capsule = CapsuleShape3D.new()
	_capsule.height = STAND_H
	_capsule.radius = 0.3
	_shape.shape = _capsule
	_shape.position.y = STAND_H / 2
	add_child(_shape)

	_camera = Camera3D.new()
	_camera.position.y = EYE
	_camera.fov = 70.0
	_camera.far = 300.0
	add_child(_camera)
	# Explicitly, not by being the first camera in the room: the laptop builds its own
	# camera while the shed does, so whoever enters the tree first would otherwise own
	# the view and the game would open looking at a desk.
	_camera.make_current()

	if grab_mouse:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func eye() -> Camera3D:
	## The camera the player looks through. Anything that takes the view away — a
	## screen, a cutscene — has to be handed this rather than read whichever camera
	## happens to be current, or it gives the view back to itself.
	return _camera


func _unhandled_input(event: InputEvent) -> void:
	if frozen:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE)
		_pitch = clamp(_pitch - event.relative.y * MOUSE, -1.5, 1.5)
		_camera.rotation.x = _pitch
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				Input.mouse_mode = (Input.MOUSE_MODE_VISIBLE
					if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
					else Input.MOUSE_MODE_CAPTURED)
			KEY_F:
				flying = not flying
			KEY_Q:
				get_tree().quit()


func _physics_process(delta: float) -> void:
	if frozen:
		velocity = Vector3.ZERO
		return
	var input := Vector3(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		0.0,
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W)),
	)
	var dir := (transform.basis * input).normalized()

	# Ctrl crouches on the ground and descends in flight — the bottom of a rack is
	# 50 mm off the floor and there is no seeing it standing up.
	_crouching = not flying and Input.is_key_pressed(KEY_CTRL)
	var wanted := CROUCH_H if _crouching else STAND_H
	if not is_equal_approx(_capsule.height, wanted):
		_capsule.height = move_toward(_capsule.height, wanted, 4.0 * delta)
		_shape.position.y = _capsule.height / 2
		_camera.position.y = EYE - (STAND_H - _capsule.height) * ((EYE - CROUCH_EYE)
			/ (STAND_H - CROUCH_H))

	var speed := CROUCH_SPEED if _crouching else (
		RUN if Input.is_key_pressed(KEY_SHIFT) else SPEED)

	if flying:
		var lift := float(Input.is_key_pressed(KEY_SPACE)) - float(Input.is_key_pressed(KEY_CTRL))
		velocity = dir * FLY + Vector3.UP * lift * FLY
	else:
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
		if is_on_floor() and Input.is_key_pressed(KEY_SPACE):
			velocity.y = 4.0
		else:
			velocity.y -= 12.0 * delta
	move_and_slide()
