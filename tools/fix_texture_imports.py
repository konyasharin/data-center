"""Force lossless, unfiltered, mip-free import for the atlas and detail maps.

Godot's defaults are built for photographic textures: VRAM block compression plus
mipmaps. On a 16x16 palette where each texel is a whole material that is fatal —
block compression bleeds neighbouring texels together and the mip chain averages the
entire palette into one colour, so skin comes out violet. Detail maps are alpha
cut-outs and lose their holes the same way.

	python tools/fix_texture_imports.py

Run it after a fresh import; it rewrites the [params] block of the .import files,
which are tracked in git.
"""

import os
import sys

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
TARGETS = [
	(os.path.join(REPO, "assets", "palettes"), {
		"compress/mode": "0",
		"compress/hdr_compression": "0",
		"mipmaps/generate": "false",
		"detect_3d/compress_to": "0",
		"process/fix_alpha_border": "false",
	}),
	(os.path.join(REPO, "assets", "textures"), {
		"compress/mode": "0",
		"mipmaps/generate": "true",
		"detect_3d/compress_to": "0",
		"process/fix_alpha_border": "false",
	}),
]


def patch(path, wanted):
	with open(path, encoding="utf-8") as fh:
		lines = fh.read().splitlines()

	out = []
	in_params = False
	seen = set()
	changed = False
	for line in lines:
		if line.startswith("["):
			if in_params and line != "[params]":
				for key in wanted:
					if key not in seen:
						out.append(f"{key}={wanted[key]}")
						changed = True
			in_params = line.strip() == "[params]"
		elif in_params and "=" in line:
			key = line.split("=", 1)[0].strip()
			if key in wanted:
				seen.add(key)
				new = f"{key}={wanted[key]}"
				if new != line:
					changed = True
				out.append(new)
				continue
		out.append(line)

	if in_params:
		for key in wanted:
			if key not in seen:
				out.append(f"{key}={wanted[key]}")
				changed = True

	if changed:
		with open(path, "w", encoding="utf-8") as fh:
			fh.write("\n".join(out) + "\n")
	return changed


def main():
	touched = []
	for directory, wanted in TARGETS:
		if not os.path.isdir(directory):
			continue
		for name in sorted(os.listdir(directory)):
			if name.endswith(".png.import"):
				path = os.path.join(directory, name)
				if patch(path, wanted):
					touched.append(os.path.relpath(path, REPO))

	if not touched:
		print("import settings already correct")
		return 0
	print("patched:")
	for path in touched:
		print("  " + path)
	print("\nre-run the Godot import so the changes take effect:")
	print("  godot --headless --import --quit")
	return 0


if __name__ == "__main__":
	sys.exit(main())
