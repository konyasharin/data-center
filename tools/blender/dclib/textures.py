"""Procedural tiling maps for detail the palette cannot carry.

The palette atlas gives every surface a flat colour in one draw call. Perforated
doors, floor grilles and rack rails are holes and fine pattern — geometry would cost
thousands of triangles each, so they get a second material with an alpha map instead.
Two draw calls per model, not two thousand triangles.
"""

import math

import bpy

SIZE = 256


def _new_image(name, width=SIZE, height=SIZE, colorspace="sRGB", alpha=True):
	img = bpy.data.images.get(name)
	if img is None:
		img = bpy.data.images.new(name, width, height, alpha=alpha)
	img.colorspace_settings.name = colorspace
	return img


def _write(img, fn):
	buf = [0.0] * (img.size[0] * img.size[1] * 4)
	w, h = img.size
	for y in range(h):
		for x in range(w):
			o = (y * w + x) * 4
			buf[o:o + 4] = fn(x / w, y / h)
	img.pixels = buf
	return img


def perforation(name="dc_perforation", holes=8, radius=0.33, base=0.09):
	"""Round-hole sheet: one tile is `holes` x `holes` holes on a staggered grid."""
	def px(u, v):
		cu, cv = (u * holes) % 1.0 - 0.5, (v * holes) % 1.0 - 0.5
		if int(v * holes) % 2:
			cu = (u * holes + 0.5) % 1.0 - 0.5
		d = math.hypot(cu, cv)
		if d < radius:
			return (0.0, 0.0, 0.0, 0.0)
		edge = min(1.0, (d - radius) * 12.0)
		shade = base * (0.55 + 0.45 * edge)
		return (shade, shade, shade * 1.06, 1.0)

	return _write(_new_image(name), px)


def rail_holes(name="dc_rail_holes", pitch=8, square=0.34, base=0.34):
	"""Square-hole mounting rail: three holes per U, which is what EIA-310 looks like."""
	def px(u, v):
		cv = (v * pitch) % 1.0 - 0.5
		cu = u - 0.5
		if abs(cu) < square and abs(cv) < square * 0.9:
			return (0.02, 0.02, 0.025, 1.0)
		shade = base * (0.9 + 0.2 * abs(cu))
		return (shade, shade, shade * 1.04, 1.0)

	return _write(_new_image(name), px)


def floor_grille(name="dc_floor_grille", slots=6, open_ratio=0.52, base=0.42):
	"""Perforated raised-floor tile: a slotted field inside a solid border."""
	def px(u, v):
		border = 0.055
		if u < border or u > 1 - border or v < border or v > 1 - border:
			shade = base * 1.12
			return (shade, shade, shade, 1.0)
		iu = (u - border) / (1 - 2 * border)
		iv = (v - border) / (1 - 2 * border)
		su = (iu * slots) % 1.0
		sv = (iv * slots) % 1.0
		if abs(su - 0.5) < open_ratio / 2 and abs(sv - 0.5) < open_ratio / 2:
			return (0.0, 0.0, 0.0, 0.0)
		shade = base
		return (shade, shade, shade * 1.03, 1.0)

	return _write(_new_image(name), px)


def panel_wear(name="dc_panel_wear", base=0.5):
	"""Faint brushed streaks so large flat metal is not perfectly uniform."""
	def px(u, v):
		streak = 0.5 + 0.5 * math.sin(v * 220.0 + math.sin(u * 9.0) * 2.0)
		grain = 0.5 + 0.5 * math.sin((u * 631.0 + v * 197.0) * 3.0)
		shade = base * (0.94 + 0.05 * streak + 0.03 * grain)
		return (shade, shade, shade * 1.02, 1.0)

	return _write(_new_image(name), px)


