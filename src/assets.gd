class_name Assets
extends RefCounted

## Loads the built glb library and binds the shared materials.
##
## The glb files carry no textures on purpose (docs/14-art-assets.md): every model
## would otherwise import its own copy of the atlas and lose batching. Here each
## surface is matched to one shared material by the material name Blender wrote.

const MODELS := "res://assets/models/"

const MATERIALS := {
	"dc_atlas": "res://assets/palettes/dc_atlas.tres",
	"dc_perforation": "res://assets/materials/dc_perforation.tres",
	"dc_rail_holes": "res://assets/materials/dc_rail_holes.tres",
	"dc_floor_grille": "res://assets/materials/dc_floor_grille.tres",
	"rack_glass": "res://assets/materials/rack_glass.tres",
	"terminal_screen": "res://assets/materials/terminal_screen.tres",
}

static var _materials: Dictionary = {}
static var _meshes: Dictionary = {}


static func material(name: String) -> Material:
	if not _materials.has(name):
		_materials[name] = load(MATERIALS.get(name, MATERIALS["dc_atlas"]))
	return _materials[name]


static func mesh(path: String) -> Mesh:
	## `path` is relative to assets/models, without the extension: "hardware/server_1u".
	if _meshes.has(path):
		return _meshes[path]
	var packed: PackedScene = load(MODELS + path + ".glb")
	var root: Node = packed.instantiate()
	var found: Mesh = null
	for node in _walk(root):
		if node is MeshInstance3D:
			found = node.mesh
			break
	if found != null:
		_bind(found)
	_meshes[path] = found
	root.queue_free()
	return found


static func instance(path: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh(path)
	return mi


static func scene(path: String) -> Node3D:
	## Full node tree — used for the rigged worker, which needs its AnimationPlayer.
	var packed: PackedScene = load(MODELS + path + ".glb")
	var root: Node3D = packed.instantiate()
	for node in _walk(root):
		if node is MeshInstance3D and node.mesh != null:
			_bind(node.mesh)
	return root


static func _bind(m: Mesh) -> void:
	for i in m.get_surface_count():
		var existing := m.surface_get_material(i)
		var key := existing.resource_name if existing != null else ""
		if key.is_empty():
			key = "dc_atlas"
		m.surface_set_material(i, material(key))


static func _walk(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for child in node.get_children():
		out.append_array(_walk(child))
	return out
