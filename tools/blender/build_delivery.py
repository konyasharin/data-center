"""What arrives on the plot: a lorry, and the crate a cabinet comes in.

A rack is not carried in assembled — it is delivered flat, in a crate, on a pallet.
The crate is two objects because its lid has to open: the body stays where it was
set down and the lid swings on its back edge, so Godot rotates one node and nothing
else moves.

The parts are the cabinet taken apart into what a person can carry: the base frame,
the two sides, the rails, the doors. They exist so the player can put one together
in the order a real one goes together, which is the only order that works.

Run: blender -b --factory-startup --python tools/blender/build_delivery.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy

from dclib import exporter
from dclib.meshkit import Builder, clear_scene
from dclib.units import MM

CRATE_W = 0.86
CRATE_D = 1.32
CRATE_H = 2.14
PLANK = 22 * MM


def _planked(b, size, at, mat="wood", gap=0.10):
	"""A face made of boards with a shadow line between them, which is what tells a
	crate from a painted box at any distance."""
	w, h = size
	rows = max(2, int(h / gap))
	step = h / rows
	for i in range(rows):
		b.box((w, PLANK, step * 0.88), (at[0], at[1], at[2] - h / 2 + step * (i + 0.5)),
		      mat, bevel=2 * MM)


def make_crate_body():
	"""Origin on the floor at the middle of the crate; the lid hinges at its back."""
	b = Builder()
	for sx in (-1, 1):
		b.box((PLANK * 2, CRATE_D, CRATE_H), (sx * (CRATE_W / 2 - PLANK), 0, CRATE_H / 2),
		      "wood", bevel=3 * MM)
	# back only: the front is a separate panel, because a crate is opened from the
	# front and a lid on top is opened by somebody standing on a ladder
	_planked(b, (CRATE_W - PLANK * 2, CRATE_H), (0, CRATE_D / 2 - PLANK, CRATE_H / 2))
	b.box((CRATE_W + 0.04, PLANK * 2, 90 * MM), (0, 0, CRATE_H - 0.045), "wood",
	      bevel=3 * MM)
	# the pallet it stands on, and the corner braces
	b.box((CRATE_W + 0.06, CRATE_D + 0.06, 0.14), (0, 0, 0.07), "wood", bevel=4 * MM)
	for sx in (-1, 1):
		for sy in (-1, 1):
			b.box((60 * MM, 60 * MM, CRATE_H), (sx * (CRATE_W / 2 - 30 * MM),
			      sy * (CRATE_D / 2 - 30 * MM), CRATE_H / 2), "wood", bevel=3 * MM)
	return b.finish("crate_body")


def make_crate_lid():
	"""The front panel. Origin on its left edge, on the floor, so the door swings about
	a vertical hinge and nothing else in the crate moves with it."""
	b = Builder()
	w = CRATE_W - PLANK * 2
	rows = int(CRATE_H / 0.12)
	step = CRATE_H / rows
	for i in range(rows):
		b.box((w, PLANK, step * 0.88), (w / 2, 0, step * (i + 0.5)), "wood", bevel=2 * MM)
	for z in (0.16, CRATE_H - 0.16):
		b.box((w, PLANK * 1.6, 70 * MM), (w / 2, -PLANK * 0.4, z), "wood", bevel=2 * MM)
	b.box((60 * MM, 40 * MM, 0.16), (w - 70 * MM, -PLANK * 1.2, CRATE_H * 0.5),
	      "steel_dark", bevel=3 * MM)
	b.box((0.34, 4 * MM, 0.22), (w / 2, -PLANK * 0.8, CRATE_H * 0.66), "label",
	      bevel=1 * MM)
	return b.finish("crate_lid")


def make_lorry():
	"""A flatbed with a box body. Never driven and never entered — it stops at the
	gate, the crate comes off the back, and it leaves again."""
	b = Builder()
	w, wheel, clear = 2.3, 0.44, 0.42
	# chassis and bed
	b.box((w, 6.6, 0.22), (0, 0, clear + 0.11), "steel_dark", bevel=8 * MM)
	# box body
	body_l = 4.2
	b.box((w, body_l, 2.3), (0, -0.9, clear + 0.22 + 1.15), "plastic_white", bevel=12 * MM,
	      mat_faces={"-Y": "plastic_grey"})
	b.box((w + 0.06, 0.10, 2.34), (0, -0.9 - body_l / 2, clear + 0.22 + 1.15),
	      "steel_light", bevel=8 * MM)
	# cab
	b.box((w - 0.1, 2.0, 1.9), (0, 2.5, clear + 0.22 + 0.95), "paint_blue", bevel=20 * MM)
	b.box((w - 0.4, 0.12, 0.8), (0, 2.5 + 1.0, clear + 0.22 + 1.45), "glass", bevel=8 * MM)
	for sx in (-1, 1):
		b.box((0.12, 1.2, 0.7), (sx * (w / 2 - 0.06), 2.5, clear + 0.22 + 1.4), "glass",
		      bevel=6 * MM)
		b.box((0.16, 0.3, 0.3), (sx * (w / 2 + 0.06), 3.3, clear + 0.22 + 1.5),
		      "plastic_dark", bevel=5 * MM)
	b.box((w - 0.2, 0.3, 0.45), (0, 3.55, clear + 0.4), "steel_dark", bevel=8 * MM)
	# wheels
	for sy in (3.0, -0.4, -1.6):
		for sx in (-1, 1):
			b.cyl(wheel, 0.30, (sx * (w / 2 - 0.12), sy, wheel), "rubber", sides=16,
			      rot=(0, 90, 0))
	return b.finish("lorry")


def part(name, build):
	b = Builder()
	build(b)
	return b.finish(name)


def make_parts():
	"""The cabinet in the pieces one person can carry, in the order it goes together."""
	w, d, h = 0.6, 1.07, 1.96

	def base(b):
		b.box((w, d, 0.09), (0, 0, 0.045), "rack_black", bevel=4 * MM)
		for sx in (-1, 1):
			for sy in (-1, 1):
				b.box((70 * MM, 70 * MM, 0.12), (sx * (w / 2 - 40 * MM),
				      sy * (d / 2 - 40 * MM), 0.06), "steel_dark", bevel=3 * MM)

	def upright(b):
		b.box((60 * MM, 60 * MM, h), (0, 0, h / 2), "rack_black", bevel=4 * MM)
		b.detail((50 * MM, h - 0.1), (0, -32 * MM, h / 2), texture="dc_rail_holes",
		         tile=(0.05, U_PITCH * 3), plane="XZ")

	def side(b):
		b.box((0.02, d - 0.06, h - 0.1), (0, 0, (h - 0.1) / 2), "steel", bevel=3 * MM)
		for sy in (-1, 1):
			b.box((40 * MM, 40 * MM, h - 0.1), (0, sy * (d / 2 - 60 * MM), (h - 0.1) / 2),
			      "steel_dark", bevel=3 * MM)

	return [part("rack_part_base", base), part("rack_part_upright", upright),
	        part("rack_part_side", side)]


U_PITCH = 0.04445


def main():
	clear_scene()
	exporter.setup_studio()
	build = exporter.Build()

	body = build.emit(make_crate_body(), "delivery")
	lid = build.emit(make_crate_lid(), "delivery")
	lorry = build.emit(make_lorry(), "delivery")
	parts = [build.emit(p, "delivery") for p in make_parts()]

	build.report()

	lid.location = (-(CRATE_W - PLANK * 2) / 2, -CRATE_D / 2 + PLANK, 0)
	exporter.contact_sheet([body, lid],
	                       os.path.join(exporter.PREVIEWS, "crate.png"),
	                       views=(("front", 3.0, 10), ("three_q", 2.6, 26)))
	exporter.render_preview([lorry], os.path.join(exporter.PREVIEWS, "lorry.png"),
	                        angle=62, elevation=18, resolution=(1200, 620))
	x = 0.0
	for obj in parts:
		obj.location = (x, 0, 0)
		x += 1.0
	exporter.render_preview(parts, os.path.join(exporter.PREVIEWS, "rack_parts.png"),
	                        angle=58, elevation=18, resolution=(1200, 620))


if __name__ == "__main__":
	main()
