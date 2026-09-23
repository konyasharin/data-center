class_name Laptop
extends Node3D

## The laptop as something you walk up to and use, rather than a menu key.
##
## The screen is a SubViewport painted onto the display quad, so the operating system
## is visible across the room and is lit by the same room (docs/09: диегетические
## экраны). Sitting down moves a camera in front of it and hands the mouse over; the
## pointer is the real one, projected onto the plane of the screen, because a second
## cursor drawn inside the viewport drifts away from the one the player is moving.

const SCREEN := Vector2i(960, 600)
const FLY := 0.5             # seconds the camera takes to get to the screen and back
const REACH := 1.6           # metres you can be from the desk and still sit down
# How far off the screen you may be looking. Generous on purpose: a laptop on a desk
# is well below eye level, so standing right at it you are looking down at it by a
# long way, and a tighter cone means the prompt only appears if you stoop.
const AIM := 0.32

var _display: Node3D
var _panel: MeshInstance3D
var _viewport: SubViewport
var _os: LaptopOS
var _seat: Camera3D
var _player: ShowroomPlayer
var _eye: Camera3D
var _pose: Transform3D
var _flight: Tween
var _open := false


func setup(display: Node3D, estate: EstateBridge, site: Object) -> void:
	_display = display
	_panel = _first_mesh(display)
	if _panel == null:
		push_error("laptop: the display has no mesh to paint the screen on")
		return

	_viewport = SubViewport.new()
	_viewport.size = SCREEN
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# The screen is a small texture seen from 40 cm away, where the engine's default
	# 3D scaling would resolve it at half size and the text would be unreadable.
	_viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	add_child(_viewport)

	_os = LaptopOS.new()
	_viewport.add_child(_os)
	_os.setup(estate, site)

	var lit := StandardMaterial3D.new()
	lit.albedo_texture = _viewport.get_texture()
	lit.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lit.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	# A viewport hands back what 2D wrote, which is already sRGB. Sampled as linear it
	# comes out washed: the dark desktop reads as light grey and every panel on it
	# disappears into the background.
	lit.albedo_texture_force_srgb = true
	_panel.material_override = lit

	_seat = Camera3D.new()
	_seat.fov = 42.0
	add_child(_seat)
	# After entering the tree, not before: a camera that is the first one in the
	# viewport becomes the current one on the way in, and this one is built while the
	# shed is, long before the player exists. The room would open looking at the desk.
	_seat.current = false
	_place_seat()


func attach_player(player: ShowroomPlayer) -> void:
	_player = player
	_eye = player.eye()


func is_open() -> bool:
	return _open


func prompt() -> String:
	if _open:
		return "ноутбук: ЛКМ — выбрать, Esc — встать"
	return "E — сесть за ноутбук" if _within_reach() else ""


func try_open() -> bool:
	## Called before the scene's own E handling, so standing at the desk opens the
	## laptop and standing at a rack still opens the door.
	if _open:
		close()
		return true
	if not _within_reach():
		return false
	_open = true
	# Starting from where the player's eyes are and moving in, rather than cutting.
	# Sitting down at a desk is a movement, and a cut leaves you working out where you
	# are looking from instead of reading the screen.
	if _eye != null and is_instance_valid(_eye):
		_seat.global_transform = _eye.global_transform
	_seat.current = true
	_fly_to(_pose, Callable())
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _player != null:
		_player.frozen = true
	return true


func close() -> void:
	if not _open:
		return
	_open = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if _eye == null or not is_instance_valid(_eye):
		_seat.current = false
		if _player != null:
			_player.frozen = false
		return
	# Frozen until the camera lands: walking away while the view is still pulling back
	# out of the screen is the one thing worse than the cut it replaces.
	_fly_to(_eye.global_transform, _stand_up)


func _stand_up() -> void:
	_seat.current = false
	if _eye != null and is_instance_valid(_eye):
		_eye.make_current()
	if _player != null:
		_player.frozen = false


