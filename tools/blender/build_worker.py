"""The technician: mesh, rig and the clips the phase-1 task loop needs.

One body, 1.75 m, built from parts that are each bound to a bone (see dclib/rig.py).
Clips map onto what docs/04-workers.md says a worker actually does: walk to a rack,
work standing or crouched, hang a LOTO tag, carry a part, type at the terminal.

Run: blender -b --factory-startup --python tools/blender/build_worker.py
"""

import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy

from dclib import anim, exporter, rig
from dclib.meshkit import Builder, clear_scene, tri_count
from dclib.units import MM

BEV = 6 * MM
CROUCH_DROP = -0.355


def lift(dz):
	"""Hips translation. The bone points up, so world Z is its local Y."""
	return (0.0, dz, 0.0)


def make_body(name="worker"):
	b = Builder()

	b.part("Hips")
	b.box((0.345, 0.215, 0.17), (0, 0, 1.00), "cloth_grey", bevel=14 * MM, segments=2)
	b.part("Spine")
	b.box((0.335, 0.205, 0.14), (0, 0, 1.14), "cloth_navy", bevel=14 * MM, segments=2)
	b.part("Spine1")
	b.box((0.375, 0.215, 0.14), (0, 0, 1.27), "cloth_navy", bevel=14 * MM, segments=2)
	b.part("Spine2")
	b.box((0.415, 0.225, 0.17), (0, 0, 1.385), "cloth_navy", bevel=16 * MM, segments=2)

	# hi-vis vest as front and back panels plus shoulder straps: a single shell box
	# reads as a crate the moment the torso twists
	for sy, panel_y in ((-1, -0.126), (1, 0.126)):
		b.part("Spine1")
		b.box((0.345, 0.026, 0.155), (0, panel_y, 1.240), "hi_vis", bevel=10 * MM)
		b.box((0.318, 0.032, 0.034), (0, panel_y + sy * 0.009, 1.198), "hi_vis_strip",
		      bevel=3 * MM)
		b.part("Spine2")
		b.box((0.375, 0.026, 0.165), (0, panel_y, 1.385), "hi_vis", bevel=10 * MM)
		b.box((0.348, 0.032, 0.034), (0, panel_y + sy * 0.009, 1.328), "hi_vis_strip",
		      bevel=3 * MM)
	b.part("Spine2")
	for sx in (-1, 1):
		b.box((0.030, 0.265, 0.165), (sx * 0.183, 0, 1.385), "hi_vis", bevel=10 * MM)
		b.box((0.080, 0.255, 0.030), (sx * 0.150, 0, 1.462), "hi_vis", bevel=10 * MM)

	b.part("Neck")
	b.cyl(0.052, 0.13, (0, 0, 1.50), "skin", sides=10, bevel=4 * MM)

	b.part("Head")
	b.box((0.168, 0.196, 0.215), (0, 0.006, 1.652), "skin", bevel=34 * MM, segments=4)
	b.box((0.180, 0.190, 0.086), (0, 0.016, 1.739), "hair_dark", bevel=30 * MM, segments=3)
	b.box((0.038, 0.034, 0.042), (0, -0.088, 1.648), "skin", bevel=12 * MM, segments=2)
	for sx in (-1, 1):
		b.box((0.030, 0.014, 0.016), (sx * 0.040, -0.090, 1.690), "plastic_dark",
		      bevel=4 * MM)
		b.box((0.034, 0.012, 0.010), (sx * 0.040, -0.093, 1.706), "hair_dark", bevel=3 * MM)
		b.sphere(0.024, (sx * 0.072, 0.010, 1.660), "skin", segments=8, rings=4,
		         scale=(0.40, 0.9, 1.0))

	for side, sx in (("Left", 1.0), ("Right", -1.0)):
		b.part(f"{side}Shoulder")
		b.sphere(0.076, (sx * 0.178, 0, 1.418), "cloth_navy", segments=10, rings=6)

		b.part(f"{side}Arm")
		b.cone(0.056, 0.066, 0.30, (sx * 0.195, 0, 1.30), "cloth_navy", sides=10)
		b.sphere(0.055, (sx * 0.195, 0, 1.16), "cloth_navy", segments=10, rings=5)

		b.part(f"{side}ForeArm")
		b.cone(0.046, 0.055, 0.25, (sx * 0.195, 0, 1.04), "cloth_navy", sides=10)
		b.sphere(0.047, (sx * 0.195, 0, 0.925), "skin", segments=10, rings=5)

		b.part(f"{side}Hand")
		b.box((0.058, 0.105, 0.130), (sx * 0.195, -0.008, 0.862), "skin", bevel=18 * MM,
		      segments=2)
		b.box((0.052, 0.038, 0.058), (sx * 0.195, -0.048, 0.812), "skin", bevel=16 * MM,
		      segments=2)

		b.part(f"{side}UpLeg")
		b.cone(0.086, 0.104, 0.45, (sx * 0.098, 0, 0.725), "cloth_grey", sides=10)
		b.sphere(0.090, (sx * 0.098, 0, 0.93), "cloth_grey", segments=10, rings=5)

		b.part(f"{side}Leg")
		b.cone(0.064, 0.080, 0.43, (sx * 0.098, 0, 0.305), "cloth_grey", sides=10)
		b.sphere(0.075, (sx * 0.098, 0, 0.505), "cloth_grey", segments=10, rings=5)

		b.part(f"{side}Foot")
		b.box((0.106, 0.150, 0.080), (sx * 0.098, -0.035, 0.062), "boots", bevel=16 * MM,
		      segments=2)
		b.part(f"{side}ToeBase")
		b.box((0.100, 0.125, 0.058), (sx * 0.098, -0.158, 0.033), "boots", bevel=16 * MM,
		      segments=2)

	obj = b.finish(name, smooth_angle=48)
	return obj


