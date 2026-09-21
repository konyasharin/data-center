"""Find z-fighting before it ships: coplanar faces that overlap in space.

Two parallel faces less than a fraction of a millimetre apart flicker as the camera
moves, and the effect is invisible in a still Blender preview — it only shows up in
the engine, in motion. This walks every built model and reports the offending pairs
with their world positions, so the fix is a number in a build script rather than a
hunt in the viewport.

	blender -b --factory-startup --python tools/blender/check_coplanar.py
"""

import math
import os
import sys
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy
from mathutils.bvhtree import BVHTree

from dclib.palette import ATLAS, SLOTS

MODELS = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..",
                                      "assets", "models"))
GAP = 0.0012          # faces closer than this along their normal are suspect
# Exactly coincident faces are NOT excluded: two parts ending on the same plane is
# the worst z-fighting there is, and skipping them hid the chassis rear for days.
NORMAL_TOL = 0.02     # dot-product slack for "same direction"
MIN_AREA = 2e-5       # ignore slivers: bevel strips are not what flickers


def _overlap(a, b):
	return all(a[i][0] < b[i][1] - 1e-5 and b[i][0] < a[i][1] - 1e-5 for i in range(3))


def _bounds(verts):
	return [(min(v[i] for v in verts), max(v[i] for v in verts)) for i in range(3)]


def slot_name(mesh, poly):
	"""Which palette entry a face uses, so a report names parts instead of numbers."""
	layer = mesh.uv_layers.active
	if layer is None or poly.material_index > 0:
		return f"mat{poly.material_index}"
	u, v = layer.data[poly.loop_start].uv
	index = int(v * ATLAS) * ATLAS + int(u * ATLAS)
	return SLOTS[index][0] if 0 <= index < len(SLOTS) else "?"


def _exposed(tree, centre, normal):
	"""True when the face can actually be seen: a face buried inside another box
	cannot flicker, and reporting it only hides the ones that can."""
	origin = centre + normal * 1e-4
	hit = tree.ray_cast(origin, normal, 4.0)
	return hit[0] is None


def scan(obj):
	mesh = obj.data
	mesh.calc_loop_triangles()
	tree = BVHTree.FromPolygons([v.co for v in mesh.vertices],
	                            [tuple(p.vertices) for p in mesh.polygons])

	# bucket by quantised normal so only plausible pairs are compared
	buckets = defaultdict(list)
	for poly in mesh.polygons:
		if poly.area < MIN_AREA:
			continue
		n = poly.normal
		if n.length < 0.5:
			continue
		key = (round(n.x / NORMAL_TOL), round(n.y / NORMAL_TOL), round(n.z / NORMAL_TOL))
		verts = [mesh.vertices[i].co for i in poly.vertices]
		d = n.dot(poly.center)
		buckets[key].append((d, _bounds(verts), poly.center.copy(),
		                     slot_name(mesh, poly), n.copy()))

	hits = []
	for faces in buckets.values():
		faces.sort(key=lambda f: f[0])
		for i in range(len(faces)):
			for j in range(i + 1, len(faces)):
				delta = faces[j][0] - faces[i][0]
				if delta > GAP:
					break
				if delta < 1e-7 and faces[i][3] == faces[j][3]:
					continue  # one welded surface: same slot, no separation at all
				if not _overlap(faces[i][1], faces[j][1]):
					continue
				if not (_exposed(tree, faces[i][2], faces[i][4])
				        or _exposed(tree, faces[j][2], faces[j][4])):
					continue
				hits.append((delta, faces[i][2], faces[i][3], faces[j][3]))
	return hits


def main():
	paths = []
	for root, _dirs, files in os.walk(MODELS):
		for name in sorted(files):
			if name.endswith(".glb"):
				paths.append(os.path.join(root, name))

	total = 0
	for path in paths:
		bpy.ops.wm.read_factory_settings(use_empty=True)
		bpy.ops.import_scene.gltf(filepath=path)
		stem = os.path.basename(path)[:-4]
		hits = []
		for obj in bpy.context.scene.objects:
			if obj.type == "MESH":
				hits += scan(obj)
		if not hits:
			continue
		total += len(hits)
		pairs = defaultdict(lambda: [0, 1e9, None])
		for delta, centre, a, b in hits:
			key = tuple(sorted((a, b)))
			entry = pairs[key]
			entry[0] += 1
			if delta < entry[1]:
				entry[1] = delta
				entry[2] = centre
		print(f"{stem}: {len(hits)} coplanar pair(s)")
		for key, (count, delta, centre) in sorted(pairs.items(), key=lambda kv: -kv[1][0]):
			print(f"    {key[0]} / {key[1]}  x{count}  gap {delta * 1000:5.2f} mm at "
			      f"({centre.x:+.3f}, {centre.y:+.3f}, {centre.z:+.3f})")
			spots = sorted({(round(c.x, 2), round(c.y, 2), round(c.z, 2))
			                for _d, c, a, bb in hits if tuple(sorted((a, bb))) == key})
			if len(spots) > 1:
				print("        also " + "  ".join(str(sp) for sp in spots[:5]))

	print(f"\n{total} suspect pairs across {len(paths)} models "
	      f"(threshold {GAP * 1000:.1f} mm)")
	return 0 if total == 0 else 1


if __name__ == "__main__":
	sys.exit(main())
