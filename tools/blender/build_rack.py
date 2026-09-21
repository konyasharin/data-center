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

def _bay_layout(units, width, height, cz):
	if units == 1:
		# a 2.5" carrier cannot stand up inside 44 mm, so a 1U bay reads as a narrow
		# vertical slot: carrier thickness across the face, drive depth into the box
		face_w, face_h, rows = SFF_H + 4 * MM, height * 0.60, 1
	else:
		face_w, face_h = LFF_W, LFF_H
		rows = max(1, min(4, int((height - 12 * MM) // (face_h + 4 * MM))))

	zone_l, zone_r = -width / 2 + 34 * MM, width / 2 - 58 * MM
	pitch_x = face_w + 4 * MM
	bays = max(1, min(10, int((zone_r - zone_l) // pitch_x)))
	pitch_z = face_h + 4 * MM
	return {
		"w": face_w, "h": face_h, "rows": rows, "bays": bays,
		"pitch_x": pitch_x, "pitch_z": pitch_z,
		"x0": (zone_l + zone_r) / 2 - pitch_x * (bays - 1) / 2,
		"z0": cz - pitch_z * (rows - 1) / 2,
	}


def _front_panel(b, units, width, height, cz, front=14 * MM):
	"""Bezel on the -Y face, built as a frame around a real opening.

	An earlier version laid a dark 'recess' panel over the solid front face. Two
	surfaces a millimetre apart is z-fighting by construction, and it showed up as
	pale rectangles crawling across the chassis. The opening is a hole in the front
	plate instead, so nothing is stacked.
	"""
	bay = _bay_layout(units, width, height, cz)
	assert bay["pitch_x"] > bay["w"], "drive bays overlap"

	# the opening must leave a frame: a bezel with no metal around the hole is not a
	# chassis, and a negative-width strip is not a box
	open_w = min(bay["pitch_x"] * bay["bays"] + 8 * MM, width - 76 * MM)
	open_h = min(bay["pitch_z"] * bay["rows"] + 6 * MM, height - 8 * MM)
	open_cx = bay["x0"] + bay["pitch_x"] * (bay["bays"] - 1) / 2
	left = open_cx - open_w / 2
	right = open_cx + open_w / 2
	top = cz + open_h / 2
	bottom = cz - open_h / 2

	plate = {"-Y": "steel"}
	b.box((left + width / 2, front, height), ((-width / 2 + left) / 2, front / 2, cz),
	      "steel_dark", bevel=0.8 * MM, mat_faces=plate)
	b.box((width / 2 - right, front, height), ((right + width / 2) / 2, front / 2, cz),
	      "steel_dark", bevel=0.8 * MM, mat_faces=plate)
	rail = cz + height / 2 - top
	b.box((open_w, front, rail), (open_cx, front / 2, (top + cz + height / 2) / 2),
	      "steel_dark", bevel=min(0.8 * MM, rail * 0.4), mat_faces=plate)
	b.box((open_w, front, rail), (open_cx, front / 2, (bottom + cz - height / 2) / 2),
	      "steel_dark", bevel=min(0.8 * MM, rail * 0.4), mat_faces=plate)

	# the well sits behind the front plate, inside the opening
	b.box((open_w - 4 * MM, 20 * MM, open_h - 4 * MM), (open_cx, front + 4 * MM, cz),
	      "mesh_black", bevel=0.6 * MM)

	for sx in (-1, 1):
		x = sx * (RACK_PANEL_WIDTH / 2 - 13 * MM)
		b.box((26 * MM, 5 * MM, height * 0.94), (x, -2.5 * MM, cz), "steel", bevel=0.8 * MM)
		for sz in ((0,) if units == 1 else (-0.3, 0.3)):
			b.cyl(3.5 * MM, 4 * MM, (x, -5.5 * MM, cz + sz * height),
			      "plastic_dark", sides=8, rot=(90, 0, 0))

	for sx in (-1, 1):
		x = sx * (width / 2 - 14 * MM)
		b.box((13 * MM, 16 * MM, height * 0.62), (x, -8 * MM, cz), "steel",
		      bevel=1.5 * MM)

	# Carriers are flat palette quads, not a detail map and not boxes.
	#
	# Not boxes: their top faces caught the ceiling lights and read as bright patches.
	# Not a detail map: a chassis is drawn through a MultiMesh, and a MultiMesh only
	# renders the mesh's first surface — the map silently never appeared, leaving the
	# dark well showing through in torn wedges. Flat quads on the atlas stay on
	# surface 0 and have no relief to catch light.
	for r in range(bay["rows"]):
		for i in range(bay["bays"]):
			x = bay["x0"] + i * bay["pitch_x"]
			z = bay["z0"] + r * bay["pitch_z"]
			b.quad((bay["w"], bay["h"]), (x, 1.0 * MM, z), "steel", facing=-1)
			b.quad((bay["w"] * 0.26, bay["h"] * 0.74), (x - bay["w"] * 0.30, 0.6 * MM, z),
			       "plastic_dark", facing=-1)
			b.quad((3.5 * MM, 3.5 * MM), (x + bay["w"] * 0.24, 0.4 * MM,
			                              z - bay["h"] * 0.3), "led_green", facing=-1)

	cx = width / 2 - 40 * MM
	b.box((24 * MM, 6 * MM, height * 0.8), (cx, -3 * MM, cz), "plastic_dark", bevel=0.8 * MM)
	for i, led in enumerate(("led_green", "led_amber", "led_blue")):
		b.box((5 * MM, 2 * MM, 5 * MM),
		      (cx - 9 * MM + i * 9 * MM, -7 * MM, cz + height * 0.22), led)
	b.cyl(5 * MM, 5 * MM, (cx, -4 * MM, cz - height * 0.18), "plastic_grey", sides=10,
	      rot=(90, 0, 0))

	b.louvres((16 * MM, height * 0.74, 6 * MM), (-width / 2 + 22 * MM, -4 * MM, cz),
	          max(2, units * 2), "mesh_black")


def make_server(units=1, name=None):
	depth = SERVER_DEPTH
	b = Builder()
	h = server_height(units)
	w = SERVER_WIDTH
	cz = h / 2

	front = 14 * MM
	b.box((w, depth - front, h), (0, front + (depth - front) / 2, cz), "steel_dark",
	      bevel=1.5 * MM, mat_faces={"+Z": "steel_dark"})

	_front_panel(b, units, w, h, cz, front)
	b.box((w * 0.98, 10 * MM, h * 0.9), (0, depth - 5 * MM, cz), "mesh_black",
	      bevel=1.0 * MM)

	# PSUs are the same dark grey as the chassis. In steel_light they were the
	# brightest thing in the hot aisle and read as random patches down the row —
	# real supplies are black with a coloured latch, nothing more
	for sx in (-1, 1):
		b.box((w * 0.22, 14 * MM, h * 0.62), (sx * w * 0.33, depth - 7 * MM, cz),
		      "steel_dark", bevel=1.0 * MM)
		b.cyl(h * 0.22, 6 * MM, (sx * w * 0.33, depth - 12 * MM, cz), "mesh_black",
		      sides=10, rot=(90, 0, 0))
		b.box((w * 0.05, 4 * MM, h * 0.30), (sx * w * 0.22, depth - 16 * MM, cz),
		      "paint_red", bevel=0.6 * MM)
		b.box((3 * MM, 2 * MM, 3 * MM), (sx * w * 0.22, depth - 18 * MM, cz + h * 0.22),
		      "led_green")
	b.box((w * 0.3, 10 * MM, h * 0.45), (0, depth - 5 * MM, cz), "plastic_dark",
	      bevel=0.8 * MM)

	return b.finish(name or f"server_{units}u", smooth_angle=0.0)


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

	# posts run 12 mm into the plinth and the roof; ending flush against them puts
	# four faces in the same plane
	post_h = total - RACK_PLINTH - RACK_ROOF + 24 * MM
	for sx in (-1, 1):
		for sy in (-1, 1):
			b.box((POST, POST, post_h),
			      (sx * (w - POST) / 2 - sx * 3 * MM, sy * (d - POST) / 2 - sy * 3 * MM,
			       RACK_PLINTH - 12 * MM + post_h / 2),
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
			b.detail((RAIL_W * 0.7, rail_h), (x, y - sy * (RAIL_T / 2 + 1.5 * MM), rail_z),
			         texture="dc_rail_holes", tile=U, plane="XZ", facing=-sy)

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

	inner_w, inner_h = w - 84 * MM, h - 84 * MM
	if kind != "glass":
		b.detail((inner_w, inner_h), (cx, 0, h / 2), texture="dc_perforation",
		         tile=26 * MM, plane="XZ", double_sided=True)
		# inner stiffeners: the sheet is 3 mm, the door has to read as a door from inside
		for j in (0.28, 0.72):
			b.box((inner_w, 14 * MM, 22 * MM), (cx, 9 * MM, 42 * MM + inner_h * j),
			      "rack_black", bevel=2 * MM)

	handle_x = w - 40 * MM
	b.box((36 * MM, 22 * MM, 150 * MM), (handle_x, -11 * MM, h * 0.48), "rack_black",
	      bevel=3 * MM)
	b.box((16 * MM, 74 * MM, 26 * MM), (handle_x, -46 * MM, h * 0.48), "alu_brushed",
	      bevel=4 * MM)
	b.cyl(11 * MM, 14 * MM, (handle_x, -14 * MM, h * 0.48 - 92 * MM), "alu", sides=12,
	      rot=(90, 0, 0))
	b.cyl(4 * MM, 3 * MM, (handle_x, -21 * MM, h * 0.48 - 92 * MM), "mesh_black", sides=8,
	      rot=(90, 0, 0))

	if kind != "rear":
		b.box((150 * MM, 3 * MM, 44 * MM), (cx, -t / 2 - 2 * MM, h - 96 * MM), "label")
		b.box((26 * MM, 3 * MM, 26 * MM), (cx - 96 * MM, -t / 2 - 2 * MM, h - 96 * MM),
		      "paint_blue")
		for i in range(3):
			b.box((70 * MM, 2 * MM, 16 * MM), (w - 120 * MM, -t / 2 - 2 * MM,
			                                   140 * MM + i * 26 * MM), "label")
	else:
		b.box((64 * MM, 3 * MM, 30 * MM), (cx, -t / 2 - 2 * MM, h - 96 * MM), "label")

	for sz in (0.10, 0.50, 0.90):
		b.cyl(13 * MM, 64 * MM, (6 * MM, 0, h * sz), "steel", sides=12)
		b.cyl(5 * MM, 76 * MM, (6 * MM, 0, h * sz), "alu", sides=8)

	obj = b.finish(name or f"rack_{units}u_door_{kind}")
	return obj


def make_rack_glass(units=42, name=None):
	"""Separate object so Godot can give it a transparent material; the smoked pane
	over a lit rack is most of what a modern cabinet looks like."""
	b = Builder()
	w, total = RACK_OUTER_WIDTH, rack_height(units)
	h = total - 20 * MM
	b.box((w - 84 * MM, 5 * MM, h - 84 * MM), (w / 2, 0, h / 2), "glass", bevel=1 * MM)
	obj = b.finish(name or f"rack_{units}u_glass")

	mat = bpy.data.materials.new("rack_glass")
	mat.use_nodes = True
	bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
	bsdf.inputs["Base Color"].default_value = (0.05, 0.06, 0.07, 1.0)
	bsdf.inputs["Roughness"].default_value = 0.08
	bsdf.inputs["Metallic"].default_value = 0.0
	bsdf.inputs["Alpha"].default_value = 0.25
	obj.data.materials.clear()
	obj.data.materials.append(mat)
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
	emit(make_rack_door(42, "glass"))
	emit(make_rack_glass(42))
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
