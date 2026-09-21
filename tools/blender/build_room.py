"""Room fabric: the raised floor, the ceiling grid and the cable trays.

None of it is scenery. The floor is where cold air comes from, the trays are where
the cabling from docs/03 physically runs, and both are what makes a hall read as a
data centre rather than a shed with boxes in it. Everything tiles on a 600 mm grid
so a hall can be laid out by index.

Run: blender -b --factory-startup --python tools/blender/build_room.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy

from dclib import exporter
from dclib.meshkit import Builder, clear_scene
from dclib.units import (MM, RACK_PANEL_WIDTH, SPINE_BASE, SPINE_CLIPS, SPINE_HEIGHT,
                         SPINE_PITCH, U)

TILE = 0.600
TILE_T = 32 * MM
PLENUM = 0.45          # raised floor cavity depth
TRAY_W = 0.30
CEIL_TILE = 0.600


def make_floor_tile(kind="solid"):
	"""Origin at the tile centre on the finished floor level; body hangs below."""
	b = Builder()
	t = TILE_T
	if kind == "grille":
		border = 48 * MM
		for sx in (-1, 1):
			b.box((border, TILE, t), (sx * (TILE - border) / 2, 0, -t / 2), "steel_dark",
			      bevel=2 * MM)
			b.box((TILE - 2 * border, border, t), (0, sx * (TILE - border) / 2, -t / 2),
			      "steel_dark", bevel=2 * MM)
		# palette geometry, not a detail map: floor tiles are instanced through a
		# MultiMesh, which only draws the mesh's first surface
		inner = TILE - 2 * border
		b.quad((inner, inner), (0, 0, -t / 2 - 2 * MM), "mesh_black", plane="XY")
		slots = 5
		bar = inner / (slots * 2 + 1)
		for i in range(slots + 1):
			offset = -inner / 2 + i * (inner - bar) / slots
			b.quad((bar, inner), (offset, 0, -t / 2 - 1 * MM), "steel_dark", plane="XY")
			b.quad((inner, bar), (0, offset, -t / 2 - 1 * MM), "steel_dark", plane="XY")
		b.box((TILE - 2 * border - 20 * MM, 22 * MM, 14 * MM), (0, 0, -t + 8 * MM),
		      "steel_dark", bevel=2 * MM)
	else:
		b.box((TILE, TILE, t), (0, 0, -t / 2), "concrete_dark", bevel=3 * MM,
		      mat_faces={"+Z": "plastic_grey"})
		b.box((TILE - 40 * MM, TILE - 40 * MM, 3 * MM), (0, 0, -1.5 * MM), "plastic_grey",
		      bevel=1 * MM)
	return b.finish(f"floor_tile_{kind}")


def make_floor_pedestal():
	"""One corner post of the raised floor. Origin is the finished floor level, so the
	whole assembly lives below the tiles and nothing pokes through them."""
	b = Builder()
	head = -TILE_T - 12 * MM
	h = PLENUM + head
	b.box((92 * MM, 92 * MM, 8 * MM), (0, 0, -PLENUM + 4 * MM), "steel_light", bevel=2 * MM)
	b.cyl(14 * MM, h - 14 * MM, (0, 0, head - h / 2), "steel", sides=10)
	b.box((76 * MM, 76 * MM, 10 * MM), (0, 0, head - 5 * MM), "steel_light", bevel=2 * MM)
	for axis in (0, 1):
		for s in (-1, 1):
			at = (s * TILE / 4, 0, head - 22 * MM) if axis == 0 else (0, s * TILE / 4, head - 22 * MM)
			size = (TILE / 2, 22 * MM, 24 * MM) if axis == 0 else (22 * MM, TILE / 2, 24 * MM)
			b.box(size, at, "steel", bevel=2 * MM)
	return b.finish("floor_pedestal")


def make_cable_tray(kind="straight"):
	"""Ladder tray, origin at the centre of a 2 m section on its underside."""
	b = Builder()
	length = 2.0 if kind == "straight" else TRAY_W
	side_h = 60 * MM

	if kind == "straight":
		for sy in (-1, 1):
			b.box((length, 12 * MM, side_h), (0, sy * TRAY_W / 2, side_h / 2), "steel_light",
			      bevel=2 * MM)
		rungs = int(length / 0.25)
		for i in range(rungs + 1):
			b.box((26 * MM, TRAY_W, 10 * MM),
			      (-length / 2 + i * length / rungs, 0, 8 * MM), "steel_light", bevel=1.5 * MM)
	else:
		for sy in (-1, 1):
			b.box((TRAY_W, 12 * MM, side_h), (0, sy * TRAY_W / 2, side_h / 2), "steel_light",
			      bevel=2 * MM)
			b.box((12 * MM, TRAY_W, side_h), (sy * TRAY_W / 2, 0, side_h / 2), "steel_light",
			      bevel=2 * MM)
		b.box((TRAY_W - 24 * MM, TRAY_W - 24 * MM, 10 * MM), (0, 0, 8 * MM), "steel_light",
		      bevel=1.5 * MM)
	return b.finish(f"cable_tray_{kind}")


def make_tray_hanger(drop=0.55):
	"""Threaded rod pair hanging a tray off the slab; origin at the ceiling anchor."""
	b = Builder()
	for sy in (-1, 1):
		b.cyl(5 * MM, drop, (0, sy * (TRAY_W / 2 + 14 * MM), -drop / 2), "steel", sides=6)
		b.cyl(9 * MM, 8 * MM, (0, sy * (TRAY_W / 2 + 14 * MM), -drop + 20 * MM), "steel",
		      sides=6)
	b.box((26 * MM, TRAY_W + 60 * MM, 16 * MM), (0, 0, -drop + 8 * MM), "steel", bevel=2 * MM)
	b.box((120 * MM, 120 * MM, 8 * MM), (0, 0, -4 * MM), "steel_light", bevel=2 * MM)
	return b.finish("tray_hanger")


def make_ceiling_tile():
	"""Sized to drop *into* the grid opening and rest on the flange — a tile as wide
	as the grid pitch intersects the T-bars and z-fights along every edge."""
	b = Builder()
	t = 15 * MM
	span = CEIL_TILE - 26 * MM
	b.box((span, span, t), (0, 0, t / 2 + 7 * MM), "ceiling_tile", bevel=2 * MM)
	return b.finish("ceiling_tile")


def make_ceiling_grid():
	"""One 600 mm cross of T-bar, so a ceiling is an instanced grid."""
	b = Builder()
	for axis in (0, 1):
		web = (CEIL_TILE, 10 * MM, 30 * MM) if axis == 0 else (10 * MM, CEIL_TILE, 30 * MM)
		flange = (CEIL_TILE, 24 * MM, 7 * MM) if axis == 0 else (24 * MM, CEIL_TILE, 7 * MM)
		b.box(web, (0, 0, 15 * MM + 7 * MM), "steel_light", bevel=1.5 * MM)
		b.box(flange, (0, 0, 3.5 * MM), "steel_light", bevel=1 * MM)
	return b.finish("ceiling_grid")


def make_blanking_panel(units=1):
	"""Empty U slots are never open holes in a real rack: they break the air path."""
	b = Builder()
	h = units * U - 3 * MM
	w = RACK_PANEL_WIDTH
	b.box((w, 12 * MM, h), (0, 6 * MM, 0), "rack_black", bevel=1.5 * MM)
	b.box((w - 80 * MM, 4 * MM, h - 10 * MM), (0, 1 * MM, 0), "rack_black", bevel=1 * MM)
	for sx in (-1, 1):
		b.cyl(4 * MM, 5 * MM, (sx * (w / 2 - 13 * MM), 0, 0), "plastic_dark", sides=8,
		      rot=(90, 0, 0))
	return b.finish(f"blanking_panel_{units}u")


def make_cable_manager():
	b = Builder()
	h = U - 3 * MM
	w = RACK_PANEL_WIDTH
	b.box((w, 16 * MM, h), (0, 8 * MM, 0), "rack_black", bevel=1.5 * MM)
	for i in range(5):
		x = -w / 2 + 62 * MM + i * (w - 124 * MM) / 4
		b.cyl(16 * MM, 12 * MM, (x, -12 * MM, 0), "plastic_dark", sides=12, rot=(90, 0, 0),
		      caps=False)
		b.box((12 * MM, 26 * MM, 8 * MM), (x, -12 * MM, -h / 2 + 6 * MM), "plastic_dark",
		      bevel=1 * MM)
	return b.finish("cable_manager_1u")


def make_pdu_strip():
	"""Vertical PDU that mounts in the rear channel rather than being part of the frame."""
	b = Builder()
	h = 1.5
	b.box((46 * MM, 46 * MM, h), (0, 0, h / 2), "plastic_grey", bevel=3 * MM)
	b.box((36 * MM, 10 * MM, 90 * MM), (0, -25 * MM, h - 70 * MM), "plastic_dark",
	      bevel=2 * MM)
	b.box((26 * MM, 3 * MM, 14 * MM), (0, -32 * MM, h - 52 * MM), "screen_on", bevel=1 * MM)
	for i in range(16):
		z = 80 * MM + i * (h - 200 * MM) / 15
		b.cyl(13 * MM, 8 * MM, (0, -26 * MM, z), "plastic_dark", sides=8, rot=(90, 0, 0))
		b.cyl(3 * MM, 3 * MM, (18 * MM, -29 * MM, z), "led_green", sides=6, rot=(90, 0, 0))
	return b.finish("pdu_strip")


def make_cable_spine():
	"""Vertical finger duct for the rear channel of a cabinet.

	Cords are pushed into the gaps between the fingers instead of hanging across the
	rack, which is what keeps a wired cabinet readable: one bundle running straight
	down, not forty diagonals. The gaps are the attachment points the scene picks up.
	"""
	b = Builder()
	h = SPINE_HEIGHT
	b.box((56 * MM, 8 * MM, h), (0, 0, h / 2), "plastic_grey", bevel=2 * MM)
	for i in range(SPINE_CLIPS + 1):
		z = SPINE_BASE + i * SPINE_PITCH - SPINE_PITCH / 2
		b.box((50 * MM, 46 * MM, 26 * MM), (0, -27 * MM, z), "plastic_grey", bevel=2 * MM)
		# the lip is what stops a bundle falling back out of the duct
		b.box((50 * MM, 8 * MM, 40 * MM), (0, -47 * MM, z), "plastic_dark", bevel=1.5 * MM)
	return b.finish("cable_spine")


def main():
	clear_scene()
	exporter.setup_studio()

	build = exporter.Build()
	made = {}
	for maker, folder in (
		(lambda: make_floor_tile("solid"), "room"),
		(lambda: make_floor_tile("grille"), "room"),
		(make_floor_pedestal, "room"),
		(lambda: make_cable_tray("straight"), "room"),
		(lambda: make_cable_tray("corner"), "room"),
		(make_tray_hanger, "room"),
		(make_ceiling_tile, "room"),
		(make_ceiling_grid, "room"),
		(lambda: make_blanking_panel(1), "hardware"),
		(lambda: make_blanking_panel(2), "hardware"),
		(make_cable_manager, "hardware"),
		(make_pdu_strip, "hardware"),
		(make_cable_spine, "hardware"),
	):
		obj = build.emit(maker(), folder)
		made[obj.name] = obj

	row = [made["floor_tile_solid"], made["floor_tile_grille"], made["floor_pedestal"],
	       made["ceiling_grid"], made["ceiling_tile"]]
	x = 0.0
	for obj in row:
		obj.location = (x, 0, 0.5)
		x += 0.9
	exporter.render_preview(row, os.path.join(exporter.PREVIEWS, "room_floor.png"),
	                        angle=58, elevation=26, resolution=(1200, 620))

	row2 = [made["cable_tray_straight"], made["blanking_panel_1u"],
	        made["cable_manager_1u"], made["pdu_strip"]]
	x = 0.0
	for obj in row2:
		obj.location = (x, 0, 0)
		x += max(obj.dimensions.x, 0.5) + 0.3
	exporter.render_preview(row2, os.path.join(exporter.PREVIEWS, "room_fittings.png"),
	                        angle=58, elevation=22, resolution=(1200, 620))

	build.report()


if __name__ == "__main__":
	main()