HEAD_BONE_Z = 1.56


def make_helmet():
	"""Separate so a role can be swapped without rebuilding the body. The origin sits
	on the Head bone, so a BoneAttachment3D needs no offset."""
	b = Builder()
	z = -HEAD_BONE_Z
	b.sphere(0.115, (0, 0.004, 1.735 + z), "helmet_white", segments=14, rings=7,
	         scale=(1.0, 1.05, 0.82))
	b.box((0.19, 0.075, 0.018), (0, -0.115, 1.706 + z), "helmet_white", bevel=8 * MM,
	      segments=2)
	b.box((0.025, 0.20, 0.028), (0, 0.004, 1.80 + z), "helmet_white", bevel=8 * MM)
	return b.finish("helmet", smooth_angle=48)


# ------------------------------------------------------------------ poses

BREATHE = {"Spine1": (-1.5, 0, 0), "Spine2": (-1.0, 0, 0)}

ARMS_REST = {
	"LeftArm": (3, 0, -6), "RightArm": (3, 0, 6),
	"LeftForeArm": (12, 0, 0), "RightForeArm": (12, 0, 0),
	"LeftShoulder": (0, 0, -2), "RightShoulder": (0, 0, 2),
}


def walk_pose(phase, stride=26.0, arm_swing=22.0, knee_lift=14.0):
	"""phase 0..1 around the cycle; 0 is right-foot contact."""
	a = phase * 2 * math.pi
	swing = math.sin(a)
	opposite = math.sin(a + math.pi)
	knee_r = max(0.0, -math.sin(a - 0.7)) * knee_lift * 2.4
	knee_l = max(0.0, -math.sin(a + math.pi - 0.7)) * knee_lift * 2.4

	return {
		"RightUpLeg": (-stride * swing, 0, 0),
		"LeftUpLeg": (-stride * opposite, 0, 0),
		"RightLeg": (knee_r + 6, 0, 0),
		"LeftLeg": (knee_l + 6, 0, 0),
		"RightFoot": (stride * 0.35 * swing + 6, 0, 0),
		"LeftFoot": (stride * 0.35 * opposite + 6, 0, 0),
		"RightArm": (arm_swing * opposite + 4, 0, 7),
		"LeftArm": (arm_swing * swing + 4, 0, -7),
		"RightForeArm": (16 + 10 * max(0.0, opposite), 0, 0),
		"LeftForeArm": (16 + 10 * max(0.0, swing), 0, 0),
		"Spine": (0, 0, -2.5 * swing),
		"Spine2": (-2, 0, 2.0 * swing),
		"Hips": (2, 0, 3.0 * swing),
		"Neck": (2, 0, 0),
	}


