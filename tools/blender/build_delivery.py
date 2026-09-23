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

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy

from dclib import exporter
from dclib.meshkit import Builder, clear_scene
from dclib.units import MM



BODY_L = 4.2
BODY_W = 2.3
BODY_H = 2.3
BED = 0.64          # top of the bed above the ground: chassis clearance plus its deck


def make_lorry():
	"""A box lorry, open at the back and hollow, because the load is taken out of it by
	hand. The rear door is its own object so it can be swung up on its top edge.

	Never driven: it slides along a path and the wheels do not turn. At the speed it
	moves and the distance it is seen from, what reads as driving is the easing."""
	b = Builder()
	w, wheel, clear = BODY_W, 0.44, 0.42
	# chassis and bed
	b.box((w, 6.6, 0.22), (0, 0, clear + 0.11), "steel_dark", bevel=8 * MM)
	# the body as walls round an empty space: floor, roof, two sides and the front
	body_l = BODY_L
	back = -0.9 - body_l / 2
	b.box((w, body_l, 60 * MM), (0, -0.9, BED), "plastic_grey", bevel=6 * MM)
	b.box((w, body_l, 80 * MM), (0, -0.9, BED + BODY_H), "plastic_white", bevel=8 * MM)
	for sx in (-1, 1):
		b.box((70 * MM, body_l, BODY_H), (sx * (w / 2 - 35 * MM), -0.9,
		      BED + BODY_H / 2), "plastic_white", bevel=8 * MM)
	b.box((w, 80 * MM, BODY_H), (0, -0.9 + body_l / 2, BED + BODY_H / 2),
	      "plastic_white", bevel=8 * MM)
	b.box((w + 0.06, 0.10, 0.12), (0, back, BED + BODY_H + 0.02), "steel_light",
	      bevel=6 * MM)
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


def make_lorry_door():
	"""The rear door, hinged along its top edge so it swings up and out of the way.
	Origin on that hinge, in the lorry's own space, so Godot parents it to the lorry
	and turns one number."""
	b = Builder()
	b.box((BODY_W + 0.04, 60 * MM, 0.10), (0, 0, 0), "steel_light", bevel=5 * MM)
	rows = 7
	step = BODY_H / rows
	for i in range(rows):
		b.box((BODY_W - 0.02, 40 * MM, step * 0.9), (0, 0, -step * (i + 0.5)),
		      "plastic_white", bevel=4 * MM)
	for sx in (-1, 1):
		b.box((60 * MM, 60 * MM, BODY_H), (sx * (BODY_W / 2 - 60 * MM), -20 * MM,
		      -BODY_H / 2), "plastic_grey", bevel=4 * MM)
	b.box((0.26, 80 * MM, 90 * MM), (0, -40 * MM, -BODY_H + 0.35), "steel_dark",
	      bevel=5 * MM)
	return b.finish("lorry_door")


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

	lorry = build.emit(make_lorry(), "delivery")
	door = build.emit(make_lorry_door(), "delivery")
	parts = [build.emit(p, "delivery") for p in make_parts()]

	build.report()

	door.location = (0, -0.9 - BODY_L / 2, BED + BODY_H)
	door.rotation_euler = (math.radians(-70), 0, 0)
	exporter.contact_sheet([lorry, door], os.path.join(exporter.PREVIEWS, "lorry.png"),
	                       views=(("rear", 9.0, 14), ("three_q", 8.0, 24)))
	x = 0.0
	for obj in parts:
		obj.location = (x, 0, 0)
		x += 1.0
	exporter.render_preview(parts, os.path.join(exporter.PREVIEWS, "rack_parts.png"),
	                        angle=58, elevation=18, resolution=(1200, 620))


if __name__ == "__main__":
	main()
