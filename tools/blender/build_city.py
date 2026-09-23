"""The world outside the fence: what the plot is, and what is beyond it.

Everything here is scenery. The city blocks are never entered and never lit from
inside, so they are shells with a window pattern and nothing else — the point is a
skyline that reads as a city from the one place the player can stand, not buildings.
The fence is what actually stops them walking into it.

Run: blender -b --factory-startup --python tools/blender/build_city.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy

from dclib import exporter
from dclib.meshkit import Builder, clear_scene
from dclib.units import MM

FENCE_W = 2.4
FENCE_H = 2.0
POST = 60 * MM


def make_fence_panel():
	"""One bay of mesh fence, origin at the bottom of its left post."""
	b = Builder()
	for x in (0.0, FENCE_W):
		b.box((POST, POST, FENCE_H), (x, 0, FENCE_H / 2), "steel_dark", bevel=3 * MM)
	# rails top and bottom, and the mesh between them as one alpha-mapped quad: the
	# wire of a real fence is thousands of triangles and reads as a grey haze anyway
	for z in (0.12, FENCE_H - 0.10):
		b.box((FENCE_W, 30 * MM, 40 * MM), (FENCE_W / 2, 0, z), "steel_dark",
		      bevel=2 * MM)
	b.detail((FENCE_W - POST, FENCE_H - 0.30), (FENCE_W / 2, 0, FENCE_H / 2 + 0.01),
	         texture="dc_fence_mesh", tile=0.30, plane="XZ", double_sided=True)
	return b.finish("fence_panel")


def make_fence_gate():
	"""A wider bay with a sliding leaf, shut. The plot is closed; this says why."""
	b = Builder()
	width = 3.6
	for x in (0.0, width):
		b.box((90 * MM, 90 * MM, FENCE_H + 0.2), (x, 0, (FENCE_H + 0.2) / 2),
		      "steel_dark", bevel=4 * MM)
	b.box((width, 50 * MM, 80 * MM), (width / 2, 0, FENCE_H - 0.06), "steel", bevel=3 * MM)
	b.box((width, 50 * MM, 60 * MM), (width / 2, 0, 0.10), "steel", bevel=3 * MM)
	b.detail((width - 0.1, FENCE_H - 0.26), (width / 2, 0, FENCE_H / 2 + 0.01),
	         texture="dc_fence_mesh", tile=0.30, plane="XZ", double_sided=True)
	for x in (width * 0.34, width * 0.66):
		b.box((60 * MM, 40 * MM, FENCE_H - 0.26), (x, 0, FENCE_H / 2 + 0.01), "steel",
		      bevel=2 * MM)
	return b.finish("fence_gate")


def block(name, size, floors, base="wall_panel", crown=None):
	"""A city building: a shell, a band of windows per floor, a parapet.

	The window strip is a detail quad rather than geometry for the same reason the
	fence mesh is: from the only place these are ever seen — across a fence, a street
	away — a lit strip and a hundred modelled frames are the same picture.
	"""
	w, d, h = size
	b = Builder()
	b.box((w, d, h), (0, 0, h / 2), base, bevel=20 * MM)
	b.box((w + 0.12, d + 0.12, 0.35), (0, 0, h + 0.1), crown or "concrete_dark",
	      bevel=20 * MM)
	step = h / floors
	for i in range(floors):
		z = step * (i + 0.55)
		if z > h - 0.5:
			break
		for sy, depth in ((-1, d / 2), (1, d / 2)):
			b.detail((w - 0.9, step * 0.45), (0, sy * (depth + 0.01), z),
			         texture="dc_windows", tile=(2.2, step * 0.45), plane="XZ",
			         facing=int(sy))
		for sx in (-1, 1):
			b.detail((d - 0.9, step * 0.45), (sx * (w / 2 + 0.01), 0, z),
			         texture="dc_windows", tile=(2.2, step * 0.45), plane="YZ",
			         facing=int(sx))
	# a plinth, so it does not look like a box dropped on the ground
	b.box((w + 0.25, d + 0.25, 0.5), (0, 0, 0.25), "concrete_dark", bevel=20 * MM)
	return b.finish(name)


def make_kiosk():
	"""Street furniture: the one thing near the fence that is at human scale, so the
	buildings behind it have something to be measured against."""
	b = Builder()
	w, d, h = 2.2, 1.6, 2.6
	b.box((w, d, h), (0, 0, h / 2), "wall_panel_dark", bevel=10 * MM)
	b.box((w + 0.2, d + 0.2, 0.22), (0, 0, h + 0.05), "roof_metal", bevel=10 * MM)
	b.box((w - 0.5, 60 * MM, 1.0), (0, -d / 2 - 0.02, 1.5), "glass", bevel=5 * MM)
	b.box((w - 0.6, 40 * MM, 0.3), (0, -d / 2 - 0.05, 2.25), "paint_blue", bevel=5 * MM)
	return b.finish("kiosk")


def main():
	clear_scene()
	exporter.setup_studio()
	build = exporter.Build()

	def emit(obj, folder="city"):
		return build.emit(obj, folder)

	panel = emit(make_fence_panel())
	gate = emit(make_fence_gate())
	tower = emit(block("city_tower", (9.0, 9.0, 26.0), 8))
	slab = emit(block("city_slab", (16.0, 11.0, 14.0), 5, base="wall_panel_dark"))
	low = emit(block("city_low", (12.0, 9.0, 7.0), 2, base="concrete"))
	kiosk = emit(make_kiosk())

	build.report()

	panel.location = (-6.0, 0, 0)
	gate.location = (-1.8, 0, 0)
	kiosk.location = (4.0, 0, 0)
	exporter.contact_sheet([panel, gate, kiosk],
	                       os.path.join(exporter.PREVIEWS, "city_street.png"),
	                       views=(("front", 16, 8), ("three_q", 14, 22)))
	tower.location = (-14.0, 0, 0)
	slab.location = (4.0, 0, 0)
	low.location = (22.0, 0, 0)
	exporter.render_preview([tower, slab, low],
	                        os.path.join(exporter.PREVIEWS, "city_blocks.png"),
	                        angle=62, elevation=16, resolution=(1400, 700))


if __name__ == "__main__":
	main()
