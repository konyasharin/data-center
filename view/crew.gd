class_name Crew
extends Node3D

## The people who actually do what the laptop ordered.
##
## A worker is a row, not a character (docs/04-workers.md): state, target, job and a
## body borrowed only while it is on screen. Two of them here is not the pool that
## doc describes — that arrives with the vertical slice — but the shape is the same
## one, so growing it is a change of size and not a change of design.
##
## The crew decides nothing about what it is building. It claims a job from the
## queue, walks the path the navigation map gives it, plays the clip the site names
## for as long as the core says the work takes, and hands the job back when done.

const WALK := 1.25            # m/s, the speed the walk clip is authored at
const ARRIVED := 0.35
const TURN := 6.0
const CORNER := 0.25          # how close counts as reaching a corner of the path
const REPLAN := 0.7
const CORD := Color(0.22, 0.62, 0.30)

enum State { IDLE, WALKING, WORKING }

var _estate: EstateBridge
var _site: Object
var _wiring: Wiring
var _body: Array[Node3D] = []
var _anim: Array[AnimationPlayer] = []
var _bundle: Array[Node3D] = []    # left hand: the coil of cords being worked from
var _tip: Array[Node3D] = []       # right hand: the end going into the socket
var _head: Array[Node3D] = []      # only for the diagnostics below
var _cord: Array[MeshInstance3D] = []
var _route: Array[PackedVector3Array] = []
var _goal := PackedVector3Array()
var _stale := PackedFloat32Array()
var _state := PackedInt32Array()
var _job := PackedInt32Array()
var _seat := PackedInt32Array()
var _owns := []
var _home := PackedVector3Array()
var _said := PackedFloat32Array()  # seconds since this worker last made a noise


func setup(estate: EstateBridge, site: Object, wiring: Wiring, posts: Array) -> void:
	_estate = estate
	_site = site
	_wiring = wiring
	for at in posts:
		var worker: Node3D = Assets.scene("characters/worker")
		worker.position = at
		add_child(worker)
		var skeleton := _skeleton_of(worker)
		_wear(skeleton, "Head", Assets.instance("characters/helmet"))

		var cord := MeshInstance3D.new()
		cord.material_override = _wiring.cord_material()
		cord.visible = false
		add_child(cord)

		_body.append(worker)
		_anim.append(_player_of(worker))
		_bundle.append(_bone(skeleton, "LeftHand"))
		_tip.append(_bone(skeleton, "RightHand"))
		_head.append(_bone(skeleton, "Head"))
		_cord.append(cord)
		_route.append(PackedVector3Array())
		_goal.append(at)
		_stale.append(0.0)
		_state.append(State.IDLE)
		_job.append(-1)
		_seat.append(0)
		_owns.append(false)
		_home.append(at)
		_said.append(0.0)
		_play(_body.size() - 1, "idle")


func _process(delta: float) -> void:
	if _estate == null:
		return
	for i in _body.size():
		match _state[i]:
			State.IDLE:
				_look_for_work(i)
			State.WALKING:
				_walk(i, delta)
			State.WORKING:
				_work(i, delta)
		_draw_cord(i)


# ------------------------------------------------------------------ choosing

func _look_for_work(i: int) -> void:
	var job: int = _estate.Claim(i)
	if job >= 0:
		# One person per cabinet. Two technicians patching different servers into the
		# same rack stand in the same half metre with their arms through each other:
		# the work is not the constraint, the space in front of it is.
		if _crowded(_site.job_place(job), i):
			_estate.Release(job)
			return
		_take(i, job, true)
		return
	var helping := _needs_a_hand(i)
	if helping >= 0:
		_take(i, helping, false)
		return
	if _body[i].position.distance_to(_home[i]) > ARRIVED:
		_job[i] = -1
		_owns[i] = false
		_head_for(i, _home[i])


func _crowded(place: int, except: int) -> bool:
	for other in _body.size():
		if other == except or _job[other] < 0:
			continue
		if _site.job_place(_job[other]) == place:
			return true
	return false


func _needs_a_hand(i: int) -> int:
	## Some work wants two people. The second is not a second claim — the queue hands a
	## job to one worker — but watching one person wrestle a cabinet alone is worse
	## than the simplification.
	for other in _body.size():
		if other == i or _job[other] < 0 or not _owns[other]:
			continue
		if _site.job_crew(_job[other]) < 2:
			continue
		var taken := false
		for third in _body.size():
			if third != other and _job[third] == _job[other]:
				taken = true
		if not taken:
			return _job[other]
	return -1


