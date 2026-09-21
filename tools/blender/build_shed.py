"""Phase-1 shell: the shed from docs/02-progression.md, walked into from the inside.

Exported in pieces so the game can animate the openings and, later, swap the shell
for a bigger one without touching the fittings:
  shed_shell      — slab, walls, steel frame, roof
  shed_gate       — sectional gate, origin on the floor at the opening centre
  shed_door       — personnel door, origin on the hinge axis
Run: blender -b --factory-startup --python tools/blender/build_shed.py
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy

from dclib import exporter
from dclib.meshkit import Builder, clear_scene
from dclib.units import (
	DOOR_H, DOOR_W, GATE_H, GATE_W, MM, SHED_D, SHED_RIDGE_H, SHED_W, SHED_WALL_H, WALL_T,
)

SLAB_T = 150 * MM
OVERHANG = 300 * MM
COLUMN = 180 * MM
GATE_X = -SHED_W / 2 + GATE_W / 2 + 700 * MM     # gate sits left of centre on the front wall
DOOR_X = SHED_W / 2 - DOOR_W / 2 - 600 * MM
WINDOW_H = 700 * MM
WINDOW_SILL = SHED_WALL_H - WINDOW_H - 350 * MM


def _ribs(b, length, height, at, axis, count, mat="wall_panel", depth=28 * MM):
	"""Trapezoidal-sheet ribs. Cheap, and they are what makes a box read as a shed."""
	pitch = length / count
	for i in range(count):
		offset = -length / 2 + pitch * (i + 0.5)
		if axis == "X":
			b.box((pitch * 0.34, depth, height), (at[0] + offset, at[1], at[2]), mat,
			      bevel=4 * MM)
		else:
			b.box((depth, pitch * 0.34, height), (at[0], at[1] + offset, at[2]), mat,
			      bevel=4 * MM)


def _wall(b, length, at, axis, height=SHED_WALL_H, inner="wall_panel_dark",
          outer="wall_panel", ribs=True, rib_side=-1):
	z = at[2] + height / 2
	if axis == "X":
		faces = {"-Y": outer, "+Y": inner} if rib_side < 0 else {"+Y": outer, "-Y": inner}
		b.box((length, WALL_T, height), (at[0], at[1], z), "wall_panel_dark",
		      bevel=6 * MM, mat_faces=faces)
		if ribs:
			_ribs(b, length, height * 0.98, (at[0], at[1] + rib_side * (WALL_T / 2 + 6 * MM), z),
			      "X", max(4, int(length / 0.45)), outer)
	else:
		faces = {"-X": outer, "+X": inner} if rib_side < 0 else {"+X": outer, "-X": inner}
		b.box((WALL_T, length, height), (at[0], at[1], z), "wall_panel_dark",
		      bevel=6 * MM, mat_faces=faces)
		if ribs:
			_ribs(b, length, height * 0.98, (at[0] + rib_side * (WALL_T / 2 + 6 * MM), at[1], z),
			      "Y", max(4, int(length / 0.45)), outer)


def _column(b, at, height):
	"""I-section stand-in: two flanges and a web."""
	for sx in (-1, 1):
		b.box((COLUMN, 16 * MM, height), (at[0], at[1] + sx * (COLUMN / 2 - 8 * MM),
		                                  at[2] + height / 2), "steel", bevel=3 * MM)
	b.box((14 * MM, COLUMN - 32 * MM, height), (at[0], at[1], at[2] + height / 2),
	      "steel", bevel=2 * MM)


def _truss(b, y, span, wall_h, ridge_h, drop):
	"""Pitched truss: two rafters, a tie beam and a king post, all clear of the deck."""
	apex = ridge_h - drop
	rise = apex - wall_h
	half = span / 2
	length = math.hypot(half, rise)
	pitch = math.degrees(math.atan2(rise, half))

	b.box((span, 90 * MM, 70 * MM), (0, y, wall_h + 35 * MM), "steel", bevel=4 * MM)
	b.box((80 * MM, 80 * MM, apex - wall_h), (0, y, (wall_h + apex) / 2), "steel", bevel=4 * MM)
	for sx in (-1, 1):
		b.box((length, 80 * MM, 90 * MM), (sx * half / 2, y, (wall_h + apex) / 2),
		      "steel", bevel=4 * MM, rot=(0, sx * pitch, 0))
		b.box((length * 0.5, 60 * MM, 60 * MM), (sx * half * 0.52, y, wall_h + rise * 0.16),
		      "steel", bevel=3 * MM, rot=(0, -sx * pitch * 1.4, 0))


def make_shell():
	b = Builder()
	w, d = SHED_W, SHED_D
	outer_w, outer_d = w + WALL_T, d + WALL_T

	b.box((outer_w + 2 * OVERHANG, outer_d + 2 * OVERHANG, SLAB_T), (0, 0, -SLAB_T / 2),
	      "concrete_dark", bevel=10 * MM, mat_faces={"+Z": "concrete"})
	b.box((w, d, 4 * MM), (0, 0, 2 * MM), "concrete", bevel=0)
	for sx in (-1, 1):
		b.box((120 * MM, d * 0.9, 3 * MM), (sx * (w / 2 - 1.1), 0, 5 * MM), "paint_yellow")

	front_y = -(d + WALL_T) / 2
	segments = [
		(-w / 2, GATE_X - GATE_W / 2),
		(GATE_X + GATE_W / 2, DOOR_X - DOOR_W / 2),
		(DOOR_X + DOOR_W / 2, w / 2),
	]
	for x0, x1 in segments:
		if x1 - x0 > 1 * MM:
			_wall(b, x1 - x0, ((x0 + x1) / 2, front_y, 0), "X")
	b.box((GATE_W, WALL_T, SHED_WALL_H - GATE_H), (GATE_X, front_y,
	                                               GATE_H + (SHED_WALL_H - GATE_H) / 2),
	      "wall_panel_dark", bevel=6 * MM, mat_faces={"-Y": "wall_panel"})
	b.box((DOOR_W, WALL_T, SHED_WALL_H - DOOR_H), (DOOR_X, front_y,
	                                               DOOR_H + (SHED_WALL_H - DOOR_H) / 2),
	      "wall_panel_dark", bevel=6 * MM, mat_faces={"-Y": "wall_panel"})
	b.box((GATE_W + 120 * MM, WALL_T + 40 * MM, 160 * MM), (GATE_X, front_y, GATE_H + 80 * MM),
	      "steel", bevel=5 * MM)

	_wall(b, w, (0, (d + WALL_T) / 2, 0), "X", rib_side=1)
	for sx in (-1, 1):
		side_x = sx * (w + WALL_T) / 2
		band_z = WINDOW_SILL
		# run past the front/back walls, otherwise each corner keeps a 200 mm gap
		_wall(b, d + 2 * WALL_T, (side_x, 0, 0), "Y", height=band_z, rib_side=sx)
		_wall(b, d + 2 * WALL_T, (side_x, 0, band_z + WINDOW_H), "Y",
		      height=SHED_WALL_H - band_z - WINDOW_H, rib_side=sx)
		for i in range(3):
			y = -d / 2 + d * (i + 0.5) / 3
			b.box((WALL_T * 0.5, d / 3 - 200 * MM, WINDOW_H), (side_x, y, band_z + WINDOW_H / 2),
			      "glass", bevel=4 * MM)
			b.frame((d / 3 - 160 * MM, WINDOW_H + 40 * MM, WALL_T * 0.8), 60 * MM,
			        (side_x, y, band_z + WINDOW_H / 2), "steel_light", axis="X", bevel=3 * MM)

	for sx in (-1, 1):
		for sy in (-1, 1):
			_column(b, (sx * (w / 2 - COLUMN / 2), sy * (d / 2 - COLUMN / 2), 0), SHED_WALL_H)
	for sy in (-1, 1):
		_column(b, (0, sy * (d / 2 - COLUMN / 2), 0), SHED_WALL_H)

	# purlins sit under the deck, the deck spans ridge to eave plus the overhang
	rise = SHED_RIDGE_H - SHED_WALL_H
	half = w / 2
	pitch_rad = math.atan2(rise, half)
	pitch = math.degrees(pitch_rad)
	deck_t = 60 * MM
	purlin = 80 * MM
	deck_half_v = deck_t / 2 / math.cos(pitch_rad)

	trusses = 3
	for i in range(trusses):
		_truss(b, -d / 2 + d * (i + 0.5) / trusses, w, SHED_WALL_H, SHED_RIDGE_H,
		       deck_half_v + purlin + 50 * MM)

	for sx in (-1, 1):
		for k in (0.3, 0.62, 0.94):
			b.box((70 * MM, d + 2 * OVERHANG, purlin),
			      (sx * half * k, 0,
			       SHED_RIDGE_H - rise * k - deck_half_v - purlin / 2 - 15 * MM),
			      "steel", bevel=3 * MM)

		eave_x = sx * (half + OVERHANG * math.cos(pitch_rad))
		eave_z = SHED_WALL_H - OVERHANG * math.sin(pitch_rad)
		mid_x, mid_z = eave_x / 2, (SHED_RIDGE_H + eave_z) / 2
		length = math.hypot(eave_x, SHED_RIDGE_H - eave_z)
		b.box((length, d + 2 * OVERHANG, deck_t), (mid_x, 0, mid_z), "roof_metal",
		      bevel=5 * MM, rot=(0, sx * pitch, 0))

	b.box((300 * MM, d + 2 * OVERHANG, 70 * MM), (0, 0, SHED_RIDGE_H + 40 * MM),
	      "roof_metal", bevel=6 * MM)

	return b.finish("shed_shell", smooth_angle=30)


def make_gate():
	"""Origin on the floor at the opening centre; panels stack upward when opened."""
	b = Builder()
	panels = 4
	ph = GATE_H / panels
	for i in range(panels):
		z = ph * (i + 0.5)
		b.box((GATE_W - 40 * MM, 60 * MM, ph - 14 * MM), (0, 0, z), "wall_panel",
		      bevel=6 * MM, mat_faces={"-Y": "wall_panel", "+Y": "wall_panel_dark"})
		if i == panels - 1:
			for k in (-1, 0, 1):
				b.box((560 * MM, 26 * MM, 240 * MM), (k * 0.95, -32 * MM, z), "glass",
				      bevel=4 * MM)
				b.frame((600 * MM, 280 * MM, 34 * MM), 40 * MM, (k * 0.95, -32 * MM, z),
				        "wall_panel_dark", axis="Y", bevel=3 * MM)
		else:
			for sz in (-0.26, 0.26):
				b.box((GATE_W - 120 * MM, 20 * MM, 26 * MM), (0, -34 * MM, z + sz * ph),
				      "wall_panel_dark", bevel=4 * MM)
	for sx in (-1, 1):
		b.box((70 * MM, 80 * MM, GATE_H + 120 * MM), (sx * (GATE_W / 2 - 10 * MM), 20 * MM,
		                                              GATE_H / 2), "steel", bevel=4 * MM)
	b.box((240 * MM, 70 * MM, 70 * MM), (0, -60 * MM, 1.05), "steel_light", bevel=5 * MM)
	return b.finish("shed_gate")


def make_door():
	"""Origin on the hinge axis at the floor; leaf extends into +X."""
	b = Builder()
	w, h, t = DOOR_W, DOOR_H, 55 * MM
	b.box((w, t, h), (w / 2, 0, h / 2), "paint_blue", bevel=5 * MM)
	b.box((w - 180 * MM, t + 10 * MM, h * 0.44), (w / 2, 0, h * 0.68), "paint_blue",
	      bevel=8 * MM)
	b.box((w - 180 * MM, t + 10 * MM, h * 0.30), (w / 2, 0, h * 0.24), "paint_blue",
	      bevel=8 * MM)
	b.box((26 * MM, 130 * MM, 32 * MM), (w - 90 * MM, -60 * MM, 1.05), "alu_brushed",
	      bevel=4 * MM)
	b.cyl(22 * MM, 20 * MM, (w - 90 * MM, -t / 2 - 6 * MM, 0.98), "alu", sides=12,
	      rot=(90, 0, 0))
	for z in (0.25, 0.98, 1.85):
		b.cyl(16 * MM, 70 * MM, (14 * MM, 0, z), "steel", sides=10)
	b.box((180 * MM, 4 * MM, 240 * MM), (w / 2, -t / 2 - 2 * MM, h - 420 * MM), "label")
	return b.finish("shed_door")


def main():
	clear_scene()
	exporter.setup_studio()

	build = exporter.Build()

	def emit(obj, folder="building"):
		return build.emit(obj, folder)

	shell = emit(make_shell())
	gate = emit(make_gate())
	door = emit(make_door())

	gate.location = (GATE_X, -(SHED_D + WALL_T) / 2, 0)
	door.location = (DOOR_X - DOOR_W / 2, -(SHED_D + WALL_T) / 2, 0)

	group = [shell, gate, door]
	exporter.contact_sheet(group, os.path.join(exporter.PREVIEWS, "shed.png"),
	                       views=(("front", 74, 12), ("three_q", 36, 26)))

	exporter.render_eye(group, os.path.join(exporter.PREVIEWS, "shed_interior.png"),
	                    eye=(SHED_W / 2 - 0.9, SHED_D / 2 - 0.9, 1.65),
	                    target=(-SHED_W / 2 + 1.0, -SHED_D / 2 + 1.2, 1.3))

	build.report()


if __name__ == "__main__":
	main()