func _fly_to(to: Transform3D, then: Callable) -> void:
	var from := _seat.global_transform
	if _flight != null and _flight.is_valid():
		_flight.kill()
	_flight = create_tween()
	_flight.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_flight.tween_method(
		func(t: float) -> void: _seat.global_transform = from.interpolate_with(to, t),
		0.0, 1.0, FLY)
	if not then.is_null():
		_flight.finished.connect(then)


func show_app(id: String) -> void:
	if _os != null:
		_os.open(id)


func seat_pose() -> Array:
	## Where a shot of the screen is taken from: the same place the player's eyes are
	## when they sit down, so what a screenshot shows is what they will read.
	if _panel == null:
		return []
	var box := _panel.get_aabb()
	return [_seat.global_position, _panel.global_transform * box.get_center()]


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		var at := _screen_hit(event.position)
		if at.x < 0.0:
			return
		var copy := event.duplicate()
		copy.position = at
		if copy is InputEventMouseMotion:
			copy.global_position = at
		else:
			copy.global_position = at
		_viewport.push_input(copy, true)
		get_viewport().set_input_as_handled()


func _screen_hit(mouse: Vector2) -> Vector2:
	## Where on the screen the real pointer is, in viewport pixels, or (-1, -1) when it
	## is off the panel.
	var camera := _seat
	var origin := camera.project_ray_origin(mouse)
	# nothing lands on the screen while the camera is still on its way in
	if _flight != null and _flight.is_valid():
		return Vector2(-1, -1)
	var dir := camera.project_ray_normal(mouse)
	var to_panel := _panel.global_transform
	var normal := to_panel.basis.z.normalized()
	var denom := dir.dot(normal)
	if absf(denom) < 0.0001:
		return Vector2(-1, -1)
	var box := _panel.get_aabb()
	var centre := to_panel * box.get_center()
	var t := (centre - origin).dot(normal) / denom
	if t <= 0.0:
		return Vector2(-1, -1)

	var local := to_panel.affine_inverse() * (origin + dir * t)
	var span := box.size
	if span.x <= 0.0 or span.y <= 0.0:
		return Vector2(-1, -1)
	var u := (local.x - box.get_center().x) / span.x + 0.5
	var v := 0.5 - (local.y - box.get_center().y) / span.y
	if u < 0.0 or u > 1.0 or v < 0.0 or v > 1.0:
		return Vector2(-1, -1)
	return Vector2(u * SCREEN.x, v * SCREEN.y)


func _place_seat() -> void:
	var box := _panel.get_aabb()
	var centre := _panel.global_transform * box.get_center()
	var normal := _panel.global_transform.basis.z.normalized()
	# Far enough back that the whole lid is in frame and a hand would still reach the
	# keyboard; slightly above centre, which is where eyes are when you sit down.
	_seat.global_position = centre + normal * 0.44 + Vector3.UP * 0.07
	_seat.look_at(centre, Vector3.UP)
	_pose = _seat.global_transform


func reach_numbers() -> Array:
	## How far the eye is from the screen and how squarely it is pointed at it, which
	## is what decides whether the prompt appears. Judging a cone by eye is how it ends
	## up either unusable or triggering from across the room.
	var camera := _eye if _eye != null else get_viewport().get_camera_3d()
	if _panel == null or camera == null:
		return []
	var centre := _panel.global_transform * _panel.get_aabb().get_center()
	var to_screen := (centre - camera.global_position).normalized()
	return [camera.global_position.distance_to(centre),
		-camera.global_transform.basis.z.dot(to_screen)]


func _within_reach() -> bool:
	if _panel == null:
		return false
	var camera := _eye if _eye != null else get_viewport().get_camera_3d()
	if camera == null or not is_instance_valid(camera):
		return false
	var box := _panel.get_aabb()
	var centre := _panel.global_transform * box.get_center()
	if camera.global_position.distance_to(centre) > REACH:
		return false
	var to_screen := (centre - camera.global_position).normalized()
	return -camera.global_transform.basis.z.dot(to_screen) > AIM


func _first_mesh(root: Node) -> MeshInstance3D:
	for node in _walk(root):
		if node is MeshInstance3D:
			return node
	return null


func _walk(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for child in node.get_children():
		out.append_array(_walk(child))
	return out
