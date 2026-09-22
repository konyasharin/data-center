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
## queue, walks to where the site says the work is, plays the right animation for as
## long as the core says the work takes, and hands the job back when it is done.

const WALK := 1.25            # m/s, the speed the walk clip is authored at
const ARRIVED := 0.45
const TURN := 6.0

enum State { IDLE, WALKING, WORKING }

var _estate: EstateBridge
var _site: Object
var _body: Array[Node3D] = []
var _anim: Array[AnimationPlayer] = []
var _state := PackedInt32Array()
var _job := PackedInt32Array()
var _target := PackedVector3Array()
var _home := PackedVector3Array()


func setup(estate: EstateBridge, site: Object, posts: Array) -> void:
	_estate = estate
	_site = site
	for at in posts:
		var worker: Node3D = Assets.scene("characters/worker")
		worker.position = at
		add_child(worker)
		_wear_helmet(worker)

		_body.append(worker)
		_anim.append(_player_of(worker))
		_state.append(State.IDLE)
		_job.append(-1)
		_target.append(at)
		_home.append(at)
		_play(_body.size() - 1, "idle")


func _process(delta: float) -> void:
	if _estate == null:
		return
	for i in _body.size():
		match _state[i]:
			State.IDLE:
				_look_for_work(i, delta)
			State.WALKING:
				_walk(i, delta)
			State.WORKING:
				_work(i, delta)


func _look_for_work(i: int, delta: float) -> void:
	var job: int = _estate.Claim(i)
	if job < 0:
		# nothing to do: drift back to where they were standing, so the shed does not
		# slowly fill with people stopped wherever their last job was
		if _body[i].position.distance_to(_home[i]) > ARRIVED:
			_target[i] = _home[i]
			_state[i] = State.WALKING
			_play(i, "walk")
		return
	_job[i] = job
	_target[i] = _site.job_site(job)
	_state[i] = State.WALKING
	_play(i, "walk")


func _walk(i: int, delta: float) -> void:
	var body := _body[i]
	var flat := _target[i]
	flat.y = body.position.y
	var step := flat - body.position
	if step.length() < ARRIVED:
		if _job[i] < 0:
			_state[i] = State.IDLE
			_play(i, "idle")
			return
		_state[i] = State.WORKING
		_play(i, "work_stand")
		return
	body.position += step.normalized() * WALK * delta
	_face(i, step, delta)


func _work(i: int, delta: float) -> void:
	# Facing the rack while working, because the animation is authored looking
	# forwards and a technician with their back to the cabinet reads as a bug.
	_face(i, _site.job_facing(_job[i]), delta)
	if not _estate.Advance(_job[i], delta):
		return
	_site.job_done(_job[i])
	_job[i] = -1
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


func busy() -> int:
	var count := 0
	for job in _job:
		if job >= 0:
			count += 1
	return count


func _wear_helmet(worker: Node3D) -> void:
	var skeleton := _skeleton_of(worker)
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
