"""Humanoid armature and skinning.

Bone names follow the Mixamo skeleton (without the `mixamorig:` prefix) so retargeting
a downloaded clip later is a rename, not a rebuild.

Skinning is deliberately not bone-heat: the body is a union of intersecting boxes and
is not manifold, so heat weighting is unreliable. Each part is bound rigidly to its
bone, then the weights are smoothed — predictable, and it bakes cleanly to VAT for the
L1 crowd described in docs/10-tech-architecture.md.
"""

import bpy
from mathutils import Vector

# name: (head, tail, parent)
SKELETON = [
	("Hips", (0.0, 0.0, 0.98), (0.0, 0.0, 1.07), None),
	("Spine", (0.0, 0.0, 1.07), (0.0, 0.0, 1.20), "Hips"),
	("Spine1", (0.0, 0.0, 1.20), (0.0, 0.0, 1.33), "Spine"),
	("Spine2", (0.0, 0.0, 1.33), (0.0, 0.0, 1.45), "Spine1"),
	("Neck", (0.0, 0.0, 1.45), (0.0, 0.0, 1.56), "Spine2"),
	("Head", (0.0, 0.0, 1.56), (0.0, 0.0, 1.75), "Neck"),
]

for side, sx in (("Left", 1.0), ("Right", -1.0)):
	SKELETON += [
		(f"{side}Shoulder", (sx * 0.04, 0.0, 1.42), (sx * 0.195, 0.0, 1.44), "Spine2"),
		(f"{side}Arm", (sx * 0.195, 0.0, 1.44), (sx * 0.195, 0.0, 1.16), f"{side}Shoulder"),
		(f"{side}ForeArm", (sx * 0.195, 0.0, 1.16), (sx * 0.195, 0.0, 0.92), f"{side}Arm"),
		(f"{side}Hand", (sx * 0.195, 0.0, 0.92), (sx * 0.195, 0.0, 0.76), f"{side}ForeArm"),
		(f"{side}UpLeg", (sx * 0.098, 0.0, 0.94), (sx * 0.098, 0.0, 0.51), "Hips"),
		(f"{side}Leg", (sx * 0.098, 0.0, 0.51), (sx * 0.098, 0.0, 0.10), f"{side}UpLeg"),
		(f"{side}Foot", (sx * 0.098, 0.0, 0.10), (sx * 0.098, -0.13, 0.025), f"{side}Leg"),
		(f"{side}ToeBase", (sx * 0.098, -0.13, 0.025), (sx * 0.098, -0.24, 0.025),
		 f"{side}Foot"),
	]

BONES = [b[0] for b in SKELETON]


def build_armature(name="worker_rig"):
	arm = bpy.data.armatures.new(name)
	obj = bpy.data.objects.new(name, arm)
	bpy.context.scene.collection.objects.link(obj)

	bpy.context.view_layer.objects.active = obj
	bpy.ops.object.mode_set(mode="EDIT")
	for bone_name, head, tail, parent in SKELETON:
		eb = arm.edit_bones.new(bone_name)
		eb.head = Vector(head)
		eb.tail = Vector(tail)
		eb.roll = 0.0
		if parent:
			eb.parent = arm.edit_bones[parent]
	bpy.ops.object.mode_set(mode="OBJECT")
	return obj


def bind(mesh_obj, arm_obj, smooth_repeat=6, smooth_factor=0.6):
	"""The mesh already carries rigid per-bone weights from Builder.part(); relax them."""
	mod = mesh_obj.modifiers.new("Armature", "ARMATURE")
	mod.object = arm_obj
	mesh_obj.parent = arm_obj

	bpy.ops.object.select_all(action="DESELECT")
	mesh_obj.select_set(True)
	bpy.context.view_layer.objects.active = mesh_obj
	bpy.ops.object.mode_set(mode="EDIT")
	bpy.ops.mesh.select_all(action="SELECT")
	bpy.ops.object.vertex_group_smooth(group_select_mode="ALL", factor=smooth_factor,
	                                   repeat=smooth_repeat, expand=0.0)
	bpy.ops.object.mode_set(mode="OBJECT")
	return mod
