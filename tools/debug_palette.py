"""Swap the palette for hue-coded slots, to identify what a pixel actually is.

When an artefact shows up in the engine, the hard part is naming the part that
causes it: every chassis surface is a grey rectangle. This writes a palette where
slot N gets its own hue, so one screenshot answers the question. Rebuild the assets
(`build_all.py`) to restore the real colours.

	python tools/debug_palette.py          # write hue palette + print the legend
"""

import colorsys
import os
import struct
import sys
import zlib

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(REPO, "tools", "blender"))

from dclib.palette import ATLAS, SLOTS  # noqa: E402 - needs the path above

TARGET = os.path.join(REPO, "assets", "palettes", "dc_atlas_albedo.png")
# golden-ratio step: consecutive slots land far apart on the wheel, so a hue read
# back from a screenshot cannot be confused with its neighbour
HUE_STEP = 0.61803399


def _chunk(tag, data):
	return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data))


def main():
	rows = []
	for row in range(ATLAS):
		line = bytearray()
		for col in range(ATLAS):
			i = row * ATLAS + col
			rgb = colorsys.hsv_to_rgb((i * HUE_STEP) % 1.0, 0.95, 1.0) if i < len(SLOTS) \
				else (0.0, 0.0, 0.0)
			line += bytes(int(c * 255) for c in rgb) + b"\xff"
		rows.append(bytes(line))

	# Blender writes the atlas bottom-up, so slot 0 lives on the last PNG row
	raw = b"".join(b"\x00" + rows[ATLAS - 1 - y] for y in range(ATLAS))
	png = (b"\x89PNG\r\n\x1a\n"
	       + _chunk(b"IHDR", struct.pack(">IIBBBBB", ATLAS, ATLAS, 8, 6, 0, 0, 0))
	       + _chunk(b"IDAT", zlib.compress(raw))
	       + _chunk(b"IEND", b""))
	with open(TARGET, "wb") as fh:
		fh.write(png)

	print(f"wrote {os.path.relpath(TARGET, REPO)} — rebuild assets to restore\n")
	for i, slot in enumerate(SLOTS):
		r, g, b = colorsys.hsv_to_rgb((i * HUE_STEP) % 1.0, 0.95, 1.0)
		print(f"{i:3d}  {slot[0]:16s} rgb({int(r * 255):3d},{int(g * 255):3d},{int(b * 255):3d})")
	return 0


if __name__ == "__main__":
	sys.exit(main())
