class_name ShowroomPlayer
extends CharacterBody3D

## Throwaway first-person camera for looking at the asset library.
## The real player controller belongs with the vertical slice, not here.

const SPEED := 2.6
const RUN := 6.0
const FLY := 4.5
const MOUSE := 0.0022

@export var flying := false

var _camera: Camera3D
var _pitch := 0.0


func _ready() -> void:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.75
	capsule.radius = 0.3
	shape.shape = capsule
	shape.position.y = 0.875
	add_child(shape)

	_camera = Camera3D.new()
	_camera.position.y = 1.65
	_camera.fov = 70.0
	_camera.far = 300.0
	add_child(_camera)

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
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
	var input := Vector3(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		0.0,
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W)),
	)
	var dir := (transform.basis * input).normalized()
	var speed := RUN if Input.is_key_pressed(KEY_SHIFT) else SPEED

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
