class_name Outline
extends MeshInstance3D

## The edges of a box, drawn over everything, for "this is the thing you are pointing
## at". Used by anything that can be picked up — a chassis in a rack, a part in a
## crate — so the two never drift into looking like different kinds of highlight.
##
## Lines rather than a filled shape: a solid overlay hides the thing being pointed
## at, which is the one thing the highlight must not do. Godot draws a line one pixel
## wide whatever is asked for, and at this size that is exactly the thin outline
## wanted.

const WARM := Color(0.98, 0.78, 0.22)
const COOL := Color(0.40, 0.86, 0.58)


static func make(colour: Color) -> Outline:
	var node := Outline.new()
	node.mesh = _box()
	node.material_override = glow(colour)
	node.visible = false
	return node


func show_at(where: Transform3D, colour: Color) -> void:
	global_transform = where
	material_override = glow(colour)
	visible = true


static func glow(colour: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Through everything, because everything is in the way: a cabinet door, a crate
	# wall, the cords. A depth-tested outline is invisible exactly when it is needed.
	mat.no_depth_test = true
	mat.render_priority = 8
	return mat


static func _box() -> ArrayMesh:
	var corners := PackedVector3Array()
	for i in 8:
		corners.append(Vector3(
			-0.5 + float(i & 1), -0.5 + float((i >> 1) & 1), -0.5 + float((i >> 2) & 1)))
	var lines := PackedVector3Array()
	for a in 8:
		for b in range(a + 1, 8):
			# neighbours on the cube differ in exactly one coordinate
			if (a ^ b) in [1, 2, 4]:
				lines.append(corners[a])
				lines.append(corners[b])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = lines
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return mesh
