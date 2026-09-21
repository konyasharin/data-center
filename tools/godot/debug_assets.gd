extends SceneTree

func _initialize() -> void:
	for path in ["hardware/rack_42u_frame", "room/floor_tile_solid", "characters/worker"]:
		var packed: PackedScene = load("res://assets/models/" + path + ".glb")
		if packed == null:
			print(path, ": FAILED TO LOAD")
			continue
		var root: Node = packed.instantiate()
		print("--- ", path, " root=", root.get_class())
		_dump(root, 1)
		root.free()

	var mat := load("res://assets/palettes/dc_atlas.tres")
	print("material: ", mat, " albedo=", mat.albedo_texture, " filter=", mat.texture_filter)
	var tex: Texture2D = mat.albedo_texture
	var img := tex.get_image()
	print("atlas size: ", img.get_size(), " fmt=", img.get_format(), " mips=", img.has_mipmaps())
	print("texel(0,15) steel_dark = ", img.get_pixel(0, 15))
	print("texel(5,13) skin?      = ", img.get_pixel(5, 13))
	quit(0)

func _dump(node: Node, depth: int) -> void:
	var pad := "  ".repeat(depth)
	if node is MeshInstance3D:
		var m: Mesh = node.mesh
		var names := []
		for i in m.get_surface_count():
			var sm := m.surface_get_material(i)
			names.append(sm.resource_name if sm != null else "<null>")
		print(pad, node.name, " MeshInstance3D surfaces=", m.get_surface_count(),
			" mats=", names, " aabb=", m.get_aabb().size)
	else:
		print(pad, node.name, " ", node.get_class())
	for c in node.get_children():
		_dump(c, depth + 1)