func _take(i: int, job: int, owns: bool) -> void:
	_job[i] = job
	_owns[i] = owns
	_seat[i] = 0 if owns else 1
	_head_for(i, _site.job_site(job, _seat[i]))


# ------------------------------------------------------------------- walking

func _head_for(i: int, to: Vector3) -> void:
	_goal[i] = to
	_stale[i] = 0.0
	_route[i] = _path(_body[i].position, to)
	_state[i] = State.WALKING
	_play(i, "walk")


func _path(from: Vector3, to: Vector3) -> PackedVector3Array:
	## Around the furniture rather than through it. A map that has not finished its
	## first build answers with an error rather than an empty path, and the route is
	## asked for again every second anyway.
	var map := get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return PackedVector3Array([to])
	var found := NavigationServer3D.map_get_path(map, from, to, true)
	if found.size() < 2:
		return PackedVector3Array([to])
	# the last corner is the closest point on the mesh, which is not the same as the
	# spot beside the rack the site asked for
	found[found.size() - 1] = to
	return found


func _walk(i: int, delta: float) -> void:
	var body := _body[i]
	# Asked for again now and then: the map finishes building a few frames into the
	# session, and a cabinet raised in the meantime is not in a route planned before it.
	_stale[i] += delta
	if _stale[i] > REPLAN:
		_stale[i] = 0.0
		var fresh := _path(body.position, _goal[i])
		if fresh.size() > 1 or _route[i].size() <= 1:
			_route[i] = fresh
	if _route[i].is_empty():
		_arrive(i)
		return
	var corner: Vector3 = _route[i][0]
	corner.y = body.position.y
	var step := corner - body.position
	var close: float = ARRIVED if _route[i].size() == 1 else CORNER
	if step.length() < close:
		_route[i].remove_at(0)
		if _route[i].is_empty():
			_arrive(i)
		return
	body.position += step.normalized() * WALK * delta
	_face(i, step, delta)


# ------------------------------------------------------------------- working

func _arrive(i: int) -> void:
	if _job[i] < 0:
		_state[i] = State.IDLE
		_play(i, "idle")
		return
	_state[i] = State.WORKING
	_said[i] = 0.0
	_play(i, _site.job_clip(_job[i]))
	var coil: String = _site.job_prop(_job[i])
	if not coil.is_empty():
		var prop := Assets.instance(coil)
		# Smaller than the one on the shelf and hanging off the hand rather than
		# centred on it, or it reads as a bracelet worn round the wrist.
		prop.scale = Vector3(0.38, 0.38, 0.38)
		prop.position = Vector3(0.0, -0.07, 0.0)
		_wear_in(_bundle[i], prop)
	if _owns[i]:
		_site.job_started(_job[i])


func _work(i: int, delta: float) -> void:
	_face(i, _site.job_facing(_job[i], _seat[i]), delta)
	_noise(i, delta)
	if not _owns[i]:
		# the helper stops when the job does, which it notices rather than is told
		if _estate.JobStateOf(_job[i]) == 2:
			_finish(i)
		return
	var before := _estate.JobProgressOf(_job[i])
	if not _estate.Advance(_job[i], delta):
		_site.job_tick(_job[i], before, _estate.JobProgressOf(_job[i]))
		return
	_site.job_tick(_job[i], before, 1.0)
	_site.job_done(_job[i])
	_finish(i)


func _noise(i: int, delta: float) -> void:
	## Work is heard before it is seen, and the interval comes from the site because it
	## belongs to the clip: a sound that drifts against the motion reads as somebody
	## else working off screen.
	_said[i] += delta
	var every: float = _site.job_beat(_job[i])
	if every <= 0.0 or _said[i] < every:
		return
	_said[i] = 0.0
	var sound: String = _site.job_sound(_job[i])
	if not sound.is_empty():
		say(_body[i].global_position + Vector3(0, 1.0, 0), sound, -9.0)


func say(at: Vector3, stream: String, volume := -6.0) -> void:
	var player := AudioStreamPlayer3D.new()
	player.stream = load("res://assets/audio/%s.wav" % stream)
	player.position = at
	player.unit_size = 3.0
	player.max_db = volume
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)


func _finish(i: int) -> void:
	_job[i] = -1
	_owns[i] = false
	_wear_in(_bundle[i], null)
	_state[i] = State.IDLE
	_play(i, "idle")


# ------------------------------------------------------------------- the cord

