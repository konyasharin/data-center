"""Rebuild the whole asset library from source.

	blender -b --factory-startup --python tools/blender/build_all.py

Each builder runs in a fresh scene inside one Blender process. Models land in
assets/models/, preview renders in assets/previews/, palette maps in assets/palettes/.
"""

import importlib
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy

from dclib import exporter, palette, textures

BUILDERS = ["build_rack", "build_shed", "build_room", "build_props", "build_worker",
            "build_city", "build_delivery"]


def main():
	started = time.time()
	for name in BUILDERS:
		print(f"\n########## {name} ##########")
		importlib.import_module(name).main()

	bpy.ops.wm.read_factory_settings(use_empty=True)
	paths = palette.save_images(os.path.join(exporter.REPO, "assets", "palettes"))
	paths += textures.save_all(os.path.join(exporter.REPO, "assets", "textures"))
	print("\nmaps: " + ", ".join(os.path.basename(p) for p in paths))

	total = 0
	count = 0
	for root, _dirs, files in os.walk(exporter.MODELS):
		for f in files:
			if f.endswith(".glb"):
				total += os.path.getsize(os.path.join(root, f))
				count += 1
	print(f"\n{count} glb files, {total / 1024 / 1024:.2f} MB, "
	      f"built in {time.time() - started:.1f}s")


if __name__ == "__main__":
	main()
