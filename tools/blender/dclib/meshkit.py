"""Primitive builder. Everything is boxes and cylinders welded into one mesh.

Each primitive is bevelled on creation — the chamfer catching a highlight is what
separates this look from flat low-poly, and it costs one extra face per edge.
"""

import math

import bmesh
import bpy
from mathutils import Euler, Vector

from . import palette, textures

MM_ = 0.001

AXES = {
	"+X": Vector((1, 0, 0)),
	"-X": Vector((-1, 0, 0)),
	"+Y": Vector((0, 1, 0)),
	"-Y": Vector((0, -1, 0)),
	"+Z": Vector((0, 0, 1)),
	"-Z": Vector((0, 0, -1)),
}


class Builder:
	def __init__(self):
		self.bm = bmesh.new()
		self.uv = self.bm.loops.layers.uv.new("UVMap")
		self.deform = None
		self.groups = []
		self.active_group = None
		self.detail_slots = []  # extra materials, in slot order after the atlas

	def part(self, group):
		"""Bind everything built from here on to one bone. Weights live in the bmesh,
		so they survive the merge in finish()."""
		if self.deform is None:
			self.deform = self.bm.verts.layers.deform.new()
		if group not in self.groups:
			self.groups.append(group)
		self.active_group = group
		return self

	def _weigh(self, verts):
		if self.active_group is None:
			return
		index = self.groups.index(self.active_group)
		for v in verts:
			v[self.deform][index] = 1.0

	# --- internals -------------------------------------------------------

	def _snapshot(self):
		return set(self.bm.faces)

	def _fresh(self, before):
		return [f for f in self.bm.faces if f not in before]

	def _paint(self, faces, mat, mat_faces=None):
		matched = set()
		for f in faces:
			name = mat
			if mat_faces:
				n = f.normal
				for key, axis in AXES.items():
					if key in mat_faces and n.dot(axis) > 0.99:
						name = mat_faces[key]
						matched.add(key)
						break
			u, v = palette.uv(name)
			for loop in f.loops:
				loop[self.uv].uv = (u, v)
		if mat_faces:
			missed = set(mat_faces) - matched
			assert not missed, f"mat_faces {sorted(missed)} matched no face (rot applied?)"

	def _place(self, verts, at, rot):
		self._weigh(verts)
		if rot:
			m = Euler([math.radians(a) for a in rot], "XYZ").to_matrix().to_4x4()
			bmesh.ops.transform(self.bm, matrix=m, verts=verts)
		if at != (0, 0, 0):
			bmesh.ops.translate(self.bm, vec=Vector(at), verts=verts)

	# --- primitives ------------------------------------------------------

	def box(self, size, at=(0, 0, 0), mat="steel", mat_faces=None, bevel=0.003,
	        segments=1, rot=None):
		"""Axis-aligned box centred on `at` (before `rot`), size is full extent."""
		assert all(v > 0 for v in size), f"box needs positive extents, got {size}"
		before = self._snapshot()
		cube = bmesh.ops.create_cube(self.bm, size=1.0)
		verts = cube["verts"]
		bmesh.ops.scale(self.bm, vec=Vector(size), verts=verts)

		if bevel > 0:
			limit = min(size) * 0.45
			edges = {e for v in verts for e in v.link_edges}
			bmesh.ops.bevel(
				self.bm, geom=list(verts) + list(edges), offset=min(bevel, limit),
				segments=segments, profile=0.5, affect="EDGES", clamp_overlap=True,
			)

		faces = self._fresh(before)
		self._paint(faces, mat, mat_faces)
		self._place(list({v for f in faces for v in f.verts}), at, rot)
		return faces

	def socket(self, size, at=(0, 0, 0), depth=0.006, wall=0.002, mat="mesh_black",
	           inner="plastic_dark", bevel=0.0, facing=-1):
		"""A connector you can plug something into: a rim standing proud of the panel
		with a recess inside it and a floor at the back.

		Sockets drawn as a solid block are the single thing that most makes hardware
		look unfinished — a cord then ends against a flat face instead of going into
		anything. `size` is the outside of the rim and `at` its centre on the panel
		face.

		`facing` is which way is *out*: -1 for the model's front (-Y, the usual case)
		and +1 for a rear panel. Get it wrong and the rim is built into the body
		instead of out of it — the socket then cannot be seen at all and a cord ends
		against bare panel, which is precisely what it looks like.
		"""
		w, h = size
		t = wall
		sign = -1.0 if facing < 0 else 1.0
		out = []
		for sz, off in (((w, depth, t), (0, 0, (h - t) / 2)),
		                ((w, depth, t), (0, 0, -(h - t) / 2)),
		                ((t, depth, h - 2 * t), ((w - t) / 2, 0, 0)),
		                ((t, depth, h - 2 * t), (-(w - t) / 2, 0, 0))):
			out += self.box(sz, (at[0] + off[0], at[1] + sign * depth / 2, at[2] + off[2]),
			                mat, bevel=bevel)
		# Set in from the panel face. Flush, the floor's front face and the body's own
		# are the same plane and the pair flickers — most visible on the PDU, where the
		# strip's face is exactly there.
		out += self.box((w - 2 * t, 1.5 * MM_, h - 2 * t),
		                (at[0], at[1] - sign * 1.8 * MM_, at[2]), inner, bevel=0.0)
		return out

	def cyl(self, radius, height, at=(0, 0, 0), mat="steel", sides=12, bevel=0.0,
	        rot=None, caps=True):
		before = self._snapshot()
		res = bmesh.ops.create_cone(
			self.bm, cap_ends=caps, cap_tris=False, segments=sides,
			radius1=radius, radius2=radius, depth=height,
		)
		verts = res["verts"]
		if bevel > 0:
			edges = {e for v in verts for e in v.link_edges if len(e.link_faces) == 2
			         and e.calc_face_angle(0.0) > 0.6}
			if edges:
				bmesh.ops.bevel(self.bm, geom=list(edges), offset=bevel, segments=1,
				                profile=0.5, affect="EDGES", clamp_overlap=True)
		faces = self._fresh(before)
		self._paint(faces, mat)
		self._place(list({v for f in faces for v in f.verts}), at, rot)
		return faces

	def cone(self, r_bottom, r_top, height, at=(0, 0, 0), mat="steel", sides=12, rot=None):
		before = self._snapshot()
		bmesh.ops.create_cone(
			self.bm, cap_ends=True, cap_tris=False, segments=sides,
			radius1=r_bottom, radius2=r_top, depth=height,
		)
		faces = self._fresh(before)
		self._paint(faces, mat)
		self._place(list({v for f in faces for v in f.verts}), at, rot)
		return faces

	def sphere(self, radius, at=(0, 0, 0), mat="steel", segments=12, rings=6, scale=(1, 1, 1)):
		before = self._snapshot()
		bmesh.ops.create_uvsphere(
			self.bm, u_segments=segments, v_segments=rings, radius=radius,
		)
		faces = self._fresh(before)
		verts = list({v for f in faces for v in f.verts})
		if scale != (1, 1, 1):
			bmesh.ops.scale(self.bm, vec=Vector(scale), verts=verts)
		self._paint(faces, mat)
		self._place(verts, at, None)
		return faces

	def frame(self, size, thickness, at=(0, 0, 0), mat="steel", axis="Y", bevel=0.002):
		"""Rectangular picture-frame of four bars — door surrounds, panel edges."""
		w, h, d = size
		t = thickness
		out = []
		# Rails run the full width and the uprights overlap into them by 2 mm. Butting
		# the two flush leaves coplanar end faces at all four corners, and they fight
		# for depth; an overlap buries the join where nothing can see it.
		overlap = 2.0 * MM_
		stile = h - 2 * t + 2 * overlap
		if axis == "Y":
			out += self.box((w, d, t), (at[0], at[1], at[2] + h / 2 - t / 2), mat, bevel=bevel)
			out += self.box((w, d, t), (at[0], at[1], at[2] - h / 2 + t / 2), mat, bevel=bevel)
			out += self.box((t, d, stile), (at[0] - w / 2 + t / 2, at[1], at[2]), mat, bevel=bevel)
			out += self.box((t, d, stile), (at[0] + w / 2 - t / 2, at[1], at[2]), mat, bevel=bevel)
		else:
			out += self.box((d, w, t), (at[0], at[1], at[2] + h / 2 - t / 2), mat, bevel=bevel)
			out += self.box((d, w, t), (at[0], at[1], at[2] - h / 2 + t / 2), mat, bevel=bevel)
			out += self.box((d, t, stile), (at[0], at[1] - w / 2 + t / 2, at[2]), mat, bevel=bevel)
			out += self.box((d, t, stile), (at[0], at[1] + w / 2 - t / 2, at[2]), mat, bevel=bevel)
		return out

	def louvres(self, size, at, count, mat="mesh_black", axis="Y", bevel=0.0015):
		"""Slat run standing in for perforation — reads as vents without an alpha map."""
		w, h, d = size
		pitch = h / count
		slat = pitch * 0.55
		out = []
		for i in range(count):
			z = at[2] - h / 2 + pitch * (i + 0.5)
			if axis == "Y":
				out += self.box((w, d, slat), (at[0], at[1], z), mat, bevel=bevel, rot=(18, 0, 0))
			else:
				out += self.box((d, w, slat), (at[0], at[1], z), mat, bevel=bevel, rot=(0, 18, 0))
		return out

	def quad(self, size, at=(0, 0, 0), mat="steel", rot=None, plane="XZ", facing=1):
		"""Flat palette-coloured face. Same shape as detail(), but on the atlas, so it
		survives being drawn through a MultiMesh."""
		axes = {"XZ": (0, 2), "XY": (0, 1), "YZ": (1, 2)}[plane]
		normal_axis = ({0, 1, 2} - set(axes)).pop()
		corners = []
		for su, sv in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
			co = [0.0, 0.0, 0.0]
			co[axes[0]] = su * size[0] / 2
			co[axes[1]] = sv * size[1] / 2
			corners.append(self.bm.verts.new(Vector(co)))
		face = self.bm.faces.new(corners)
		self.bm.normal_update()
		if face.normal[normal_axis] * facing < 0:
			bmesh.ops.reverse_faces(self.bm, faces=[face])
		face.tag = True
		self._paint([face], mat)
		self._place(list(face.verts), at, rot)
		return [face]

	def detail(self, size, at=(0, 0, 0), texture="dc_perforation", tile=0.12,
	           rot=None, plane="XZ", double_sided=False, facing=1):
		"""Flat quad carrying a tiling detail map instead of a palette texel.

		`tile` is metres per texture repeat, either one value or (u, v). `facing` is
		which way along the plane's normal axis the quad looks: Godot culls back faces,
		so a panel pointed into the chassis is simply invisible in the engine even
		though Blender's preview shows it.

		This is a single face on purpose. Built as a box, its *side* faces inherit the
		same planar UVs, which are degenerate across their thickness: the UV
		derivatives explode, the GPU picks a far mip, and each side face lights up
		with the texture's average colour — bright wedges that swap per triangle and
		crawl as the camera moves. A quad has no side faces to get this wrong.
		"""
		if texture not in self.detail_slots:
			self.detail_slots.append(texture)
		slot = self.detail_slots.index(texture) + 1

		axes = {"XZ": (0, 2), "XY": (0, 1), "YZ": (1, 2)}[plane]
		normal_axis = ({0, 1, 2} - set(axes)).pop()
		half = [0.0, 0.0, 0.0]
		half[axes[0]] = size[0] / 2
		half[axes[1]] = size[1] / 2

		corners = []
		for su, sv in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
			co = [0.0, 0.0, 0.0]
			co[axes[0]] = su * half[axes[0]]
			co[axes[1]] = sv * half[axes[1]]
			corners.append(self.bm.verts.new(Vector(co)))

		faces = [self.bm.faces.new(corners)]
		if double_sided:
			flipped = [self.bm.verts.new(v.co) for v in reversed(corners)]
			faces.append(self.bm.faces.new(flipped))

		tile_u, tile_v = tile if isinstance(tile, (tuple, list)) else (tile, tile)
		# anchor UVs to the panel's own corner. Dividing raw local coordinates puts the
		# origin in the middle, which splits the tile across the centre of the panel:
		# the seam then lands in the visible area and mips tear along it
		origin_u = -size[0] / 2
		origin_v = -size[1] / 2
		for f in faces:
			f.material_index = slot
			for loop in f.loops:
				co = loop.vert.co
				loop[self.uv].uv = ((co[axes[0]] - origin_u) / tile_u,
				                    (co[axes[1]] - origin_v) / tile_v)
		self.bm.normal_update()
		if faces[0].normal[normal_axis] * facing < 0:
			bmesh.ops.reverse_faces(self.bm, faces=faces[:1])
		for f in faces:
			f.tag = True

		self._place(list({v for f in faces for v in f.verts}), at, rot)
		return faces

	# --- composition -----------------------------------------------------

	def stamp(self, other, at=(0, 0, 0), rot=None, scale=None):
		"""Weld a copy of another builder's geometry into this one."""
		tmp = bpy.data.meshes.new("_stamp")
		other.bm.to_mesh(tmp)
		before = self._snapshot()
		self.bm.from_mesh(tmp)
		bpy.data.meshes.remove(tmp)
		faces = self._fresh(before)
		verts = list({v for f in faces for v in f.verts})
		if scale:
			bmesh.ops.scale(self.bm, vec=Vector(scale), verts=verts)
		self._place(verts, at, rot)
		return faces

	def repeat(self, other, positions, rot=None):
		out = []
		for p in positions:
			out += self.stamp(other, p, rot)
		return out

	def paint(self, faces, mat):
		self._paint(faces, mat)

	# --- output ----------------------------------------------------------

	def finish(self, name, smooth_angle=35.0, weld=1e-5, collection=None):
		bmesh.ops.remove_doubles(self.bm, verts=list(self.bm.verts), dist=weld)
		# recalc orients faces outward from enclosed volume; a lone quad has no volume,
		# so it gets flipped at random and Godot's back-face culling then hides it —
		# which reads as a missing panel, not as a normals bug
		solids = [f for f in self.bm.faces if not f.tag]
		bmesh.ops.recalc_face_normals(self.bm, faces=solids)

		me = bpy.data.meshes.new(name)
		self.bm.to_mesh(me)
		self.bm.free()
		self.bm = None

		obj = bpy.data.objects.new(name, me)
		(collection or bpy.context.scene.collection).objects.link(obj)
		me.materials.append(palette.build_material())
		for slot in self.detail_slots:
			me.materials.append(textures.build_material(slot))
		for group in self.groups:
			obj.vertex_groups.new(name=group)

		prev = bpy.context.view_layer.objects.active
		bpy.ops.object.select_all(action="DESELECT")
		obj.select_set(True)
		bpy.context.view_layer.objects.active = obj
		bpy.ops.object.shade_smooth_by_angle(angle=math.radians(smooth_angle))
		if prev:
			bpy.context.view_layer.objects.active = prev
		return obj


def tri_count(obj):
	me = obj.data
	return sum(len(p.vertices) - 2 for p in me.polygons)


def clear_scene():
	bpy.ops.wm.read_factory_settings(use_empty=True)
	bpy.context.scene.render.fps = 24
