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

enum State { IDLE, WALKING, WORKING }

var _estate: EstateBridge
var _site: Object
var _body: Array[Node3D] = []
var _anim: Array[AnimationPlayer] = []
var _hand: Array[Node3D] = []      # what is in the right hand, hidden unless in use
var _route: Array[PackedVector3Array] = []
var _goal := PackedVector3Array()
var _stale := PackedFloat32Array()   # seconds since the route was last asked for
var _state := PackedInt32Array()
var _job := PackedInt32Array()
var _seat := PackedInt32Array()    # which side of the work this one stands on
var _owns := []                    # true if this worker is the one advancing the job
var _home := PackedVector3Array()


func setup(estate: EstateBridge, site: Object, posts: Array) -> void:
	_estate = estate
	_site = site
	for at in posts:
		var worker: Node3D = Assets.scene("characters/worker")
		worker.position = at
		add_child(worker)
		var skeleton := _skeleton_of(worker)
		_wear_helmet(skeleton)

		_body.append(worker)
		_anim.append(_player_of(worker))
		_hand.append(_hold_point(skeleton))
		_route.append(PackedVector3Array())
		_goal.append(at)
		_stale.append(0.0)
		_state.append(State.IDLE)
		_job.append(-1)
		_seat.append(0)
		_owns.append(false)
		_home.append(at)
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


func _look_for_work(i: int) -> void:
	var job: int = _estate.Claim(i)
	if job >= 0:
		_take(i, job, true)
		return
	# Some work wants two people. The second is not a second claim — the queue hands a
	# job to one worker — but standing there watching while someone wrestles a cabinet
	# alone is worse than the simplification.
	var helping := _job_needing_a_hand(i)
	if helping >= 0:
		_take(i, helping, false)
		return
	if _body[i].position.distance_to(_home[i]) > ARRIVED:
		_job[i] = -1
		_owns[i] = false
		_head_for(i, _home[i])


func _job_needing_a_hand(i: int) -> int:
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


func _head_for(i: int, to: Vector3) -> void:
	_goal[i] = to
	_stale[i] = 0.0
	_route[i] = _path(_body[i].position, to)
	_state[i] = State.WALKING
	_play(i, "walk")


func _path(from: Vector3, to: Vector3) -> PackedVector3Array:
	## Around the furniture rather than through it. A map that has not finished its
	## first sync, or a point off the mesh, gives an empty path — walking straight at
	## the target is then still better than standing still, and it is what the crew
	## did before there was a map at all.
	var map := get_world_3d().navigation_map
	# Asking before the map has finished building is an error, not an empty answer,
	# and the route is asked for again every second anyway.
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return PackedVector3Array([to])
	var found := NavigationServer3D.map_get_path(map, from, to, true)
	if found.size() < 2:
		return PackedVector3Array([to])
	# the last corner is the closest point on the mesh, which is not the same as the
	# spot in front of the rack the site asked for
	found[found.size() - 1] = to
	return found


func _walk(i: int, delta: float) -> void:
	var body := _body[i]
	# Asked for again now and then. The map finishes building at the end of a physics
	# frame, so the very first walk of a session is planned against nothing, and a
	# cabinet raised in the meantime is not in the route that was planned before it.
	_stale[i] += delta
	if _stale[i] > 0.7:
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


func _arrive(i: int) -> void:
	if _job[i] < 0:
		_state[i] = State.IDLE
		_play(i, "idle")
		return
	_state[i] = State.WORKING
	_play(i, _site.job_clip(_job[i]))
	_show_prop(i, _site.job_prop(_job[i]))
	if _owns[i]:
		_site.job_started(_job[i])


func _work(i: int, delta: float) -> void:
	# Facing the work while doing it, because the clips are authored looking forwards
	# and a technician with their back to the cabinet reads as a bug.
	_face(i, _site.job_facing(_job[i]), delta)
	if not _owns[i]:
		# the helper stops when the job does, which it notices rather than is told
		if _estate.JobStateOf(_job[i]) == 2:
			_finish(i)
		return
	if not _estate.Advance(_job[i], delta):
		return
	_site.job_done(_job[i])
	_finish(i)


func _finish(i: int) -> void:
	_job[i] = -1
	_owns[i] = false
	_show_prop(i, "")
	_state[i] = State.IDLE
	_play(i, "idle")


func _face(i: int, towards: Vector3, delta: float) -> void:
	towards.y = 0.0
	if towards.length_squared() < 0.0001:
		return
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


func _show_prop(i: int, path: String) -> void:
	var hand := _hand[i]
	if hand == null:
		return
	for child in hand.get_children():
		child.queue_free()
	if path.is_empty():
		return
	var prop := Assets.instance(path)
	prop.scale = Vector3(0.6, 0.6, 0.6)
	prop.position = Vector3(0.0, 0.03, 0.0)
	hand.add_child(prop)


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


func _hold_point(skeleton: Skeleton3D) -> Node3D:
	if skeleton == null:
		return null
	var attach := BoneAttachment3D.new()
	attach.bone_name = "RightHand"
	skeleton.add_child(attach)
	return attach


func _wear_helmet(skeleton: Skeleton3D) -> void:
	if skeleton == null:
		return
	var attach := BoneAttachment3D.new()
	attach.bone_name = "Head"
	skeleton.add_child(attach)
	attach.add_child(Assets.instance("characters/helmet"))


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
