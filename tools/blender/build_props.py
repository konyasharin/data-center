"""Phase-1 fittings: everything the shed needs before it is a data centre.

The laptop display is a separate object with its own material so Godot can bind a
SubViewport texture to it — the diegetic terminal from docs/09-interface-time.md.
The LOTO tag and lock exist because claim/LOTO is in the vertical slice, not because
a shed needs decoration.

Run: blender -b --factory-startup --python tools/blender/build_props.py
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy

from dclib import exporter
from dclib.meshkit import Builder, clear_scene
from dclib.units import DESK_H, MM, RACK_PANEL_WIDTH, U


def make_desk():
	b = Builder()
	w, d, h = 1.4, 0.7, DESK_H
	top = 28 * MM
	b.box((w, d, top), (0, 0, h - top / 2), "wood", bevel=4 * MM)
	for sx in (-1, 1):
		x = sx * (w / 2 - 60 * MM)
		b.box((40 * MM, d - 80 * MM, h - top), (x, 0, (h - top) / 2), "steel_dark",
		      bevel=3 * MM)
		b.box((70 * MM, d - 40 * MM, 30 * MM), (x, 0, 15 * MM), "steel_dark", bevel=4 * MM)
	b.box((w - 200 * MM, 30 * MM, 120 * MM), (0, d / 2 - 60 * MM, h - top - 90 * MM),
	      "steel_dark", bevel=3 * MM)
	return b.finish("desk")


def make_laptop_base():
	"""Origin at the hinge line so the lid object rotates around (0, 0, 0)."""
	b = Builder()
	w, d, t = 330 * MM, 230 * MM, 16 * MM
	b.box((w, d, t), (0, -d / 2, t / 2), "plastic_dark", bevel=2 * MM,
	      mat_faces={"+Z": "plastic_grey"})
	# key rows as strips: 70 individual keycaps only bought moire at this scale
	b.box((w - 36 * MM, d * 0.54, 4 * MM), (0, -d * 0.40, t - 1 * MM), "mesh_black",
	      bevel=1 * MM)
	for r in range(5):
		b.box((w - 52 * MM, 13 * MM, 4 * MM), (0, -d * 0.19 - r * 16 * MM, t + 1.5 * MM),
		      "plastic_grey", bevel=1 * MM)
	b.box((90 * MM, 60 * MM, 2 * MM), (0, -d + 50 * MM, t + 1 * MM), "plastic_grey",
	      bevel=1 * MM)
	for sx in (-1, 1):
		b.box((18 * MM, 8 * MM, 6 * MM), (sx * (w / 2 - 6 * MM), -d * 0.3, t / 2),
		      "alu_brushed", bevel=1 * MM)
	return b.finish("laptop_base")


def make_laptop_lid():
	b = Builder()
	w, h, t = 330 * MM, 215 * MM, 11 * MM
	# no screen panel here: laptop_display is a separate object in the same place,
	# and two coplanar panels 1 mm apart flicker as the camera moves
	b.box((w, t, h), (0, 0, h / 2), "plastic_dark", bevel=2 * MM)
	b.cyl(2 * MM, 3 * MM, (0, -t / 2 - 1 * MM, h - 9 * MM), "plastic_grey", sides=8,
	      rot=(90, 0, 0))
	return b.finish("laptop_lid")


def make_laptop_display():
	"""Bare quad in the lid's local space; Godot swaps this material for a viewport."""
	b = Builder()
	w, h = 330 * MM - 26 * MM, 215 * MM - 26 * MM
	b.box((w, 2 * MM, h), (0, -9 * MM, h / 2 + 11 * MM), "screen_on", bevel=0)
	obj = b.finish("laptop_display")
	mat = bpy.data.materials.new("terminal_screen")
	mat.use_nodes = True
	bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
	bsdf.inputs["Base Color"].default_value = (0.02, 0.05, 0.04, 1.0)
	bsdf.inputs["Emission Color"].default_value = (0.18, 0.85, 0.42, 1.0)
	bsdf.inputs["Emission Strength"].default_value = 2.5
	bsdf.inputs["Roughness"].default_value = 0.35
	obj.data.materials.clear()
	obj.data.materials.append(mat)
	return obj


