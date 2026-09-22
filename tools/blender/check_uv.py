"""Which palette slot a primitive's faces actually land on.

Every surface in the library is coloured by pointing its UVs at one texel of the
16x16 atlas, so a wrong colour is never a material problem — it is a UV pointing
at the wrong texel. Reading that back is the only way to tell "this slot is the
wrong choice" from "this face never got the slot it was given".

Run: blender -b --factory-startup --python tools/blender/check_uv.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from dclib import palette
from dclib.meshkit import Builder, clear_scene

ATLAS = palette.ATLAS


def slot_at(u, v):
	col = int(u * ATLAS)
	row = int(v * ATLAS)
	i = row * ATLAS + col
	if 0 <= i < len(palette.SLOTS):
		return palette.SLOTS[i][0]
	return f"<off atlas {col},{row}>"


def report(name, obj, expect):
	mesh = obj.data
	uv = mesh.uv_layers.active.data
	seen = {}
	for poly in mesh.polygons:
		for loop in poly.loop_indices:
			u, v = uv[loop].uv
			seen.setdefault(slot_at(u, v), 0)
			seen[slot_at(u, v)] += 1
	print(f"\n{name}: {mesh.polygons:} faces" if False else f"\n{name}")
	for slot, count in sorted(seen.items(), key=lambda kv: -kv[1]):
		mark = "  <- expected" if slot in expect else ""
		print(f"   {count:5d} loops  {slot}{mark}")


def main():
	clear_scene()

	b = Builder()
	b.socket((17 * 0.001, 12 * 0.001), (0, -0.001, 0), depth=0.007, wall=0.0018)
	report("socket(front facing)", b.finish("probe_socket"),
	       {"mesh_black", "plastic_dark"})

	b = Builder()
	b.socket((13 * 0.001, 0.011), (0, 0.75, 0), depth=0.006, wall=0.0015, facing=1)
	report("socket(rear facing)", b.finish("probe_socket_rear"),
	       {"mesh_black", "plastic_dark"})

	b = Builder()
	b.box((0.05, 0.05, 0.05), (0, 0, 0), "mesh_black")
	report("plain box, mesh_black", b.finish("probe_box"), {"mesh_black"})


main()
