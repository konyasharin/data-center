extends SceneTree

# Engine-side half of the asset contract: the glb files carry what the game expects.
#   godot --headless --script res://tools/godot/check_assets.gd

const WORKER := "res://assets/models/characters/worker.glb"
const MANIFEST := "res://assets/models/characters/worker.clips.json"
const MATERIAL := "res://assets/palettes/dc_atlas.tres"
const EXPECTED_CLIPS := [
	"idle", "idle_look", "walk", "run", "carry_idle", "carry_walk",
	"work_stand", "crouch_down", "work_crouch", "tag_hang", "type", "push_cart",
]

var failures: Array[String] = []

func _initialize() -> void:
	_check_material()
	_check_worker()
	_check_manifest()
	_check_models()

	if failures.is_empty():
		print("\nasset contract OK")
	else:
		print("\nFAILURES")
		for f in failures:
			print(" - ", f)
	quit(0 if failures.is_empty() else 1)

func _check_material() -> void:
	var mat := load(MATERIAL)
	if mat is not StandardMaterial3D:
		failures.append("%s did not load as StandardMaterial3D" % MATERIAL)
		return
	for field in ["albedo_texture", "metallic_texture", "roughness_texture", "emission_texture"]:
		if mat.get(field) == null:
			failures.append("dc_atlas.tres: %s is empty" % field)
	# a filtered atlas blends neighbouring texels into every face
	if mat.texture_filter != BaseMaterial3D.TEXTURE_FILTER_NEAREST:
		failures.append("dc_atlas.tres: texture_filter is %d, expected Nearest"
			% mat.texture_filter)
	print("material: dc_atlas.tres loaded, filter=%d" % mat.texture_filter)

func _check_worker() -> void:
	var packed := load(WORKER)
	if packed == null:
		failures.append("cannot load %s" % WORKER)
		return
	var root: Node = packed.instantiate()
	var player: AnimationPlayer = null
	var skeleton: Skeleton3D = null
	for node in _walk(root):
		if node is AnimationPlayer:
			player = node
		elif node is Skeleton3D:
			skeleton = node

	if player == null:
		failures.append("worker.glb has no AnimationPlayer")
	else:
		var names := Array(player.get_animation_list())
		print("worker: %d clips, %d bones" % [names.size(),
			skeleton.get_bone_count() if skeleton else 0])
		for clip in EXPECTED_CLIPS:
			if not names.has(clip):
				failures.append("worker.glb is missing clip '%s'" % clip)
		for clip in names:
			var anim := player.get_animation(clip)
			if anim.length <= 0.0:
				failures.append("clip '%s' has zero length" % clip)

	if skeleton == null:
		failures.append("worker.glb has no Skeleton3D")
	elif skeleton.find_bone("Hips") < 0 or skeleton.find_bone("LeftHand") < 0:
		failures.append("worker.glb skeleton is not the expected Mixamo-style rig")
	root.free()

func _check_manifest() -> void:
	var text := FileAccess.get_file_as_string(MANIFEST)
	if text.is_empty():
		failures.append("cannot read %s" % MANIFEST)
		return
	var data: Variant = JSON.parse_string(text)
	if data == null or not data.has("clips"):
		failures.append("%s is not a clip manifest" % MANIFEST)
		return
	for clip in EXPECTED_CLIPS:
		if not data["clips"].has(clip):
			failures.append("manifest is missing clip '%s'" % clip)
	print("manifest: %d clips at %d fps" % [data["clips"].size(), data["fps"]])


func _check_models() -> void:
	var count := 0
	var surfaces := 0
	for path in _glb_paths("res://assets/models"):
		var packed := load(path)
		if packed == null:
			failures.append("cannot load %s" % path)
			continue
		var root: Node = packed.instantiate()
		for node in _walk(root):
			if node is MeshInstance3D and node.mesh != null:
				surfaces += node.mesh.get_surface_count()
				if node.mesh.get_surface_count() > 1:
					failures.append("%s: %d surfaces, batching expects one" %
						[path.get_file(), node.mesh.get_surface_count()])
		root.free()
		count += 1
	print("models: %d files, %d surfaces total" % [count, surfaces])

func _glb_paths(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		failures.append("cannot open %s" % dir_path)
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			out.append_array(_glb_paths(full))
		elif entry.ends_with(".glb"):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return out

func _walk(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for child in node.get_children():
		out.append_array(_walk(child))
	return out