def make_ups():
	b = Builder()
	w, d, h = 0.30, 0.52, 0.70
	b.box((w, d, h), (0, 0, h / 2), "plastic_dark", bevel=5 * MM,
	      mat_faces={"-Y": "plastic_dark"})
	b.box((w - 60 * MM, 6 * MM, 150 * MM), (0, -d / 2 - 1 * MM, h - 150 * MM),
	      "plastic_grey", bevel=3 * MM)
	b.box((110 * MM, 4 * MM, 70 * MM), (0, -d / 2 - 4 * MM, h - 150 * MM), "screen_off",
	      bevel=2 * MM)
	for i, led in enumerate(("led_green", "led_amber", "led_red")):
		b.cyl(4 * MM, 3 * MM, (-40 * MM + i * 40 * MM, -d / 2 - 3 * MM, h - 250 * MM),
		      led, sides=8, rot=(90, 0, 0))
	b.louvres((w - 80 * MM, h * 0.45, 8 * MM), (0, -d / 2 + 2 * MM, h * 0.28), 8)
	for i in range(4):
		b.box((46 * MM, 8 * MM, 46 * MM), (-w / 2 + 50 * MM + (i % 2) * 90 * MM,
		                                   d / 2 - 2 * MM, 120 * MM + (i // 2) * 90 * MM),
		      "plastic_white", bevel=2 * MM)
	return b.finish("ups")


def make_breaker_panel():
	"""Wall-mounted; origin on the wall face, box hangs into -Y."""
	b = Builder()
	w, h, d = 0.42, 0.62, 0.16
	b.box((w, d, h), (0, -d / 2, h / 2), "steel_light", bevel=4 * MM)
	b.box((w - 60 * MM, 8 * MM, h - 70 * MM), (0, -d - 2 * MM, h / 2), "plastic_white",
	      bevel=3 * MM)
	for row in range(2):
		for i in range(8):
			b.box((16 * MM, 26 * MM, 44 * MM),
			      (-w / 2 + 52 * MM + i * 38 * MM, -d - 14 * MM, h * 0.66 - row * 110 * MM),
			      "plastic_grey", bevel=1.5 * MM)
			b.box((10 * MM, 8 * MM, 16 * MM),
			      (-w / 2 + 52 * MM + i * 38 * MM, -d - 26 * MM,
			       h * 0.66 - row * 110 * MM + 12 * MM), "plastic_dark", bevel=1 * MM)
	b.box((120 * MM, 2 * MM, 40 * MM), (0, -d - 3 * MM, 70 * MM), "paint_yellow")
	b.cyl(9 * MM, 26 * MM, (w / 2 - 26 * MM, -d - 10 * MM, h / 2), "alu", sides=10,
	      rot=(90, 0, 0))
	return b.finish("breaker_panel")


def make_shelf():
	b = Builder()
	w, d, h = 1.0, 0.5, 2.0
	levels = 5
	for sx in (-1, 1):
		for sy in (-1, 1):
			b.box((40 * MM, 40 * MM, h), (sx * (w / 2 - 20 * MM), sy * (d / 2 - 20 * MM),
			                              h / 2), "steel", bevel=3 * MM)
	for i in range(levels):
		z = 80 * MM + i * (h - 140 * MM) / (levels - 1)
		b.box((w - 30 * MM, d - 30 * MM, 22 * MM), (0, 0, z), "steel_light", bevel=3 * MM)
		b.box((w - 30 * MM, 18 * MM, 44 * MM), (0, d / 2 - 24 * MM, z + 22 * MM), "steel",
		      bevel=3 * MM)
	return b.finish("shelf")


def make_box(kind="large"):
	b = Builder()
	w, d, h = (0.40, 0.30, 0.25) if kind == "large" else (0.26, 0.20, 0.16)
	b.box((w, d, h), (0, 0, h / 2), "cardboard", bevel=4 * MM)
	b.box((w * 0.5, 4 * MM, 3 * MM), (0, -d / 2 - 1 * MM, h * 0.6), "label")
	b.box((w - 30 * MM, d * 0.12, 3 * MM), (0, 0, h), "cardboard", bevel=2 * MM)
	return b.finish(f"box_{kind}")


def make_cart():
	b = Builder()
	w, d, h = 0.80, 0.52, 0.95
	b.box((w, d, 40 * MM), (0, 0, 0.22), "steel_light", bevel=4 * MM)
	b.box((w, d, 40 * MM), (0, 0, 0.60), "steel_light", bevel=4 * MM)
	for sx in (-1, 1):
		for sy in (-1, 1):
			b.box((34 * MM, 34 * MM, h * 0.72), (sx * (w / 2 - 24 * MM),
			                                     sy * (d / 2 - 24 * MM), h * 0.36),
			      "steel", bevel=3 * MM)
			b.cyl(60 * MM, 34 * MM, (sx * (w / 2 - 70 * MM), sy * (d / 2 - 60 * MM),
			                         60 * MM), "rubber", sides=12, rot=(0, 90, 0))
			b.box((40 * MM, 40 * MM, 60 * MM), (sx * (w / 2 - 70 * MM),
			                                    sy * (d / 2 - 60 * MM), 0.13), "steel",
			      bevel=3 * MM)
	b.box((w - 40 * MM, 34 * MM, 34 * MM), (0, -d / 2 + 20 * MM, h), "steel", bevel=4 * MM)
	for sx in (-1, 1):
		b.box((34 * MM, 34 * MM, 0.33), (sx * (w / 2 - 24 * MM), -d / 2 + 20 * MM,
		                                 h - 0.165), "steel", bevel=3 * MM)
	return b.finish("cart")


def make_extinguisher():
	b = Builder()
	r, h = 75 * MM, 0.50
	b.cyl(r, h, (0, 0, h / 2 + 30 * MM), "paint_red", sides=14, bevel=6 * MM)
	b.cone(r, r * 0.55, 90 * MM, (0, 0, h + 70 * MM), "paint_red", sides=14)
	b.cyl(r * 0.35, 60 * MM, (0, 0, h + 140 * MM), "alu_brushed", sides=10)
	b.box((150 * MM, 28 * MM, 22 * MM), (30 * MM, 0, h + 165 * MM), "plastic_dark",
	      bevel=3 * MM)
	b.cyl(18 * MM, 40 * MM, (-r * 0.6, 0, h + 120 * MM), "plastic_white", sides=10,
	      rot=(0, 90, 0))
	b.box((110 * MM, 4 * MM, 150 * MM), (0, -r - 1 * MM, h * 0.55), "label")
	b.cyl(r + 8 * MM, 26 * MM, (0, 0, 13 * MM), "plastic_dark", sides=14)
	return b.finish("extinguisher")


def make_ceiling_lamp():
	"""Origin at the ceiling anchor; body hangs below."""
	b = Builder()
	L = 1.24
	for sx in (-1, 1):
		b.cyl(6 * MM, 0.30, (sx * L * 0.3, 0, -0.15), "steel", sides=6)
	b.box((L, 110 * MM, 70 * MM), (0, 0, -0.34), "steel_light", bevel=5 * MM)
	b.box((L - 40 * MM, 90 * MM, 12 * MM), (0, 0, -0.375), "plastic_white", bevel=3 * MM)
	b.box((L - 60 * MM, 70 * MM, 6 * MM), (0, 0, -0.384), "screen_on", bevel=0)
	return b.finish("ceiling_lamp")


def make_patch_panel():
	b = Builder()
	h = U - 2 * MM
	w = RACK_PANEL_WIDTH
	b.box((w, 40 * MM, h), (0, 20 * MM, 0), "steel_dark", bevel=1.5 * MM,
	      mat_faces={"-Y": "steel"})
	for i in range(24):
		x = -w / 2 + 34 * MM + i * (w - 68 * MM) / 23
		b.box((13 * MM, 6 * MM, 15 * MM), (x, -1 * MM, 2 * MM), "mesh_black", bevel=0.6 * MM)
		b.box((10 * MM, 2 * MM, 4 * MM), (x, -3 * MM, -10 * MM), "label")
	for sx in (-1, 1):
		b.cyl(3 * MM, 4 * MM, (sx * (w / 2 - 12 * MM), -1 * MM, 0), "plastic_dark",
		      sides=8, rot=(90, 0, 0))
	return b.finish("patch_panel_1u")


def make_switch():
	"""Deeper than a real access switch on purpose: at 300 mm it sat less than half
	as deep as the servers around it and read as a broken chassis in an open rack."""
	b = Builder()
	h = U - 2 * MM
	w, d = RACK_PANEL_WIDTH, 0.46
	b.box((w - 50 * MM, d, h), (0, d / 2, 0), "steel_dark", bevel=1.5 * MM)
	for sx in (-1, 1):
		b.box((26 * MM, 4 * MM, h), (sx * (w / 2 - 13 * MM), 2 * MM, 0), "steel",
		      bevel=0.8 * MM)
	for row in (-1, 1):
		for i in range(12):
			x = -w / 2 + 60 * MM + i * 28 * MM
			b.box((17 * MM, 7 * MM, 12 * MM), (x, -1 * MM, row * 10 * MM), "mesh_black",
			      bevel=0.6 * MM)
			b.box((3 * MM, 2 * MM, 2 * MM), (x - 5 * MM, -4 * MM, row * 10 * MM + 7 * MM),
			      "led_green")
	b.box((40 * MM, 5 * MM, 24 * MM), (w / 2 - 60 * MM, 1 * MM, 0), "plastic_dark",
	      bevel=1 * MM)
	return b.finish("switch_1u")


def make_loto_tag():
	"""Hangs off a rack handle: the visible half of the claim system."""
	b = Builder()
	w, h, t = 80 * MM, 145 * MM, 3 * MM
	b.box((w, t, h), (0, 0, -h / 2 - 22 * MM), "paint_red", bevel=2 * MM)
	b.box((w - 16 * MM, t + 1 * MM, 34 * MM), (0, 0, -52 * MM), "label")
	b.box((w - 22 * MM, t + 1 * MM, 44 * MM), (0, 0, -110 * MM), "label")
	b.cyl(9 * MM, t + 6 * MM, (0, 0, -18 * MM), "steel_light", sides=10, rot=(90, 0, 0))
	b.cyl(13 * MM, 5 * MM, (0, 0, -6 * MM), "steel_light", sides=14, rot=(90, 0, 0))
	return b.finish("loto_tag")


def make_loto_lock():
	b = Builder()
	w, h, t = 42 * MM, 52 * MM, 20 * MM
	b.box((w, t, h), (0, 0, 0), "paint_red", bevel=4 * MM)
	b.cyl(5 * MM, 46 * MM, (-w * 0.28, 0, h * 0.75), "alu", sides=8)
	b.cyl(5 * MM, 46 * MM, (w * 0.28, 0, h * 0.75), "alu", sides=8)
	b.box((w * 0.56, 10 * MM, 10 * MM), (0, 0, h * 0.75 + 23 * MM), "alu", bevel=2 * MM)
	b.cyl(8 * MM, t + 2 * MM, (0, 0, -6 * MM), "alu_brushed", sides=10, rot=(90, 0, 0))
	return b.finish("loto_lock")


def make_toolbox():
	b = Builder()
	w, d, h = 0.48, 0.25, 0.22
	b.box((w, d, h * 0.62), (0, 0, h * 0.31), "paint_red", bevel=4 * MM)
	b.box((w - 20 * MM, d - 16 * MM, h * 0.40), (0, 0, h * 0.80), "paint_red", bevel=6 * MM)
	b.box((w * 0.34, 26 * MM, 18 * MM), (0, 0, h + 30 * MM), "plastic_dark", bevel=4 * MM)
	for sx in (-1, 1):
		b.box((16 * MM, 6 * MM, 40 * MM), (sx * w * 0.3, -d / 2 - 2 * MM, h * 0.62),
		      "alu_brushed", bevel=2 * MM)
	return b.finish("toolbox")


def make_pallet():
	b = Builder()
	w, d, h = 1.20, 0.80, 0.145
	for i in range(7):
		b.box((w, 90 * MM, 22 * MM), (0, -d / 2 + 45 * MM + i * (d - 90 * MM) / 6, h - 11 * MM),
		      "wood", bevel=3 * MM)
	for i in range(3):
		y = -d / 2 + 60 * MM + i * (d - 120 * MM) / 2
		b.box((w, 120 * MM, 80 * MM), (0, y, 62 * MM), "wood", bevel=3 * MM)
	for i in range(3):
		b.box((140 * MM, d, 22 * MM), (-w / 2 + 70 * MM + i * (w - 140 * MM) / 2, 0, 11 * MM),
		      "wood", bevel=3 * MM)
	return b.finish("pallet")


def make_cable_coil():
	b = Builder()
	for i in range(5):
		b.cyl(0.19 - i * 6 * MM, 26 * MM, (0, 0, 14 * MM + i * 22 * MM), "cable_blue",
		      sides=18, bevel=4 * MM)
	b.box((60 * MM, 8 * MM, 60 * MM), (0.16, 0, 60 * MM), "label", bevel=2 * MM)
	return b.finish("cable_coil")


def make_ac_indoor():
	"""Wall split unit — the shed's cooling in phase 1. Origin on the wall face at its
	top edge, so hanging it is a single height value."""
	b = Builder()
	w, h, d = 0.84, 0.29, 0.21
	b.box((w, d, h), (0, -d / 2, -h / 2), "plastic_white", bevel=14 * MM)
	b.box((w - 90 * MM, 10 * MM, 40 * MM), (0, -d - 2 * MM, -h * 0.78), "plastic_grey",
	      bevel=5 * MM)
	b.louvres((w - 120 * MM, h * 0.34, 12 * MM), (0, -d - 4 * MM, -h * 0.38), 5,
	          "plastic_white")
	b.box((70 * MM, 4 * MM, 16 * MM), (w / 2 - 70 * MM, -d - 4 * MM, -h * 0.8),
	      "screen_off", bevel=1 * MM)
	b.cyl(3 * MM, 3 * MM, (w / 2 - 110 * MM, -d - 5 * MM, -h * 0.8), "led_green", sides=8,
	      rot=(90, 0, 0))
	return b.finish("ac_indoor")


def make_ac_outdoor():
	b = Builder()
	w, d, h = 0.80, 0.30, 0.55
	b.box((w, d, h), (0, 0, h / 2 + 60 * MM), "plastic_white", bevel=8 * MM)
	b.cyl(0.21, 30 * MM, (0, -d / 2 - 2 * MM, h * 0.55 + 60 * MM), "mesh_black", sides=16,
	      rot=(90, 0, 0))
	for i in range(5):
		b.box((0.40, 6 * MM, 12 * MM), (0, -d / 2 - 12 * MM - i * 0.4 * MM,
		                                h * 0.55 + 60 * MM),
		      "plastic_grey", bevel=2 * MM, rot=(0, 20 + i * 36, 0))
	b.louvres((w - 80 * MM, h * 0.7, 10 * MM), (0, d / 2 - 4 * MM, h / 2 + 60 * MM), 12,
	          "mesh_black")
	for sx in (-1, 1):
		b.box((60 * MM, d + 80 * MM, 60 * MM), (sx * (w / 2 - 60 * MM), 0, 30 * MM),
		      "steel", bevel=4 * MM)
	return b.finish("ac_outdoor")


def main():
	clear_scene()
	exporter.setup_studio()

	makers = [
		("furniture", make_desk), ("furniture", make_shelf), ("furniture", make_pallet),
		("terminal", make_laptop_base), ("terminal", make_laptop_lid),
		("terminal", make_laptop_display),
		("power", make_ups), ("power", make_breaker_panel),
		("hardware", make_patch_panel), ("hardware", make_switch),
		("cooling", make_ac_indoor), ("cooling", make_ac_outdoor),
		("props", make_box), ("props", make_cart), ("props", make_extinguisher),
		("props", make_ceiling_lamp), ("props", make_toolbox), ("props", make_cable_coil),
		("loto", make_loto_tag), ("loto", make_loto_lock),
	]

	build = exporter.Build()
	objects = {}
	for folder, maker in makers:
		obj = build.emit(maker(), folder)
		objects[obj.name] = obj
	objects["box_small"] = build.emit(make_box("small"), "props")

	_stage_previews(objects)
	build.report(total=True)


def _stage_previews(o):
	lid = o["laptop_lid"]
	display = o["laptop_display"]
	desk = o["desk"]
	lid.rotation_euler = (math.radians(-18), 0, 0)
	display.rotation_euler = (math.radians(-18), 0, 0)
	for part in (o["laptop_base"], lid, display):
		part.location = (0, 0.06, DESK_H)
	exporter.contact_sheet([desk, o["laptop_base"], lid, display],
	                       os.path.join(exporter.PREVIEWS, "terminal.png"),
	                       views=(("three_q", 58, 26),))

	groups = {
		"power": [o["ups"], o["breaker_panel"], o["ac_indoor"], o["ac_outdoor"]],
		"storage": [o["shelf"], o["cart"], o["pallet"], o["box_large"], o["box_small"]],
		"tools": [o["extinguisher"], o["toolbox"], o["cable_coil"], o["ceiling_lamp"],
		          o["loto_tag"], o["loto_lock"]],
		"network": [o["patch_panel_1u"], o["switch_1u"]],
	}
	for name, group in groups.items():
		x = 0.0
		for obj in group:
			width = max(obj.dimensions.x, 0.3) + 0.30
			obj.location = (x + width / 2, 0, 0)
			x += width
		exporter.render_preview(group, os.path.join(exporter.PREVIEWS, f"props_{name}.png"),
		                        angle=62, elevation=20, resolution=(1200, 620))


if __name__ == "__main__":
	main()