WORK_STAND = anim.merge(ARMS_REST, {
	"Spine": (6, 0, 0), "Spine1": (4, 0, 0), "Spine2": (3, 0, 0),
	"Neck": (10, 0, 0), "Head": (6, 0, 0),
	"LeftShoulder": (-6, 0, -8), "RightShoulder": (-6, 0, 8),
	"LeftArm": (-58, 10, -16), "RightArm": (-58, -10, 16),
	"LeftForeArm": (-64, 0, 22), "RightForeArm": (-64, 0, -22),
	"LeftHand": (10, 0, -8), "RightHand": (10, 0, 8),
})

CROUCH = {
	"Hips": (14, 0, 0),
	"LeftUpLeg": (-92, 4, 0), "RightUpLeg": (-92, -4, 0),
	"LeftLeg": (104, 0, 0), "RightLeg": (104, 0, 0),
	"LeftFoot": (-22, 0, 0), "RightFoot": (-22, 0, 0),
	"Spine": (10, 0, 0), "Spine1": (6, 0, 0), "Spine2": (4, 0, 0),
	"Neck": (12, 0, 0), "Head": (8, 0, 0),
	"LeftShoulder": (-4, 0, -6), "RightShoulder": (-4, 0, 6),
	"LeftArm": (-46, 12, -14), "RightArm": (-46, -12, 14),
	"LeftForeArm": (-52, 0, 20), "RightForeArm": (-52, 0, -20),
}

CARRY = {
	"LeftShoulder": (-4, 0, -6), "RightShoulder": (-4, 0, 6),
	"LeftArm": (-64, 6, -20), "RightArm": (-64, -6, 20),
	"LeftForeArm": (-58, 0, 30), "RightForeArm": (-58, 0, -30),
	"LeftHand": (0, 0, -14), "RightHand": (0, 0, 14),
	"Spine": (-4, 0, 0), "Spine1": (-2, 0, 0),
}

TYPE_BASE = {
	"Spine": (8, 0, 0), "Spine1": (5, 0, 0), "Spine2": (3, 0, 0),
	"Neck": (16, 0, 0), "Head": (10, 0, 0),
	"LeftShoulder": (-2, 0, -4), "RightShoulder": (-2, 0, 4),
	"LeftArm": (-40, 14, -10), "RightArm": (-40, -14, 10),
	"LeftForeArm": (-52, 0, 16), "RightForeArm": (-52, 0, -16),
	"LeftHand": (18, 0, -6), "RightHand": (18, 0, 6),
}


# ------------------------------------------------------------------ clips

