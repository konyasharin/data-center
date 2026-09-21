"""Palette atlas: every surface type is one texel, so a whole model is one material.

UVs point at texel centres, so no filter mode can bleed neighbours into a face.
Recolouring the game is then a texture swap, not a re-export.
"""

import bpy

ATLAS = 16  # texels per side

# name: (hex srgb, metallic, roughness, emission strength)
SLOTS = [
	("steel_dark", 0x2B2E33, 0.35, 0.58, 0.0),
	("steel", 0x484D55, 0.50, 0.52, 0.0),
	("steel_light", 0x7B8189, 0.75, 0.44, 0.0),
	("alu", 0xA8ADB4, 1.00, 0.33, 0.0),
	("alu_brushed", 0x8F959C, 0.90, 0.48, 0.0),
	("rack_black", 0x1A1D20, 0.25, 0.62, 0.0),
	("mesh_black", 0x0C0D0F, 0.50, 0.70, 0.0),
	("plastic_dark", 0x1A1B1E, 0.00, 0.60, 0.0),
	("plastic_grey", 0x55585C, 0.00, 0.55, 0.0),
	("plastic_white", 0xD5D7DA, 0.00, 0.50, 0.0),
	("rubber", 0x131416, 0.00, 0.85, 0.0),
	("pcb", 0x1F5F3F, 0.00, 0.55, 0.0),
	("gold", 0xC9A227, 1.00, 0.30, 0.0),
	("copper", 0xB06A3B, 1.00, 0.35, 0.0),
	("label", 0xE8E9EA, 0.00, 0.45, 0.0),
	("glass", 0x141A20, 0.00, 0.10, 0.0),
	("screen_off", 0x0B0D10, 0.00, 0.20, 0.0),
	("screen_on", 0x2E6FA8, 0.00, 0.20, 2.0),
	("led_green", 0x36C25A, 0.00, 0.30, 6.0),
	("led_amber", 0xE8A020, 0.00, 0.30, 6.0),
	("led_red", 0xE03A2F, 0.00, 0.30, 6.0),
	("led_blue", 0x3A7CE0, 0.00, 0.30, 6.0),
	("cable_blue", 0x1E4FA0, 0.00, 0.55, 0.0),
	("cable_yellow", 0xC9A31A, 0.00, 0.55, 0.0),
	("cable_red", 0xA82A22, 0.00, 0.55, 0.0),
	("cable_grey", 0x6E7276, 0.00, 0.55, 0.0),
	("cable_black", 0x111214, 0.00, 0.60, 0.0),
	("concrete", 0x8C8880, 0.00, 0.80, 0.0),
	("concrete_dark", 0x5E5B56, 0.00, 0.85, 0.0),
	("wall_panel", 0x9BA1A5, 0.35, 0.55, 0.0),
	("wall_panel_dark", 0x6C7276, 0.35, 0.60, 0.0),
	("roof_metal", 0x767C80, 0.60, 0.50, 0.0),
	("wood", 0x7B6A56, 0.00, 0.72, 0.0),
	("cardboard", 0xA8875A, 0.00, 0.85, 0.0),
	("paint_yellow", 0xD8A417, 0.00, 0.50, 0.0),
	("paint_red", 0xB22B22, 0.00, 0.50, 0.0),
	("paint_blue", 0x1F5C99, 0.00, 0.50, 0.0),
	("paint_green", 0x2E7D4F, 0.00, 0.50, 0.0),
	("skin", 0xC98E6B, 0.00, 0.65, 0.0),
	("skin_dark", 0x8A5A3C, 0.00, 0.65, 0.0),
	("hair_dark", 0x241C17, 0.00, 0.70, 0.0),
	("cloth_navy", 0x2B3440, 0.00, 0.75, 0.0),
	("cloth_grey", 0x585E66, 0.00, 0.75, 0.0),
	("hi_vis", 0xD9E03A, 0.00, 0.65, 0.0),
	("hi_vis_strip", 0xC8CCD0, 0.30, 0.40, 0.0),
	("boots", 0x1C1A18, 0.00, 0.70, 0.0),
	("helmet_white", 0xE2E4E6, 0.00, 0.35, 0.0),
]

INDEX = {name: i for i, (name, *_rest) in enumerate(SLOTS)}


def uv(name):
	i = INDEX[name]
	col, row = i % ATLAS, i // ATLAS
	return ((col + 0.5) / ATLAS, (row + 0.5) / ATLAS)


def _srgb_to_linear(c):
	return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _pixels(channel):
	"""Flat RGBA float buffer for one of the atlas maps."""
	buf = [0.0] * (ATLAS * ATLAS * 4)
	for i, (_name, rgb, metal, rough, emit) in enumerate(SLOTS):
		col, row = i % ATLAS, i // ATLAS
		o = (row * ATLAS + col) * 4
		r, g, b = ((rgb >> 16) & 255) / 255, ((rgb >> 8) & 255) / 255, (rgb & 255) / 255
		if channel == "albedo":
			px = (_srgb_to_linear(r), _srgb_to_linear(g), _srgb_to_linear(b), 1.0)
		elif channel == "orm":
			px = (1.0, rough, metal, 1.0)
		else:
			e = min(emit, 1.0)
			px = (r * e, g * e, b * e, 1.0)
		buf[o:o + 4] = px
	return buf


def build_images():
	imgs = {}
	for channel, colorspace in (("albedo", "sRGB"), ("orm", "Non-Color"), ("emission", "sRGB")):
		name = f"dc_atlas_{channel}"
		img = bpy.data.images.get(name)
		if img is None:
			img = bpy.data.images.new(name, ATLAS, ATLAS, alpha=True, float_buffer=False)
		img.colorspace_settings.name = colorspace
		img.pixels = _pixels(channel)
		imgs[channel] = img
	return imgs


def build_material(name="dc_atlas"):
	"""One Principled material fed by the three atlas maps; glTF exports it as-is."""
	mat = bpy.data.materials.get(name)
	if mat is not None:
		return mat

	imgs = build_images()
	mat = bpy.data.materials.new(name)
	mat.use_nodes = True
	nt = mat.node_tree
	nt.nodes.clear()

	out = nt.nodes.new("ShaderNodeOutputMaterial")
	out.location = (600, 0)
	bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
	bsdf.location = (300, 0)
	nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

	def tex(channel, y):
		n = nt.nodes.new("ShaderNodeTexImage")
		n.image = imgs[channel]
		n.interpolation = "Closest"
		n.extension = "CLIP"
		n.location = (-400, y)
		return n

	nt.links.new(tex("albedo", 250).outputs["Color"], bsdf.inputs["Base Color"])

	orm = tex("orm", 0)
	sep = nt.nodes.new("ShaderNodeSeparateColor")
	sep.location = (-100, 0)
	nt.links.new(orm.outputs["Color"], sep.inputs["Color"])
	nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
	nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])

	nt.links.new(tex("emission", -250).outputs["Color"], bsdf.inputs["Emission Color"])
	bsdf.inputs["Emission Strength"].default_value = 1.0
	return mat


def save_images(directory):
	import os
	os.makedirs(directory, exist_ok=True)
	paths = []
	for channel, img in build_images().items():
		path = os.path.join(directory, f"dc_atlas_{channel}.png")
		img.filepath_raw = path
		img.file_format = "PNG"
		img.save()
		paths.append(path)
	return paths