def drive_bays(name="dc_drive_bays"):
	"""One drive bay, tiled across the chassis opening.

	As geometry a carrier row is ~40 small boxes per server whose top faces catch the
	ceiling lights and read as loose bright patches down a dark aisle. Painted into a
	map the row is two triangles and stays flat under any light.
	"""
	def px(u, v):
		gap_u, gap_v = 0.07, 0.10
		if u < gap_u or u > 1 - gap_u or v < gap_v or v > 1 - gap_v:
			return (0.035, 0.037, 0.040, 1.0)          # recess between carriers
		iu = (u - gap_u) / (1 - 2 * gap_u)
		iv = (v - gap_v) / (1 - 2 * gap_v)
		if iu < 0.30:                                   # latch
			shade = 0.10 if iu > 0.06 else 0.05
			return (shade, shade, shade * 1.05, 1.0)
		if 0.62 < iu < 0.78 and 0.10 < iv < 0.24:       # activity LED
			return (0.20, 0.62, 0.30, 1.0)
		face = 0.30 + 0.04 * (1.0 - iv)
		if iv > 0.86 or iv < 0.08:
			face *= 0.82                                # rolled edge of the carrier
		return (face, face * 1.01, face * 1.05, 1.0)

	return _write(_new_image(name, 64, 96), px)


def drive_bays_emission(name="dc_drive_bays_emit"):
	def px(u, v):
		gap_u, gap_v = 0.07, 0.10
		if gap_u < u < 1 - gap_u and gap_v < v < 1 - gap_v:
			iu = (u - gap_u) / (1 - 2 * gap_u)
			iv = (v - gap_v) / (1 - 2 * gap_v)
			if 0.62 < iu < 0.78 and 0.10 < iv < 0.24:
				return (0.21, 0.76, 0.35, 1.0)
		return (0.0, 0.0, 0.0, 1.0)

	return _write(_new_image(name, 64, 96), px)


BUILDERS = {
	"dc_drive_bays": drive_bays,
	"dc_drive_bays_emit": drive_bays_emission,
	"dc_perforation": perforation,
	"dc_rail_holes": rail_holes,
	"dc_floor_grille": floor_grille,
	"dc_panel_wear": panel_wear,
}


def build_material(name, alpha=None, roughness=0.55, metallic=0.7):
	mat = bpy.data.materials.get(name)
	if mat is not None:
		return mat

	if alpha is None:
		alpha = name not in OPAQUE
	img = BUILDERS[name](name)
	mat = bpy.data.materials.new(name)
	mat.use_nodes = True
	nt = mat.node_tree
	nt.nodes.clear()

	out = nt.nodes.new("ShaderNodeOutputMaterial")
	out.location = (400, 0)
	bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
	bsdf.location = (150, 0)
	bsdf.inputs["Roughness"].default_value = roughness
	bsdf.inputs["Metallic"].default_value = metallic
	nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

	tex = nt.nodes.new("ShaderNodeTexImage")
	tex.image = img
	tex.interpolation = "Linear"
	tex.extension = "REPEAT"
	tex.location = (-250, 0)
	nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])

	if name in EMISSIVE:
		emit = nt.nodes.new("ShaderNodeTexImage")
		emit.image = BUILDERS[EMISSIVE[name]](EMISSIVE[name])
		emit.interpolation = "Linear"
		emit.extension = "REPEAT"
		emit.location = (-250, -300)
		nt.links.new(emit.outputs["Color"], bsdf.inputs["Emission Color"])
		bsdf.inputs["Emission Strength"].default_value = 1.6

	if alpha:
		nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
		mat.blend_method = "CLIP" if hasattr(mat, "blend_method") else mat.blend_method
	return mat


OPAQUE = {"dc_drive_bays", "dc_drive_bays_emit", "dc_panel_wear"}
EMISSIVE = {"dc_drive_bays": "dc_drive_bays_emit"}


def save_all(directory):
	import os

	os.makedirs(directory, exist_ok=True)
	paths = []
	for name, fn in BUILDERS.items():
		img = fn(name)
		path = os.path.join(directory, f"{name}.png")
		img.filepath_raw = path
		img.file_format = "PNG"
		img.save()
		paths.append(path)
	return paths