func _draw_cord(i: int) -> void:
	## The lead itself, hanging between the coil in one hand and the end in the other.
	## Rebuilt every frame because both ends are bones in motion, and it is the whole
	## reason the patching reads as patching rather than as reaching at a cabinet.
	var showing: bool = _state[i] == State.WORKING and _bundle[i] != null \
		and _tip[i] != null and _job[i] >= 0 \
		and not _site.job_prop(_job[i]).is_empty()
	if not showing:
		_cord[i].visible = false
		return
	var from: Vector3 = _bundle[i].global_position
	var to: Vector3 = _tip[i].global_position
	if from.distance_to(to) < 0.03:
		_cord[i].visible = false
		return
	_cord[i].visible = true
	# out of the coil downwards and into the socket along the reach, which keeps the
	# loop hanging below the hands instead of cutting through the forearms
	_cord[i].mesh = _wiring.loose_cord(from, Vector3.DOWN, to, (to - from).normalized(),
		CORD)


# ------------------------------------------------------------------- plumbing

func _face(i: int, towards: Vector3, delta: float) -> void:
	towards.y = 0.0
	if towards.length_squared() < 0.0001:
		return
	# The model is authored with its front along +Z (docs/14-art-assets.md), so a body
	# turned to atan2(x, z) looks along the vector rather than away from it.
	var want := atan2(towards.x, towards.z)
	_body[i].rotation.y = rotate_toward(_body[i].rotation.y, want, TURN * delta)


func _play(i: int, clip: String) -> void:
	var anim := _anim[i]
	if anim == null or not anim.has_animation(clip):
		return
	if anim.current_animation == clip:
		return
	anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	anim.play(clip)


func cord_report() -> String:
	## Whether the lead in someone's hands is actually being built, and how far apart
	## the hands are. Both are invisible in a screenshot taken from the wrong side, and
	## guessing which of the two is wrong costs a run each time.
	var out := PackedStringArray()
	for i in _body.size():
		out.append("рабочий %d: состояние %d, клип %s, голова на %.2f м, работа %d" % [
			i, _state[i],
			_anim[i].current_animation if _anim[i] != null else "-",
			_head[i].global_position.y if _head[i] != null else -1.0, _job[i]])
		if _state[i] != State.WORKING:
			continue
		var gap := 0.0
		if _bundle[i] != null and _tip[i] != null:
			gap = _bundle[i].global_position.distance_to(_tip[i].global_position)
		var towards: Vector3 = _site.job_facing(_job[i], _seat[i])
		towards.y = 0.0
		out.append(("рабочий %d: руки %.3f м, шнур %s, бухта %d;"
			+ " стоит %.0f°, надо %.0f°, лицом к работе %.2f") % [
			i, gap, _cord[i].visible,
			_bundle[i].get_child_count() if _bundle[i] != null else -1,
			rad_to_deg(_body[i].rotation.y), rad_to_deg(atan2(towards.x, towards.z)),
			(_body[i].global_transform.basis.z.normalized()).dot(towards.normalized())])
	return "
".join(out)


func at_job(job: int) -> int:
	## How many bodies are on this piece of work, which is the only way to see from
	## outside that the second pair of hands turned up.
	var count := 0
	for i in _job.size():
		if _job[i] == job and _state[i] == State.WORKING:
			count += 1
	return count


func busy() -> int:
	var count := 0
	for job in _job:
		if job >= 0:
			count += 1
	return count


func _wear_in(attach: Node3D, what: Node3D) -> void:
	if attach == null:
		return
	for child in attach.get_children():
		child.queue_free()
	if what != null:
		attach.add_child(what)


func _wear(skeleton: Skeleton3D, bone: String, what: Node3D) -> void:
	var attach := _bone(skeleton, bone)
	if attach != null:
		attach.add_child(what)


func _bone(skeleton: Skeleton3D, bone: String) -> BoneAttachment3D:
	if skeleton == null:
		return null
	var attach := BoneAttachment3D.new()
	attach.bone_name = bone
	skeleton.add_child(attach)
	return attach


func _skeleton_of(root: Node) -> Skeleton3D:
	for node in _walk_tree(root):
		if node is Skeleton3D:
			return node
	return null


func _player_of(root: Node) -> AnimationPlayer:
	for node in _walk_tree(root):
		if node is AnimationPlayer:
			return node
	return null


func _walk_tree(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for child in node.get_children():
		out.append_array(_walk_tree(child))
	return out
