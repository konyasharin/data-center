"""Racks, chassis and drive carriers.

Origins follow the project convention: -Y is the front face, +Z is up.
  rack   — origin at the centre of its floor footprint
  server — origin at the centre of the front face, bottom edge; body runs into +Y
This makes slotting a chassis into a rack a pure Z offset.

Run: blender -b --factory-startup --python tools/blender/build_rack.py
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy

from dclib import exporter
from dclib.meshkit import Builder, clear_scene
from dclib.units import (
	LFF_D, LFF_H, LFF_W, MM, RACK_OUTER_DEPTH, RACK_OUTER_WIDTH, RACK_PANEL_WIDTH,
	RACK_PLINTH, RACK_ROOF, SERVER_DEPTH, SERVER_GAP, SERVER_WIDTH, SFF_D, SFF_H,
	SFF_W, U,
	rack_height, server_height,
)

POST = 60 * MM          # corner post section
RAIL_W = 25 * MM        # mounting rail visible face
RAIL_T = 18 * MM


# ---------------------------------------------------------------- drives

def make_drive(kind="lff", name=None):
	b = Builder()
	w, h, d = (LFF_W, LFF_H, LFF_D) if kind == "lff" else (SFF_W, SFF_H, SFF_D)
	body_d = d - 12 * MM

	b.box((w, body_d, h), (0, body_d / 2 + 12 * MM, 0), "steel_dark", bevel=1.2 * MM)
	b.box((w, 10 * MM, h), (0, 6 * MM, 0), "alu_brushed", bevel=1.2 * MM,
	      mat_faces={"-Y": "alu"})

	b.box((w * 0.18, 5 * MM, h * 0.78), (-w / 2 + w * 0.13, 1.5 * MM, 0),
	      "plastic_dark", bevel=0.8 * MM)
	b.box((w * 0.55, 3 * MM, h * 0.30), (w * 0.08, 1.0 * MM, 0), "plastic_dark",
	      bevel=0.6 * MM)

	b.box((7 * MM, 2 * MM, 3 * MM), (w / 2 - 9 * MM, 0.8 * MM, h / 2 - 5 * MM), "led_green")
	b.box((7 * MM, 2 * MM, 3 * MM), (w / 2 - 9 * MM, 0.8 * MM, -h / 2 + 5 * MM), "led_amber")

	return b.finish(name or f"drive_{kind}")


# ---------------------------------------------------------------- chassis

def _front_panel(b, units, width, height, cz):
	"""Bezel detail on the -Y face. `cz` is the chassis centre height."""
	face = 1.5 * MM

	for sx in (-1, 1):
		x = sx * (RACK_PANEL_WIDTH / 2 - 13 * MM)
		b.box((26 * MM, 5 * MM, height * 0.94), (x, face, cz), "steel", bevel=0.8 * MM)
		for sz in ((0,) if units == 1 else (-0.3, 0.3)):
			b.cyl(3.5 * MM, 4 * MM, (x, face - 1 * MM, cz + sz * height),
			      "plastic_dark", sides=8, rot=(90, 0, 0))

	for sx in (-1, 1):
		x = sx * (width / 2 - 14 * MM)
		b.box((13 * MM, 26 * MM, height * 0.66), (x, -9 * MM, cz), "steel_light",
		      bevel=1.5 * MM)

	bay_zone_l = -width / 2 + 34 * MM
	bay_zone_r = width / 2 - 58 * MM
	span = bay_zone_r - bay_zone_l

	if units == 1:
		# a 2.5" carrier cannot stand up inside 44 mm, so a 1U bay reads as a narrow
		# vertical slot: carrier thickness across the face, drive depth into the box
		face_w, face_h = SFF_H + 4 * MM, height * 0.76
		rows = 1
	else:
		face_w, face_h = LFF_W, LFF_H
		rows = max(1, min(4, int((height - 12 * MM) // (face_h + 4 * MM))))

	pitch_x = face_w + 4 * MM
	bays = max(1, min(10, int(span // pitch_x)))  # real 1U chassis top out around 10
	start_x = (bay_zone_l + bay_zone_r) / 2 - pitch_x * (bays - 1) / 2
	pitch_z = face_h + 4 * MM
	start_z = cz - pitch_z * (rows - 1) / 2
	bw, bh = face_w, face_h

	# recessed bay well: the dark gap around each carrier is what makes the row read
	b.box((pitch_x * bays + 6 * MM, 8 * MM, pitch_z * rows + 6 * MM),
	      (start_x + pitch_x * (bays - 1) / 2, face + 3 * MM, cz), "mesh_black",
	      bevel=0.6 * MM)
	assert pitch_x > bw, f"drive bays overlap: pitch {pitch_x:.4f} <= carrier {bw:.4f}"

	for r in range(rows):
		for i in range(bays):
			x, z = start_x + i * pitch_x, start_z + r * pitch_z
			b.box((bw, 9 * MM, bh), (x, face - 2.5 * MM, z), "steel_dark",
			      bevel=0.8 * MM, mat_faces={"-Y": "alu_brushed"})
			if units == 1:
				b.box((bw * 0.42, 3 * MM, bh * 0.72), (x - bw * 0.24, face - 8 * MM, z),
				      "plastic_dark", bevel=0.5 * MM)
				b.box((2.5 * MM, 2 * MM, 2.5 * MM),
				      (x + bw * 0.22, face - 8 * MM, z - bh * 0.38), "led_green")
			else:
				b.box((bw * 0.16, 3 * MM, bh * 0.62), (x - bw * 0.33, face - 8 * MM, z),
				      "plastic_dark", bevel=0.5 * MM)
				b.box((2.5 * MM, 2 * MM, 2.5 * MM),
				      (x + bw * 0.30, face - 8 * MM, z + bh * 0.24), "led_green")

	cx = width / 2 - 40 * MM
	b.box((24 * MM, 5 * MM, height * 0.8), (cx, face, cz), "plastic_dark", bevel=0.8 * MM)
	for i, led in enumerate(("led_green", "led_amber", "led_blue")):
		b.box((3.5 * MM, 2 * MM, 3.5 * MM),
		      (cx - 8 * MM + i * 8 * MM, face + 2 * MM, cz + height * 0.22), led)
	b.cyl(5 * MM, 4 * MM, (cx, face, cz - height * 0.18), "plastic_grey", sides=10,
	      rot=(90, 0, 0))

	b.louvres((16 * MM, height * 0.74, 6 * MM), (-width / 2 + 22 * MM, face - 2 * MM, cz),
	          max(2, units * 2), "mesh_black")


def make_server(units=1, name=None):
	depth = SERVER_DEPTH
	b = Builder()
	h = server_height(units)
	w = SERVER_WIDTH
	cz = h / 2

	b.box((w, depth, h), (0, depth / 2, cz), "steel_dark", bevel=1.5 * MM,
	      mat_faces={"+Z": "steel_dark", "-Y": "steel"})

	b.box((w * 0.82, depth * 0.7, 1.5 * MM), (0, depth * 0.45, h - 0.5 * MM),
	      "steel", bevel=0.5 * MM)

	_front_panel(b, units, w, h, cz)
	b.box((w * 0.98, 10 * MM, h * 0.9), (0, depth - 5 * MM, cz), "mesh_black",
	      bevel=1.0 * MM)

	for sx in (-1, 1):
		b.box((w * 0.22, 14 * MM, h * 0.62), (sx * w * 0.33, depth - 7 * MM, cz),
		      "steel_light", bevel=1.0 * MM)
		b.cyl(h * 0.22, 6 * MM, (sx * w * 0.33, depth - 12 * MM, cz), "mesh_black",
		      sides=10, rot=(90, 0, 0))
	b.box((w * 0.3, 10 * MM, h * 0.45), (0, depth - 5 * MM, cz), "plastic_dark",
	      bevel=0.8 * MM)

	return b.finish(name or f"server_{units}u")


def make_server_lod(units=1, level=1):
	b = Builder()
	h = server_height(units)
	w = SERVER_WIDTH
	d = SERVER_DEPTH
	if level == 1:
		b.box((w, d, h), (0, d / 2, h / 2), "steel_dark", bevel=1.0 * MM,
		      mat_faces={"-Y": "alu_brushed"})
		b.box((w * 0.7, 4 * MM, h * 0.5), (-w * 0.08, 1 * MM, h / 2), "steel_dark")
		b.box((12 * MM, 2 * MM, 3 * MM), (w / 2 - 40 * MM, 1 * MM, h * 0.62), "led_green")
	else:
		b.box((w, d, h), (0, d / 2, h / 2), "steel_dark", bevel=0.0,
		      mat_faces={"-Y": "alu_brushed"})
	return b.finish(f"server_{units}u_lod{level}")


# ---------------------------------------------------------------- rack

def make_rack_frame(units=42, name=None):
	b = Builder()
	w, d = RACK_OUTER_WIDTH, RACK_OUTER_DEPTH
	total = rack_height(units)
	inner_bottom = RACK_PLINTH

	b.box((w, d, RACK_PLINTH), (0, 0, RACK_PLINTH / 2), "rack_black", bevel=3 * MM)
	for sx in (-1, 1):
		for sy in (-1, 1):
			b.cyl(24 * MM, 26 * MM, (sx * (w / 2 - 70 * MM), sy * (d / 2 - 70 * MM), 13 * MM),
			      "rubber", sides=10)

	for sx in (-1, 1):
		for sy in (-1, 1):
			b.box((POST, POST, total - RACK_PLINTH - RACK_ROOF),
			      (sx * (w - POST) / 2, sy * (d - POST) / 2,
			       RACK_PLINTH + (total - RACK_PLINTH - RACK_ROOF) / 2),
			      "rack_black", bevel=3 * MM)

	b.box((w, d, RACK_ROOF), (0, 0, total - RACK_ROOF / 2), "rack_black", bevel=3 * MM)
	b.box((w * 0.55, d * 0.3, 8 * MM), (0, -d * 0.18, total - 6 * MM), "mesh_black",
	      bevel=1 * MM)
	for sx in (-1, 1):
		b.cyl(55 * MM, 12 * MM, (sx * w * 0.22, d * 0.22, total - 8 * MM), "mesh_black",
		      sides=12)

	rail_h = units * U
	rail_z = inner_bottom + rail_h / 2
	for sx in (-1, 1):
		for sy, mat in ((-1, "steel"), (1, "steel_dark")):
			x = sx * (RACK_PANEL_WIDTH / 2 + RAIL_W / 2)
			y = sy * (d / 2 - 90 * MM)
			b.box((RAIL_W, RAIL_T, rail_h), (x, y, rail_z), mat, bevel=1.5 * MM)
			if sy < 0:
				for i in range(units):
					hz = inner_bottom + (i + 0.5) * U
					b.box((9 * MM, 4 * MM, 9 * MM), (x, y - RAIL_T / 2 + 1 * MM, hz),
					      "mesh_black", bevel=0.5 * MM)
					b.box((3 * MM, 2 * MM, 2 * MM),
					      (x - sx * 14 * MM, y - RAIL_T / 2, hz), "label")

	b.box((44 * MM, 44 * MM, units * U * 0.8),
	      (w / 2 - 80 * MM, d / 2 - 100 * MM, inner_bottom + units * U * 0.45),
	      "plastic_grey", bevel=2 * MM)
	for i in range(12):
		b.cyl(11 * MM, 6 * MM,
		      (w / 2 - 80 * MM, d / 2 - 124 * MM,
		       inner_bottom + units * U * 0.1 + i * units * U * 0.06),
		      "plastic_dark", sides=8, rot=(90, 0, 0))

	return b.finish(name or f"rack_{units}u_frame")


def make_rack_door(units=42, kind="front", name=None):
	"""Origin sits on the hinge axis so the game can rotate it directly."""
	b = Builder()
	w, total = RACK_OUTER_WIDTH, rack_height(units)
	h = total - 20 * MM
	t = 26 * MM
	cx = w / 2  # hinge at left edge, geometry extends into +X

	b.frame((w, h, t), 42 * MM, (cx, 0, h / 2), "rack_black", axis="Y", bevel=2.5 * MM)

	if kind == "front":
		inner_w, inner_h = w - 84 * MM, h - 84 * MM
		b.box((inner_w, 6 * MM, inner_h), (cx, 0, h / 2), "mesh_black", bevel=1 * MM)
		cols, rows = 7, max(8, units // 3)
		for i in range(1, cols):
			b.box((5 * MM, 10 * MM, inner_h), (cx - inner_w / 2 + i * inner_w / cols, -3 * MM,
			                                   h / 2), "rack_black", bevel=0.8 * MM)
		for j in range(1, rows):
			b.box((inner_w, 10 * MM, 5 * MM), (cx, -3 * MM,
			                                   j * inner_h / rows + 42 * MM), "rack_black",
			      bevel=0.8 * MM)
		b.box((90 * MM, 16 * MM, 26 * MM), (w - 34 * MM, -14 * MM, h * 0.48), "alu_brushed",
		      bevel=2 * MM)
		b.cyl(9 * MM, 22 * MM, (w - 34 * MM, -22 * MM, h * 0.48), "alu", sides=10,
		      rot=(90, 0, 0))
		b.box((120 * MM, 3 * MM, 40 * MM), (cx, -t / 2 - 1 * MM, h - 120 * MM), "label")
	else:
		b.box((w - 84 * MM, 8 * MM, h - 84 * MM), (cx, 0, h / 2), "rack_black", bevel=1 * MM)
		b.louvres((w - 120 * MM, h - 140 * MM, 8 * MM), (cx, -2 * MM, h / 2),
		          max(10, units // 2), "mesh_black")

	for sz in (0.12, 0.88):
		b.cyl(12 * MM, 60 * MM, (6 * MM, 0, h * sz), "steel", sides=10)

	obj = b.finish(name or f"rack_{units}u_door_{kind}")
	return obj


def make_rack_side(units=42, name=None):
	b = Builder()
	d, total = RACK_OUTER_DEPTH, rack_height(units)
	h = total - RACK_PLINTH - RACK_ROOF
	b.box((14 * MM, d - 30 * MM, h - 10 * MM), (0, 0, 0), "rack_black", bevel=2 * MM)
	b.box((6 * MM, d - 120 * MM, h - 120 * MM), (-6 * MM, 0, 0), "rack_black", bevel=1.5 * MM)
	for sz in (-1, 1):
		b.box((10 * MM, 90 * MM, 26 * MM), (-8 * MM, 0, sz * (h / 2 - 90 * MM)),
		      "alu_brushed", bevel=1.5 * MM)
	return b.finish(name or f"rack_{units}u_side")


def make_rack_lod(units=42, level=1):
	b = Builder()
	w, d, total = RACK_OUTER_WIDTH, RACK_OUTER_DEPTH, rack_height(units)
	if level == 1:
		b.box((w, d, RACK_PLINTH), (0, 0, RACK_PLINTH / 2), "rack_black", bevel=2 * MM)
		b.box((w, d, total - RACK_PLINTH), (0, 0, RACK_PLINTH + (total - RACK_PLINTH) / 2),
		      "rack_black", bevel=3 * MM, mat_faces={"-Y": "mesh_black"})
		b.box((w - 80 * MM, 6 * MM, total - 180 * MM), (0, -d / 2 - 2 * MM, total / 2),
		      "mesh_black")
	else:
		b.box((w, d, total), (0, 0, total / 2), "rack_black", bevel=0.0,
		      mat_faces={"-Y": "mesh_black"})
	return b.finish(f"rack_{units}u_lod{level}")


# ---------------------------------------------------------------- build

def main():
	clear_scene()
	exporter.setup_studio()

	build = exporter.Build()

	def emit(obj, folder="hardware"):
		return build.emit(obj, folder)

	frame = emit(make_rack_frame(42))
	door_f = emit(make_rack_door(42, "front"))
	door_r = emit(make_rack_door(42, "rear"))
	side = emit(make_rack_side(42))
	emit(make_rack_lod(42, 1))
	emit(make_rack_lod(42, 2))

	srv1 = emit(make_server(1))
	emit(make_server(2))
	emit(make_server(4))
	emit(make_server_lod(1, 1))
	emit(make_server_lod(1, 2))

	emit(make_drive("lff"))
	emit(make_drive("sff"))

	exporter.contact_sheet([srv1], os.path.join(exporter.PREVIEWS, "server_1u.png"),
	                       views=(("front", 90, 0), ("three_q", 58, 22)), ortho=True)
	drive = bpy.data.objects["drive_lff"]
	exporter.contact_sheet([drive], os.path.join(exporter.PREVIEWS, "drive_lff.png"),
	                       views=(("three_q", 62, 20),))

	stage_assembled(frame, door_f, door_r, side, srv1)
	build.report()


def stage_assembled(frame, door_f, door_r, side, srv1):
	"""Preview the parts the way the game assembles them: the real quality check."""
	w, d = RACK_OUTER_WIDTH, RACK_OUTER_DEPTH
	front_y = -d / 2 + 0.10

	door_f.location = (-w / 2, -d / 2 - 0.004, 0.010)
	door_f.rotation_euler = (0, 0, math.radians(-105))
	door_r.location = (w / 2, d / 2 + 0.004, 0.010)
	door_r.rotation_euler = (0, 0, math.pi)
	side.location = (w / 2 - 0.007, 0, RACK_PLINTH + (rack_height(42) - RACK_PLINTH - RACK_ROOF) / 2)

	populated = []
	for slot in list(range(6, 24)) + list(range(27, 38)):
		copy = srv1.copy()
		copy.data = srv1.data
		bpy.context.scene.collection.objects.link(copy)
		copy.location = (0, front_y, RACK_PLINTH + slot * U + SERVER_GAP)
		populated.append(copy)

	srv1.location = (0, front_y - 0.42, RACK_PLINTH + 24 * U)  # one chassis pulled out

	group = [frame, door_f, door_r, side, srv1] + populated
	exporter.contact_sheet(group, os.path.join(exporter.PREVIEWS, "rack.png"),
	                       views=(("front", 90, 6), ("three_q", 38, 16), ("closeup", 30, 4)))


if __name__ == "__main__":
	main()
