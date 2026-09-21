"""Keyframed clips for the worker rig.

Poses are written as {bone: (rx, ry, rz)} in degrees, local to the bone. Every clip
gets its own NLA track, which is what the glTF exporter turns into separate Godot
animations.
"""

import math

import bpy

FPS = 24


def iter_fcurves(action):
	"""Blender 4.4+ moved fcurves into layers/strips/channelbags; older builds keep
	the flat collection."""
	for layer in getattr(action, "layers", ()):
		for strip in layer.strips:
			for bag in strip.channelbags:
				yield from bag.fcurves
	if not hasattr(action, "layers"):
		yield from action.fcurves


class Clip:
	def __init__(self, arm_obj, name, length, loop=True):
		self.arm = arm_obj
		self.name = name
		self.length = length
		self.loop = loop
		self.frames = []

		if arm_obj.animation_data is None:
			arm_obj.animation_data_create()
		self.action = bpy.data.actions.new(name)
		self.action.use_fake_user = True
		arm_obj.animation_data.action = self.action
		for pb in arm_obj.pose.bones:
			pb.rotation_mode = "XYZ"

	def key(self, frame, poses, root=(0.0, 0.0, 0.0)):
		"""Every bone is keyed on every clip. A channel a clip omits is not neutral —
		it keeps whatever the previously played clip left there."""
		for pb in self.arm.pose.bones:
			rot = poses.get(pb.name, (0.0, 0.0, 0.0))
			pb.rotation_euler = [math.radians(a) for a in rot]
			pb.keyframe_insert("rotation_euler", frame=frame)
		hips = self.arm.pose.bones["Hips"]
		hips.location = root
		hips.keyframe_insert("location", frame=frame)
		self.frames.append(frame)

	def hold(self, frames, poses, root=(0.0, 0.0, 0.0)):
		for f in frames:
			self.key(f, poses, root)

	def finish(self, interpolation="BEZIER"):
		curves = 0
		for fc in iter_fcurves(self.action):
			curves += 1
			for kp in fc.keyframe_points:
				kp.interpolation = interpolation
		assert curves, f"{self.name}: no fcurves found — action layout changed"
		track = self.arm.animation_data.nla_tracks.new()
		track.name = self.name
		strip = track.strips.new(self.name, 0, self.action)
		strip.name = self.name
		track.mute = True  # stacked live tracks would blend every clip at once
		self.arm.animation_data.action = None
		return self.action


def reset_pose(arm_obj):
	for pb in arm_obj.pose.bones:
		pb.rotation_mode = "XYZ"
		pb.rotation_euler = (0, 0, 0)
		pb.location = (0, 0, 0)


def mirror(poses):
	"""Swap Left/Right bones and flip the axes that cross the body midline."""
	out = {}
	for name, (rx, ry, rz) in poses.items():
		if name.startswith("Left"):
			target = "Right" + name[4:]
		elif name.startswith("Right"):
			target = "Left" + name[5:]
		else:
			target = name
		out[target] = (rx, -ry, -rz)
	return out


def blend(a, b, t):
	keys = set(a) | set(b)
	out = {}
	for k in keys:
		va, vb = a.get(k, (0, 0, 0)), b.get(k, (0, 0, 0))
		out[k] = tuple(va[i] + (vb[i] - va[i]) * t for i in range(3))
	return out


def merge(*poses):
	out = {}
	for p in poses:
		out.update(p)
	return out