def build_clips(arm):
	clips = []

	def clip(name, length, loop=True):
		anim.reset_pose(arm)
		c = anim.Clip(arm, name, length, loop)
		clips.append(c)
		return c

	c = clip("idle", 96)
	base = anim.merge(ARMS_REST, {"Neck": (3, 0, 0)})
	c.key(0, base)
	c.key(28, anim.merge(base, BREATHE, {"Head": (0, 0, 2)}))
	c.key(56, anim.merge(base, {"Spine1": (1, 0, 0), "Head": (1, 0, -3)}))
	c.key(96, base)
	c.finish()

	c = clip("idle_look", 120)
	c.key(0, base)
	c.key(30, anim.merge(base, {"Neck": (2, 0, 26), "Head": (0, 0, 16),
	                            "Spine2": (0, 0, 6)}))
	c.key(56, anim.merge(base, BREATHE))
	c.key(86, anim.merge(base, {"Neck": (4, 0, -22), "Head": (2, 0, -14)}))
	c.key(120, base)
	c.finish()

	for name, length, stride, swing in (("walk", 32, 26.0, 22.0), ("run", 24, 40.0, 38.0)):
		c = clip(name, length)
		steps = 8
		for i in range(steps + 1):
			phase = i / steps
			pose = walk_pose(phase, stride=stride, arm_swing=swing,
			                 knee_lift=14.0 if name == "walk" else 22.0)
			bob = 0.012 if name == "walk" else 0.03
			c.key(round(length * phase), pose,
			      root=lift(-bob * abs(math.sin(phase * 2 * math.pi))))
		c.finish()

	c = clip("carry_idle", 96)
	c.key(0, CARRY)
	c.key(48, anim.merge(CARRY, {"Spine1": (-3, 0, 0), "LeftForeArm": (-56, 0, 30),
	                             "RightForeArm": (-56, 0, -30)}))
	c.key(96, CARRY)
	c.finish()

	c = clip("carry_walk", 32)
	steps = 8
	for i in range(steps + 1):
		phase = i / steps
		legs = {k: v for k, v in walk_pose(phase, stride=22.0).items()
		        if "Leg" in k or "Foot" in k or k == "Hips"}
		c.key(round(32 * phase), anim.merge(CARRY, legs),
		      root=lift(-0.012 * abs(math.sin(phase * 2 * math.pi))))
	c.finish()

	c = clip("work_stand", 110)
	c.key(0, WORK_STAND)
	c.key(22, anim.merge(WORK_STAND, {"RightForeArm": (-78, 0, -26),
	                                  "RightHand": (24, 0, 10), "Spine2": (5, 0, -3)}))
	c.key(46, anim.merge(WORK_STAND, {"LeftForeArm": (-76, 0, 26),
	                                  "RightArm": (-52, -14, 14), "Spine2": (4, 0, 4)}))
	c.key(74, anim.merge(WORK_STAND, {"RightForeArm": (-70, 0, -30), "Head": (10, 0, -6)}))
	c.key(110, WORK_STAND)
	c.finish()

	c = clip("work_crouch", 120)
	c.key(0, CROUCH, root=lift(CROUCH_DROP))
	c.key(30, anim.merge(CROUCH, {"RightForeArm": (-66, 0, -26), "Spine2": (6, 0, -4)}),
	      root=lift(CROUCH_DROP))
	c.key(62, anim.merge(CROUCH, {"LeftForeArm": (-64, 0, 26), "Head": (12, 0, 5)}),
	      root=lift(CROUCH_DROP - 0.01))
	c.key(92, anim.merge(CROUCH, {"RightArm": (-38, -14, 12), "RightForeArm": (-58, 0, -18)}),
	      root=lift(CROUCH_DROP))
	c.key(120, CROUCH, root=lift(CROUCH_DROP))
	c.finish()

	c = clip("crouch_down", 24, loop=False)
	c.key(0, ARMS_REST, root=lift(0.0))
	c.key(14, anim.blend(ARMS_REST, CROUCH, 0.75), root=lift(CROUCH_DROP * 0.7))
	c.key(24, CROUCH, root=lift(CROUCH_DROP))
	c.finish()

	# hanging the tag is a distinct, readable half-second: see docs/04-workers.md
	c = clip("tag_hang", 30, loop=False)
	reach = anim.merge(ARMS_REST, {
		"RightShoulder": (-8, 0, 10), "RightArm": (-76, -16, 22),
		"RightForeArm": (-40, 0, -18), "RightHand": (-14, 0, 14),
		"Spine2": (2, 0, -6), "Neck": (8, 0, -8), "Head": (4, 0, -4),
	})
	c.key(0, ARMS_REST)
	c.key(10, reach)
	c.key(17, anim.merge(reach, {"RightArm": (-70, -16, 20), "RightHand": (-2, 0, 10)}))
	c.key(30, ARMS_REST)
	c.finish()

	c = clip("type", 96)
	c.key(0, TYPE_BASE)
	c.key(12, anim.merge(TYPE_BASE, {"LeftHand": (26, 0, -6), "RightHand": (10, 0, 6)}))
	c.key(26, anim.merge(TYPE_BASE, {"LeftHand": (12, 0, -6), "RightHand": (26, 0, 6)}))
	c.key(44, anim.merge(TYPE_BASE, {"LeftHand": (24, 0, -8), "RightHand": (14, 0, 4),
	                                 "Head": (12, 0, 3)}))
	c.key(70, anim.merge(TYPE_BASE, {"LeftHand": (14, 0, -6), "RightHand": (24, 0, 8)}))
	c.key(96, TYPE_BASE)
	c.finish()

	c = clip("push_cart", 32)
	push = {
		"LeftShoulder": (-6, 0, -8), "RightShoulder": (-6, 0, 8),
		"LeftArm": (-70, 8, -12), "RightArm": (-70, -8, 12),
		"LeftForeArm": (-16, 0, 8), "RightForeArm": (-16, 0, -8),
		"Spine": (10, 0, 0), "Spine1": (5, 0, 0), "Neck": (6, 0, 0),
	}
	for i in range(9):
		phase = i / 8
		legs = {k: v for k, v in walk_pose(phase, stride=20.0).items()
		        if "Leg" in k or "Foot" in k}
		c.key(round(32 * phase), anim.merge(push, legs))
	c.finish()

	anim.reset_pose(arm)
	return clips


