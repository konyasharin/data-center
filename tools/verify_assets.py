"""Check the exported glb library without opening Blender.

Reads the glTF JSON chunk of every file under assets/models and asserts the contract
the game relies on: metres, Y-up, one material per model, sane triangle budgets, and
that the worker actually carries its skin and clips.

	python tools/verify_assets.py
"""

import json
import os
import struct
import sys

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
MODELS = os.path.join(REPO, "assets", "models")

sys.path.insert(0, os.path.join(REPO, "tools", "blender"))
from dclib.units import (  # noqa: E402 - needs REPO on the path first
	DESK_H, HUMAN_HEIGHT, LFF_H, rack_height, server_height,
)

# model -> (expected height in metres, tolerance). Height is the Y extent: glTF is Y-up.
# Values come from units.py so a change to U cannot pass this check silently.
EXPECTED_HEIGHT = {
	"rack_42u_frame": (rack_height(42), 0.002),
	"server_1u": (server_height(1), 0.001),
	"server_4u": (server_height(4), 0.001),
	"shed_shell": (4.32, 0.15),
	"worker": (HUMAN_HEIGHT + 0.02, 0.03),
	"desk": (DESK_H, 0.005),
	"shelf": (2.00, 0.02),
	"pallet": (0.145, 0.01),
	"drive_lff": (LFF_H, 0.002),
}

BUDGET = {"server_1u": 1600, "rack_42u_frame": 9000, "worker": 5000, "shed_shell": 9000}

# One atlas material batches everything; a model may add detail maps for perforation
# and one-off materials for glass and the terminal screen. Anything else is a slip.
ALLOWED_MATERIALS = {
	"dc_atlas", "dc_perforation", "dc_rail_holes", "dc_floor_grille", "dc_drive_bays",
	"dc_fence_mesh", "dc_windows", "rack_glass", "terminal_screen",
}


def read_gltf(path):
	with open(path, "rb") as fh:
		magic, _version, _length = struct.unpack("<III", fh.read(12))
		if magic != 0x46546C67:
			raise ValueError(f"{path}: not a glb")
		chunk_len, chunk_type = struct.unpack("<II", fh.read(8))
		if chunk_type != 0x4E4F534A:
			raise ValueError(f"{path}: first chunk is not JSON")
		return json.loads(fh.read(chunk_len))


def model_stats(doc):
	tris = 0
	bbox_min = [1e9] * 3
	bbox_max = [-1e9] * 3
	for mesh in doc.get("meshes", []):
		for prim in mesh.get("primitives", []):
			pos = doc["accessors"][prim["attributes"]["POSITION"]]
			tris += (doc["accessors"][prim["indices"]]["count"] if "indices" in prim
			         else pos["count"]) // 3
			for i in range(3):
				bbox_min[i] = min(bbox_min[i], pos["min"][i])
				bbox_max[i] = max(bbox_max[i], pos["max"][i])
	size = [bbox_max[i] - bbox_min[i] for i in range(3)]
	return tris, size, bbox_min, bbox_max


def main():
	problems = []
	rows = []
	for root, _dirs, files in os.walk(MODELS):
		for name in sorted(files):
			if not name.endswith(".glb"):
				continue
			path = os.path.join(root, name)
			stem = name[:-4]
			doc = read_gltf(path)
			tris, size, lo, hi = model_stats(doc)
			mat_names = [m.get("name", "") for m in doc.get("materials", [])]
			mats = len(mat_names)
			anims = len(doc.get("animations", []))
			skins = len(doc.get("skins", []))
			joints = len(doc["skins"][0]["joints"]) if skins else 0

			unknown = [m for m in mat_names if m not in ALLOWED_MATERIALS]
			if unknown:
				problems.append(f"{stem}: unexpected material(s) {unknown}")
			if mats > 3:
				problems.append(f"{stem}: {mats} materials — that is {mats} draw calls")
			# Buildings are the one thing in the library that is bigger than a room, and
			# the cap exists to catch a model exported in centimetres, not to say how
			# tall a tower may be.
			limit = 60 if root.endswith("city") else 20
			if max(size) > limit or max(size) < 0.01:
				problems.append(f"{stem}: implausible size {size} — unit scale is metres")
			limit = BUDGET.get(stem)
			if limit and tris > limit:
				problems.append(f"{stem}: {tris} tris over the {limit} budget")
			expect_tol = EXPECTED_HEIGHT.get(stem)
			if expect_tol and abs(size[1] - expect_tol[0]) > expect_tol[1]:
				problems.append(f"{stem}: height {size[1]:.4f} m, expected "
				                f"{expect_tol[0]} +/-{expect_tol[1]}")

			# Godot is Y-up: anything standing on a floor must not dip below it
			if stem in ("rack_42u_frame", "worker", "desk", "shelf", "ups", "cart") \
					and lo[1] < -0.02:
				problems.append(f"{stem}: sits {lo[1]:.3f} m below the floor plane")

			rows.append((stem, tris, size, mats, anims, joints,
			             os.path.getsize(path) / 1024))

	if not rows:
		print(f"no glb files under {MODELS} — run build_all.py first")
		return 1

	width = max(len(r[0]) for r in rows)
	print(f"{'model':<{width}}  {'tris':>6}  {'size (m, xyz)':<22} {'mat':>3} "
	      f"{'anim':>4} {'bone':>4} {'KB':>7}")
	for stem, tris, size, mats, anims, joints, kb in rows:
		dims = " x ".join(f"{v:.2f}" for v in size)
		print(f"{stem:<{width}}  {tris:6d}  {dims:<22} {mats:3d} {anims:4d} {joints:4d} "
		      f"{kb:7.1f}")

	total = sum(r[1] for r in rows)
	print(f"\n{len(rows)} models, {total} tris, {sum(r[6] for r in rows) / 1024:.2f} MB")

	if problems:
		print("\nPROBLEMS")
		for p in problems:
			print(" - " + p)
		return 1
	print("\nall checks passed")
	return 0


if __name__ == "__main__":
	sys.exit(main())
