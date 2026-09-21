"""glTF export tuned for Godot, plus turntable previews so models can be eyeballed."""

import math
import os

import bpy
from mathutils import Vector

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
MODELS = os.path.join(REPO, "assets", "models")
PREVIEWS = os.path.join(REPO, "assets", "previews")


def export_glb(objects, path, animations=False):
	os.makedirs(os.path.dirname(path), exist_ok=True)
	bpy.ops.object.select_all(action="DESELECT")
	for o in objects:
		o.select_set(True)
	bpy.context.view_layer.objects.active = objects[0]
	bpy.ops.export_scene.gltf(
		filepath=path,
		export_format="GLB",
		use_selection=True,
		export_apply=True,
		export_yup=True,
		export_animations=animations,
		export_animation_mode="ACTIONS" if animations else "ACTIONS",
		export_bake_animation=animations,
		export_optimize_animation_size=False,
		export_image_format="NONE",  # the atlas is one shared Godot material, not 39 copies
		export_tangents=False,
		export_normals=True,
		export_extras=True,
	)
	return path, os.path.getsize(path)


def _set_engine():
	scene = bpy.context.scene
	for name in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE", "BLENDER_WORKBENCH"):
		try:
			scene.render.engine = name
			return name
		except TypeError:
			continue
	return scene.render.engine


def setup_studio(world_strength=1.2):
	scene = bpy.context.scene
	engine = _set_engine()

	world = bpy.data.worlds.get("studio") or bpy.data.worlds.new("studio")
	world.use_nodes = True
	bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
	bg.inputs[0].default_value = (0.16, 0.17, 0.19, 1.0)
	bg.inputs[1].default_value = world_strength
	scene.world = world

	for name, direction, energy in RIG:
		light = bpy.data.lights.new(name, "AREA")
		light.energy = energy
		obj = bpy.data.objects.new(name, light)
		obj.location = Vector(direction) * 3
		scene.collection.objects.link(obj)
		_aim(obj, Vector((0, 0, 0)))
	return engine


# direction (normalised-ish), relative energy — placed per subject in render_preview
RIG = (
	("key", (1.0, -1.15, 1.1), 55.0),
	("fill", (-1.2, -0.75, 0.6), 18.0),
	("rim", (-0.5, 1.3, 1.0), 30.0),
)


def _place_lights(centre, radius):
	for name, direction, energy in RIG:
		obj = bpy.data.objects.get(name)
		if obj is None:
			continue
		d = Vector(direction)
		obj.location = centre + d.normalized() * radius * 3.0
		obj.data.size = radius * 0.9
		obj.data.energy = energy * (radius * 3.0) ** 2
		_aim(obj, centre)


def _aim(obj, target):
	direction = target - obj.location
	obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def render_preview(objects, path, angle=42.0, elevation=22.0, margin=1.22,
                   resolution=(900, 760), samples=24, isolate=True, ortho=False):
	scene = bpy.context.scene

	hidden = []
	if isolate:
		keep = set(objects)
		for o in scene.objects:
			if o.type == "MESH" and o not in keep and not o.hide_render:
				o.hide_render = True
				hidden.append(o)
	scene.render.resolution_x, scene.render.resolution_y = resolution
	scene.render.film_transparent = False
	try:
		scene.eevee.taa_render_samples = samples
	except AttributeError:
		pass

	bpy.context.view_layer.update()  # matrix_world is stale until the depsgraph ticks
	corners = [o.matrix_world @ Vector(c) for o in objects for c in o.bound_box]
	lo = Vector((min(c[i] for c in corners) for i in range(3)))
	hi = Vector((max(c[i] for c in corners) for i in range(3)))
	centre = (lo + hi) / 2
	radius = max((hi - lo).length / 2, 0.05)

	cam_data = bpy.data.cameras.get("preview_cam") or bpy.data.cameras.new("preview_cam")
	cam_data.lens = 50
	cam = bpy.data.objects.get("preview_cam")
	if cam is None:
		cam = bpy.data.objects.new("preview_cam", cam_data)
		scene.collection.objects.link(cam)
	scene.camera = cam

	a, e = math.radians(angle), math.radians(elevation)
	offset = Vector((math.cos(a) * math.cos(e), -math.sin(a) * math.cos(e), math.sin(e)))

	# frame on the silhouette, not on the bbox diagonal: a 1U chassis is 0.04 m tall
	# and 0.75 m deep, and diagonal framing renders it as a speck
	view = -offset.normalized()
	right = view.cross(Vector((0, 0, 1)))
	right = right.normalized() if right.length > 1e-6 else Vector((1, 0, 0))
	up = right.cross(view).normalized()
	rel = [c - centre for c in corners]
	half_w = max(abs(v.dot(right)) for v in rel)
	half_u = max(abs(v.dot(up)) for v in rel)
	half_d = max(abs(v.dot(view)) for v in rel)

	if ortho:
		cam_data.type = "ORTHO"
		aspect = resolution[0] / resolution[1]
		cam_data.ortho_scale = max(half_w * 2, half_u * 2 * aspect) * margin
		d = half_d + radius * 3
	else:
		cam_data.type = "PERSP"
		half_h = cam_data.angle / 2
		half_v = math.atan(math.tan(half_h) * resolution[1] / resolution[0])
		d = half_d + margin * max(half_w / math.tan(half_h), half_u / math.tan(half_v))

	cam.location = centre + offset * d
	_aim(cam, centre)
	_place_lights(centre, radius)

	os.makedirs(os.path.dirname(path), exist_ok=True)
	scene.render.filepath = path
	scene.render.image_settings.file_format = "PNG"
	bpy.ops.render.render(write_still=True)

	for o in hidden:
		o.hide_render = False
	return path


def contact_sheet(objects, path, views=(("front", 90, 8), ("three_q", 42, 22), ("top", 42, 62)),
                  **kwargs):
	out = []
	base, ext = os.path.splitext(path)
	for name, angle, elevation in views:
		out.append(render_preview(objects, f"{base}_{name}{ext}", angle=angle,
		                          elevation=elevation, **kwargs))
	return out


def render_eye(objects, path, eye, target, resolution=(1100, 720), samples=32, lens=24,
               isolate=True):
	"""First-person view from inside a shell — the angle the game is actually played at."""
	scene = bpy.context.scene

	hidden = []
	if isolate:
		keep = set(objects)
		for o in scene.objects:
			if o.type == "MESH" and o not in keep and not o.hide_render:
				o.hide_render = True
				hidden.append(o)

	scene.render.resolution_x, scene.render.resolution_y = resolution
	try:
		scene.eevee.taa_render_samples = samples
	except AttributeError:
		pass

	cam_data = bpy.data.cameras.get("preview_cam") or bpy.data.cameras.new("preview_cam")
	cam_data.type = "PERSP"
	cam_data.lens = lens
	cam = bpy.data.objects.get("preview_cam")
	if cam is None:
		cam = bpy.data.objects.new("preview_cam", cam_data)
		scene.collection.objects.link(cam)
	scene.camera = cam
	bpy.context.view_layer.update()
	cam.location = Vector(eye)
	_aim(cam, Vector(target))

	_place_lights(Vector(target), 3.0)

	os.makedirs(os.path.dirname(path), exist_ok=True)
	scene.render.filepath = path
	scene.render.image_settings.file_format = "PNG"
	bpy.ops.render.render(write_still=True)

	for o in hidden:
		o.hide_render = False
	return path