def main():
	clear_scene()
	exporter.setup_studio()

	body = make_body()
	helmet = make_helmet()
	armature = rig.build_armature()
	rig.bind(body, armature)

	clips = build_clips(armature)

	bpy.context.scene.frame_set(0)
	path = os.path.join(exporter.MODELS, "characters", "worker.glb")
	_, size = exporter.export_glb([armature, body], path, animations=True)
	hpath = os.path.join(exporter.MODELS, "characters", "helmet.glb")
	_, hsize = exporter.export_glb([helmet], hpath)
	write_clip_manifest(clips, os.path.join(exporter.MODELS, "characters", "worker.clips.json"))

	print()
	print("=== BUILT ===")
	print(f"worker.glb   {tri_count(body):6d} tris  {size / 1024:7.1f} KB  "
	      f"{len(rig.BONES)} bones  {len(clips)} clips")
	print(f"helmet.glb   {tri_count(helmet):6d} tris  {hsize / 1024:7.1f} KB")
	print("clips: " + ", ".join(c.name for c in clips))

	_preview(body, helmet, armature)


def write_clip_manifest(clips, path):
	"""glTF carries no loop flag, so the game would otherwise have to hardcode which
	of the twelve clips cycle. Godot reads this next to the model instead."""
	data = {
		"fps": anim.FPS,
		"clips": {
			c.name: {"loop": c.loop, "frames": max(c.frames), "seconds": round(max(c.frames) / anim.FPS, 3)}
			for c in clips
		},
	}
	with open(path, "w", encoding="utf-8") as fh:
		json.dump(data, fh, indent="	", ensure_ascii=False)
		fh.write("\n")
	return path


def _preview(body, helmet, armature):
	exporter.contact_sheet([body, helmet], os.path.join(exporter.PREVIEWS, "worker.png"),
	                       views=(("front", 90, 4), ("three_q", 42, 12), ("side", 0, 6)))

	shots = [("walk", 8), ("walk", 20), ("work_stand", 22), ("work_crouch", 30),
	         ("carry_idle", 0), ("tag_hang", 14), ("type", 12), ("push_cart", 8)]
	for name, frame in shots:
		track = armature.animation_data.nla_tracks.get(name)
		if track is None:
			continue
		for t in armature.animation_data.nla_tracks:
			t.mute = t.name != name
		bpy.context.scene.frame_set(frame)
		exporter.render_preview([body, helmet],
		                        os.path.join(exporter.PREVIEWS, f"pose_{name}_{frame}.png"),
		                        angle=52, elevation=8, resolution=(560, 760))
	for t in armature.animation_data.nla_tracks:
		t.mute = True


if __name__ == "__main__":
	main()
