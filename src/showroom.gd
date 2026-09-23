extends Node3D

## Test scene: every built model, placed the way it would be used.
##
## Three zones — a hall on a raised floor, the phase-1 shed, and a catalogue row of
## everything else with labels. Nothing here is game code: it exists so the asset
## library can be judged in the engine's lighting instead of a Blender preview.
##
## Servers go through a MultiMesh rather than one node each, because that is the
## rule the whole project is built on (CLAUDE.md, rule 1) and a hall of racks is
## exactly where a node-per-entity approach would already hurt.

const TILE := 0.6
const PLENUM := 0.45
const RACK_W := 0.6
const RACK_D := 1.07
const RACK_H := 1.957
const U := 0.04445
const PLINTH := 0.05

# Models are authored with -Y as the front (docs/14-art-assets.md). The glTF export
# maps Blender -Y to +Z, so in Godot a rack's front face is at +Z and a chassis body
# runs from its origin toward -Z. Getting this backwards parks every server outside
# the cabinet, which is exactly what happened.
const RACK_FRONT_Z := RACK_D / 2
# Chassis ears land on the front face of the mounting rail (rail centre is 90 mm in,
# 18 mm thick), so the bezel sits 81 mm behind the cabinet face rather than inside
# the rail, which was leaving the ears buried in the steel.
const CHASSIS_INSET := 0.081

const SHED_RACK := 100              # rack ids for the shed, out of reach of the hall
# Rear channel, looking at the back of a cabinet. The outer 40 mm of each side is
# taken: mounting rails at x = +-0.25 and 60 mm corner posts from x = +-0.237 back to
# the door. So both the duct and the strip live inboard of that, with the server
# sockets at x = +-0.142 between them and nothing hiding anything else.
const STRIP_X := 0.175
const SPINE_X := 0.105
const CHANNEL_Z := -0.44

const HALL := Vector2i(20, 14)      # floor tiles
const LOD_SWITCH := 9.0              # metres: detailed chassis inside, lod1 beyond
const SHED_ORIGIN := Vector3(0, 0, 16.0)
const SHED_SPOTS := 5           # marked places for cabinets along the shed wall
const NAV_SOURCE := "nav_source"

var _label_font: Font
var _cabling := CablingBridge.new()
var _estate := EstateBridge.new()
var _laptop: Laptop
var _crew: Crew
var _racking: Racking
# Racks in the shed that have room left, and the floor spots a bought cabinet stands
# on. Both are what the shop offers and what a worker is sent to.
var _bays: Array[Dictionary] = []
var _spots: Array[Dictionary] = []
var _tags := {}                     # job -> the sign standing over it while it runs
var _doing := {}                    # job -> how far the work has physically got
var _doors: Array[Dictionary] = []
var _wiring: Wiring
var _hud_label: Label


func _ready() -> void:
	_environment()
	_wiring = Wiring.new()
	_wiring.attach(_cabling)
	add_child(_wiring)
	_hall()
	_shed()
	_wiring.build()
	_prewire()
	_catalogue()
	_navigation()
	_shift()
	_hud()

	if "--matte" in OS.get_cmdline_user_args():
		_matte()

	if "--stats" in OS.get_cmdline_user_args():
		_stats()

	if "--flicker" in OS.get_cmdline_user_args():
		_flicker()
		return

	if "--shots" in OS.get_cmdline_user_args():
		if "--pattern" in OS.get_cmdline_user_args():
			_wiring.check_pattern()
		_shoot()
		return

	if "--pattern" in OS.get_cmdline_user_args():
		_wiring.check_pattern()
		get_tree().quit()
		return

	if "--order" in OS.get_cmdline_user_args():
		# one of each, left for the crew to walk over and do: what the laptop would
		# have queued, without a hand on the mouse
		for kind in [1, 0]:
			var spots := free_spots(kind)
			if spots.is_empty():
				print("заказано %d: ставить некуда" % kind)
				continue
			print("заказано %d -> работа %d, место %s"
				% [kind, order(kind, spots[0]["place"], spots[0]["slot"]),
					spots[0]["label"]])
		_watch_bays()
		_check_nav()

	if "--pair" in OS.get_cmdline_user_args():
		# only a cabinet, so both of them are free to go to it: moving one is the work
		# that takes two, and nothing else shows that the second one joins
		var spots := free_spots(1)
		if not spots.is_empty():
			var job := order(1, spots[0]["place"], spots[0]["slot"])
			print("заказан шкаф -> работа %d" % job)
			_watch_pair(job)

	if "--crowd" in OS.get_cmdline_user_args():
		_watch_crowd()

	if "--crewshot" in OS.get_cmdline_user_args():
		_shoot_crew()

	if "--shop" in OS.get_cmdline_user_args():
		_check_shop()
		get_tree().quit()
		return

	if "--fitpattern" in OS.get_cmdline_user_args():
		_wiring.check_fit()
		get_tree().quit()
		return

	if "--learn" in OS.get_cmdline_user_args():
		# what the algorithm produces, written down in the same form as a hand-made
		# pattern: the baseline the two are compared against, and it overwrites a
		# saved one on purpose
		_wiring.learn(_wiring.racks()[0])
		get_tree().quit()
		return

	var player := ShowroomPlayer.new()
	player.position = Vector3(3.4, PLENUM + 0.1, 0.0)
	add_child(player)
	if _laptop != null:
		_laptop.attach_player(player)
	_racking = Racking.new()
	add_child(_racking)
	_racking.setup(_wiring, self, _bays, player.eye())

	if "--laptop" in OS.get_cmdline_user_args():
		_check_laptop(player)

	if "--rack" in OS.get_cmdline_user_args():
		_check_racking(player)


const SHOTS := [
	["hall_aisle", Vector3(3.2, 1.62, 0.0), Vector3(-2.0, 1.35, 0.0)],
	["hall_rack_open", Vector3(2.9, 1.70, 0.2), Vector3(-1.1, 1.20, -0.9)],
	["hall_wide", Vector3(4.2, 2.35, 3.3), Vector3(-1.0, 1.10, -0.6)],
	["hall_floor", Vector3(1.8, 0.95, 0.6), Vector3(-1.2, 0.48, 0.0)],
	["hall_rear", Vector3(3.0, 1.60, -3.2), Vector3(-2.0, 1.30, -2.3)],
	["rack_face", Vector3(-0.15, 2.05, 0.95), Vector3(-0.95, 1.35, -0.35)],
	["open_rack_top", Vector3(-0.95, 2.05, 0.05), Vector3(-0.90, 1.20, -1.05)],
	["front_detail", Vector3(-0.60, 1.35, 0.20), Vector3(-0.90, 1.28, -1.00)],
	["rear_close", Vector3(-0.30, 1.55, -2.55), Vector3(-1.10, 1.30, -1.95)],
	["rear_angle", Vector3(0.90, 1.70, -2.90), Vector3(-1.20, 1.25, -2.05)],
	["duct_open", Vector3(-1.75, 1.45, -2.30), Vector3(-1.78, 1.30, -1.60)],
	["duct_edge", Vector3(-2.05, 1.30, -2.62), Vector3(-2.15, 1.24, -1.95)],
	["clip_macro", Vector3(-2.19, 1.16, -2.28), Vector3(-2.21, 1.17, -1.94)],
	["port_macro", Vector3(-1.900, 1.075, -2.360), Vector3(-1.965, 1.056, -2.247)],
	["panel_macro", Vector3(-2.107, 2.30, -2.38), Vector3(-2.107, 2.28, -2.05)],
	["plug_macro", Vector3(-1.944, 1.068, -2.316), Vector3(-1.965, 1.0556, -2.250)],
	["lod_near", Vector3(0.55, 1.45, -0.35), Vector3(-0.30, 1.30, -1.00)],
	["lod_band", Vector3(2.60, 1.60, 1.90), Vector3(-0.60, 1.25, -0.90)],
	["lod_far", Vector3(4.60, 1.70, 3.40), Vector3(-1.00, 1.20, -1.10)],
	["rack_row", Vector3(5.2, 1.55, 0.2), Vector3(-2.0, 1.20, -0.4)],
	["shed_inside", Vector3(2.6, 1.65, 18.4), Vector3(-1.6, 1.2, 16.4)],
	["shed_terminal", Vector3(2.9, 1.45, 16.4), Vector3(2.0, 0.85, 17.2)],
	["catalogue", Vector3(-4.2, 2.1, -5.6), Vector3(-6.6, 0.95, -8.6)],
	["worker", Vector3(0.9, 1.5, 1.4), Vector3(-0.2, 1.05, 0.2)],
]


func _flicker() -> void:
	## Hold the camera dead still and save consecutive frames. Anything that differs
	## between them is temporal — TAA, dithered LOD, shadow noise — not geometry.
	var camera := Camera3D.new()
	camera.fov = 70
	camera.far = 300
	add_child(camera)
	camera.make_current()
	camera.position = Vector3(-0.15, 2.05, 0.95)
	camera.look_at(Vector3(-0.95, 1.35, -0.35), Vector3.UP)

	var args := OS.get_cmdline_user_args()
	if "--notaa" in args:
		get_viewport().use_taa = false
	if "--nofade" in args:
		for node in _walk(self):
			if node is GeometryInstance3D:
				node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	if "--nolod" in args:
		# keep only the detailed mesh: zeroing both thresholds would show the LOD mesh
		# as well, which is exactly the overlap being investigated
		for node in _walk(self):
			if node is GeometryInstance3D:
				if node.visibility_range_begin > 0.0:
					node.visible = false
				node.visibility_range_end = 0.0
	if "--noalpha" in args:
		for key in ["dc_perforation", "dc_rail_holes", "dc_floor_grille"]:
			var m: StandardMaterial3D = Assets.material(key)
			m.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_OFF
	if "--probe" in args:
		# same mesh as a plain MeshInstance3D, right in front of the camera: if the
		# drive-bay surface shows here but not in the MultiMesh rows, the MultiMesh
		# is the reason
		var probe := Assets.instance("hardware/server_1u")
		probe.position = Vector3(-0.35, 1.72, 0.55)
		probe.rotation.y = PI
		probe.scale = Vector3(1.6, 1.6, 1.6)
		add_child(probe)
	if "--nodetail" in args:
		# flag every detail-map surface so it is unmistakable on screen
		var seen: Dictionary = {}
		var flagged := 0
		for node in _walk(self):
			var m: Mesh = null
			if node is MeshInstance3D:
				m = node.mesh
			elif node is MultiMeshInstance3D:
				m = node.multimesh.mesh
			if m == null or seen.has(m):
				continue
			seen[m] = true
			for i in range(1, m.get_surface_count()):
				m.surface_set_material(i, _flag_material())
				flagged += 1
		print("flagged detail surfaces: ", flagged, " on ", seen.size(), " meshes")
	if "--noshadow" in args:
		for node in _walk(self):
			if node is Light3D:
				node.shadow_enabled = false
	if "--nossao" in args:
		for node in _walk(self):
			if node is WorldEnvironment:
				node.environment.ssao_enabled = false
	if "--nopeople" in args:
		for node in _walk(self):
			if node is AnimationPlayer:
				node.stop()

	var dir := "user://flicker"
	DirAccess.make_dir_recursive_absolute(dir)
	for i in 30:
		await RenderingServer.frame_post_draw
	for i in 6:
		for j in 2:
			await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/f%d.png" % [dir, i])
	print("flicker variant done")
	print("flicker frames: ", ProjectSettings.globalize_path(dir))
	get_tree().quit()


func _shoot() -> void:
	var args := OS.get_cmdline_user_args()
	if "--probe" in args:
		# same mesh as a plain MeshInstance3D, right in front of the camera: if the
		# drive-bay surface shows here but not in the MultiMesh rows, the MultiMesh
		# is the reason
		var probe := Assets.instance("hardware/server_1u")
		probe.position = Vector3(-0.35, 1.72, 0.55)
		probe.rotation.y = PI
		probe.scale = Vector3(1.6, 1.6, 1.6)
		add_child(probe)
	if "--nodetail" in args:
		# flag every detail-map surface so it is unmistakable on screen
		var seen: Dictionary = {}
		var flagged := 0
		for node in _walk(self):
			var m: Mesh = null
			if node is MeshInstance3D:
				m = node.mesh
			elif node is MultiMeshInstance3D:
				m = node.multimesh.mesh
			if m == null or seen.has(m):
				continue
			seen[m] = true
			for i in range(1, m.get_surface_count()):
				m.surface_set_material(i, _flag_material())
				flagged += 1
		print("flagged detail surfaces: ", flagged, " on ", seen.size(), " meshes")
	if "--noshadow" in args:
		for node in _walk(self):
			if node is Light3D:
				node.shadow_enabled = false
	if "--nossao" in args:
		for node in _walk(self):
			if node is WorldEnvironment:
				node.environment.ssao_enabled = false

	var modes := {
		"unshaded": Viewport.DEBUG_DRAW_UNSHADED,
		"lighting": Viewport.DEBUG_DRAW_LIGHTING,
		"normals": Viewport.DEBUG_DRAW_NORMAL_BUFFER,
		"wireframe": Viewport.DEBUG_DRAW_WIREFRAME,
		"overdraw": Viewport.DEBUG_DRAW_OVERDRAW,
	}
	for key in modes:
		if "--" + key in args:
			get_viewport().debug_draw = modes[key]

	var camera := Camera3D.new()
	camera.fov = 70
	camera.far = 300
	add_child(camera)
	camera.make_current()

	# the rear channel is what the cabling shots are about, and it sits behind a
	# perforated door
	for door in _doors:
		door["node"].rotation.y = door["shut"] - deg_to_rad(105)
		door["open"] = true

	var shots := SHOTS.duplicate()
	# a camera 90 mm off a real port, found from the wiring rather than from numbers
	# worked out by hand — every hand-aimed close-up so far has missed
	for nth in [0, 2, 40, 104]:
		var found := _wiring.debug_port(0, nth)
		if not found.is_empty():
			var at: Vector3 = found[0] + found[1] * 0.09
			shots.append(["plug_%d" % nth, at, found[0]])

	if _laptop != null:
		var pose := _laptop.seat_pose()
		if not pose.is_empty():
			shots.append(["laptop_desktop", pose[0], pose[1], ""])
			shots.append(["laptop_shop", pose[0], pose[1], "shop"])

	var dir := "user://shots"
	DirAccess.make_dir_recursive_absolute(dir)
	for shot in shots:
		camera.position = shot[1]
		camera.look_at(shot[2], Vector3.UP)
		if shot.size() > 3 and _laptop != null:
			_laptop.show_app(shot[3])
		# a few frames so SSAO, SSR and the light probes settle before the grab
		for i in 12:
			await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/%s.png" % [dir, shot[0]])
		print("shot: ", ProjectSettings.globalize_path(dir), "/", shot[0], ".png")
	get_tree().quit()


static func _flag_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0, 1)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


func _assert_inside(rack: Node3D, transforms: Array[Transform3D], m: Mesh,
                    label: String) -> void:
	## Everything mounted in a cabinet has to fit inside it. Getting the front axis
	## backwards parked whole stacks outside the rack, and nothing in the pipeline
	## complained — a scene is geometry too, and deserves the same checking as a model.
	if m == null or transforms.is_empty():
		return
	var cabinet := AABB(Vector3(-RACK_W / 2, 0, -RACK_D / 2),
		Vector3(RACK_W, RACK_H, RACK_D)).grow(0.01)
	for tf in transforms:
		var box := tf * m.get_aabb()
		if not cabinet.encloses(box):
			push_error("%s at %v sticks out of the cabinet (%v .. %v vs %v .. %v)" %
				[label, tf.origin, box.position, box.end,
				 cabinet.position, cabinet.end])
			return


func _tint(mmi: MultiMeshInstance3D, colour: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = 1.0
	mmi.material_override = mat


func _matte() -> void:
	## Diagnostic: kill the specular response but keep every albedo. Overriding the
	## whole material also flattens colour, which makes light parts look like they
	## vanished when they were only repainted.
	var mat: StandardMaterial3D = Assets.material("dc_atlas")
	mat.metallic = 0.0
	mat.metallic_texture = null
	mat.roughness = 1.0
	mat.roughness_texture = null
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED


func _stats() -> void:
	var meshes := 0
	var multi := 0
	var instances := 0
	var empty := []
	for node in _walk(self):
		if node is MeshInstance3D:
			meshes += 1
			if node.mesh == null:
				empty.append(node.get_parent().name)
		elif node is MultiMeshInstance3D:
			multi += 1
			instances += node.multimesh.instance_count
			if node.multimesh.mesh == null:
				empty.append("multimesh@" + node.get_parent().name)
	print("meshes=%d multimesh=%d instances=%d empty=%s" % [meshes, multi, instances, empty])


# ----------------------------------------------------------------- lighting

func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.022, 0.026)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.30, 0.36, 0.46)
	# a hall lit only from the ceiling leaves vertical faces near-black, and every
	# small horizontal ledge on a chassis then flares as a loose bright patch
	env.ambient_light_energy = 0.34
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.9
	env.ssao_enabled = true
	env.ssao_radius = 0.6
	env.ssao_intensity = 1.5
	env.ssr_enabled = false
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.12
	env.glow_hdr_threshold = 1.25
	env.fog_enabled = true
	env.fog_light_color = Color(0.10, 0.11, 0.13)
	env.fog_density = 0.004

	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)

	var sun := DirectionalLight3D.new()
	sun.light_energy = 0.10
	sun.light_color = Color(0.72, 0.80, 0.95)
	sun.rotation_degrees = Vector3(-52, 38, 0)
	sun.shadow_enabled = true
	add_child(sun)


func _ceiling_lamp(at: Vector3, length := 1.24) -> void:
	var lamp := Assets.instance("props/ceiling_lamp")
	lamp.position = at
	add_child(lamp)

	var light := OmniLight3D.new()
	light.position = at + Vector3(0, -0.45, 0)
	light.light_energy = 4.2
	light.light_color = Color(0.82, 0.88, 1.0)
	light.omni_range = 5.8
	light.omni_attenuation = 1.8
	light.shadow_enabled = true
	add_child(light)


# --------------------------------------------------------------------- hall

func _hall() -> void:
	var half := Vector2(HALL.x, HALL.y) * TILE * 0.5

	# slab under the raised floor
	var slab := MeshInstance3D.new()
	var slab_mesh := BoxMesh.new()
	slab_mesh.size = Vector3(HALL.x * TILE, 0.3, HALL.y * TILE)
	slab.mesh = slab_mesh
	slab.position = Vector3(0, -0.15, 0)
	var slab_mat := StandardMaterial3D.new()
	slab_mat.albedo_color = Color(0.1, 0.1, 0.11)
	slab_mat.roughness = 0.95
	slab.material_override = slab_mat
	add_child(slab)
	_static_box(Vector3(HALL.x * TILE, 0.3, HALL.y * TILE), Vector3(0, -0.15, 0))

	var solid := _multimesh("room/floor_tile_solid")
	var grille := _multimesh("room/floor_tile_grille")
	var pedestal := _multimesh("room/floor_pedestal")
	var solid_tf: Array[Transform3D] = []
	var grille_tf: Array[Transform3D] = []
	var ped_tf: Array[Transform3D] = []

	for ix in HALL.x:
		for iy in HALL.y:
			var p := Vector3((ix + 0.5) * TILE - half.x, PLENUM, (iy + 0.5) * TILE - half.y)
			# grilles run in the cold aisles, in front of the rack faces
			var cold := (iy == 6 or iy == 7) and ix > 3 and ix < HALL.x - 4
			if cold:
				grille_tf.append(Transform3D(Basis(), p))
			else:
				solid_tf.append(Transform3D(Basis(), p))
			ped_tf.append(Transform3D(Basis(), p + Vector3(TILE * 0.5, 0, TILE * 0.5)))

	_fill(solid, solid_tf)
	_fill(grille, grille_tf)
	_fill(pedestal, ped_tf)
	_static_box(Vector3(HALL.x * TILE, 0.05, HALL.y * TILE), Vector3(0, PLENUM - 0.025, 0))

	_hall_walls(half)
	_hall_ceiling(half)

	# two rows facing each other across a cold aisle
	for row in 2:
		var z := (-1.0 if row == 0 else 1.0) * 1.5
		var facing := 0.0 if row == 0 else PI
		for i in 8:
			var x := (i - 3.5) * (RACK_W + 0.002)
			# `i` drives what the cabinet looks like, `id` is who it is: the two rows
			# must not share ids, or a cord could reach across the aisle
			_rack(Vector3(x, PLENUM, z), facing, i, row * 16 + i)

	for i in 4:
		_ceiling_lamp(Vector3((i - 1.5) * 3.0, 3.35, 0))
	for i in 3:
		_ceiling_lamp(Vector3((i - 1.0) * 3.4, 3.35, -4.2))
		_ceiling_lamp(Vector3((i - 1.0) * 3.4, 3.35, 4.2))

	_trays()


func _hall_walls(half: Vector2) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.17, 0.18, 0.20)
	mat.roughness = 0.85
	for side in 3:
		var horizontal := side < 1
		var length := (HALL.x if horizontal else HALL.y) * TILE
		var offset := -half.y if horizontal else half.x * (1.0 if side == 1 else -1.0)
		var size := Vector3(length, 3.6, 0.2) if horizontal else Vector3(0.2, 3.6, length)
		var pos := Vector3(0, 1.8, offset) if horizontal else Vector3(offset, 1.8, 0)
		var wall := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = size
		wall.mesh = box
		wall.position = pos
		wall.material_override = mat
		add_child(wall)
		_static_box(size, pos)


func _hall_ceiling(half: Vector2) -> void:
	var grid := _multimesh("room/ceiling_grid")
	var tile := _multimesh("room/ceiling_tile")
	var grid_tf: Array[Transform3D] = []
	var tile_tf: Array[Transform3D] = []
	for ix in HALL.x:
		for iy in HALL.y:
			var p := Vector3((ix + 0.5) * TILE - half.x, 3.5, (iy + 0.5) * TILE - half.y)
			grid_tf.append(Transform3D(Basis(), p))
			# leave the lamp runs open
			if absf(p.z) > 0.9 and absf(absf(p.z) - 4.2) > 0.9:
				tile_tf.append(Transform3D(Basis(), p))
	_fill(grid, grid_tf)
	_fill(tile, tile_tf)


func _trays() -> void:
	var straight := _multimesh("room/cable_tray_straight")
	var hanger := _multimesh("room/tray_hanger")
	var tray_tf: Array[Transform3D] = []
	var hang_tf: Array[Transform3D] = []
	for z in [-3.0, 3.0]:
		for i in 4:
			var x := (i - 1.5) * 2.0
			tray_tf.append(Transform3D(Basis(), Vector3(x, 2.95, z)))
			hang_tf.append(Transform3D(Basis(), Vector3(x - 0.9, 3.5, z)))
	_fill(straight, tray_tf)
	_fill(hanger, hang_tf)


func _rack(at: Vector3, yaw: float, index: int, id: int) -> void:
	var basis := Basis(Vector3.UP, yaw)
	var root := Node3D.new()
	root.transform = Transform3D(basis, at)
	add_child(root)

	root.add_child(Assets.instance("hardware/rack_42u_frame"))

	var side := Assets.instance("hardware/rack_42u_side")
	side.position = Vector3(RACK_W / 2 - 0.007, PLINTH + (RACK_H - PLINTH - 0.04) / 2, 0)
	root.add_child(side)

	var glazed := index % 2 == 1
	var front := Assets.instance(
		"hardware/rack_42u_door_glass" if glazed else "hardware/rack_42u_door_front")
	front.position = Vector3(-RACK_W / 2, 0.01, RACK_FRONT_Z + 0.004)
	# one rack stands open, the way it looks when someone is working in it
	front.rotation.y = deg_to_rad(-100 if index == 2 else 0)
	root.add_child(front)
	if glazed and not ("--noglass" in OS.get_cmdline_user_args()):
		var pane := Assets.instance("hardware/rack_42u_glass")
		pane.position = front.position
		pane.rotation = front.rotation
		root.add_child(pane)

	var rear := Assets.instance("hardware/rack_42u_door_rear")
	rear.position = Vector3(RACK_W / 2, 0.01, -RACK_FRONT_Z - 0.004)
	rear.rotation.y = PI
	root.add_child(rear)
	_doors.append({"node": rear, "at": root.global_position, "shut": PI, "open": false})

	var entry: Dictionary = _wiring.rack(id, Transform3D(basis, at))
	_fittings(root, entry, 1)
	_populate(root, index, entry)


func _fittings(root: Node3D, entry: Dictionary, strips_per_feed: int) -> void:
	## The rear channel: PDU strips out at the edge, a finger duct inboard of each.
	## Both face the hot aisle, because that is the side everything is patched from.
	var strips := _multimesh("hardware/pdu_strip", root)
	var strip_tf: Array[Transform3D] = []
	for i in strips_per_feed:
		for hand in [-1, 1]:
			var pos := Vector3(hand * STRIP_X, PLINTH + 0.1,
				CHANNEL_Z + 0.06 - i * 0.075)
			strip_tf.append(Transform3D(Basis(Vector3.UP, PI), pos))
			# Feed A always on the same side of the *hall*, not of the cabinet. The
			# second row faces the other way, so keying off the local side puts A left
			# in one row and right in the other, and a walk down the aisle shows both
			# colours on both sides.
			var world_side: float = (entry["xform"].basis * Vector3(hand, 0, 0)).x
			_wiring.add_strip(entry, pos,
				Wiring.FeedId.A if world_side < 0.0 else Wiring.FeedId.B)
	_fill(strips, strip_tf)

	var spines := _multimesh("hardware/cable_spine", root)
	var spine_tf: Array[Transform3D] = []
	for hand in [-1, 1]:
		var pos := Vector3(hand * SPINE_X, PLINTH, CHANNEL_Z)
		spine_tf.append(Transform3D(Basis(Vector3.UP, PI), pos))
		_wiring.add_spine(entry, pos)
	_fill(spines, spine_tf)


func _populate(root: Node3D, index: int, entry: Dictionary, fill_override := -1) -> Dictionary:
	## One MultiMesh per rack: a hall of 8400 chassis cannot be 8400 nodes.
	# Chassis LED pips are 4 mm: past a few metres they are sub-pixel and crawl as the
	# camera moves. Visibility ranges swap in the LOD mesh, which is the L0/L1 split
	# from docs/10-tech-architecture.md doing real work rather than an anti-alias hack.
	var servers := _multimesh("hardware/server_1u", root)
	var servers_far := _multimesh("hardware/server_1u_lod1", root)
	# Hard swap, no fade. Godot's visibility-range fade is screen-door dithering:
	# across the whole margin both meshes draw at once through a stipple pattern,
	# which on opaque chassis reads as torn dark wedges that crawl as you move. The
	# margins also overlapped, so the band where both drew was metres wide. The LOD1
	# mesh is close enough to the detailed one that a hard switch is not noticeable.
	servers.visibility_range_end = LOD_SWITCH
	servers.visibility_range_end_margin = 0.0
	servers.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	servers_far.visibility_range_begin = LOD_SWITCH
	servers_far.visibility_range_begin_margin = 0.0
	servers_far.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	var big := _multimesh("hardware/server_4u", root)
	var blanks := _multimesh("hardware/blanking_panel_1u", root)
	var patch := _multimesh("hardware/patch_panel_1u", root)
	var switches := _multimesh("hardware/switch_1u", root)
	var managers := _multimesh("hardware/cable_manager_1u", root)

	var server_tf: Array[Transform3D] = []
	# Which device each of those chassis is. The rack's own list is in the order
	# devices were made and includes the 4U box, which is drawn from a different pool;
	# picking a chassis off the screen needs the list that matches what is drawn.
	var server_dev := PackedInt32Array()
	var big_tf: Array[Transform3D] = []
	var blank_tf: Array[Transform3D] = []
	var patch_tf: Array[Transform3D] = []
	var switch_tf: Array[Transform3D] = []
	var manager_tf: Array[Transform3D] = []

	var face_z := RACK_FRONT_Z - CHASSIS_INSET
	# what 48 outlets can actually feed, two inlets each, is where this stops
	var fill: int = ([22, 18, 24, 16, 24, 14][index % 6] if fill_override < 0
		else fill_override)
	var slot := 1
	while slot < 41:
		var y := PLINTH + slot * U + 0.001
		var here := Transform3D(Basis(), Vector3(0, y, face_z))
		# A chassis is modelled from its bottom edge, every flat panel from its middle.
		# Placing both at the slot line drops the panels half a U into their neighbour.
		var centred := Transform3D(Basis(), Vector3(0, y + U * 0.5, face_z))
		# Switch and patch panel face the hot aisle: their ports belong on the side
		# the power is on, or patching means walking round the rack for every cord.
		var turned := Transform3D(Basis(Vector3.UP, PI),
			Vector3(0, y + U * 0.5, -face_z))
		if slot == 40:
			patch_tf.append(turned)
			# 24 in a row, 34 mm in from each edge of a 19" panel. Mirrored, because
			# the panel is turned to face the aisle while these coordinates are in
			# rack space: a layout that is not symmetric lands on the wrong side.
			_wiring.add_panel(entry, Vector3(0, y + U * 0.5, -face_z - 0.001),
				Wiring.Kind.PATCH, 24, 0.2073, -0.018026, 0.0)
		elif slot == 36:
			# Directly under the switches: the rings gather the patch leads before they
			# climb, which is what a fan of cords across a panel is solved with in life.
			manager_tf.append(turned)
			_wiring.add_manager(entry, Vector3(0, y + U * 0.5, -face_z - 0.012))
		elif slot == 39:
			blank_tf.append(centred)
		elif slot == 38 or slot == 37:
			switch_tf.append(turned)
			# Two rows of twelve on a 28 mm pitch, 60 mm in from the left edge — and
			# so not centred: mirroring is what puts them over the sockets rather
			# than 55 mm off them.
			_wiring.add_panel(entry, Vector3(0, y + U * 0.5, -face_z - 0.001),
				Wiring.Kind.SWITCH, 24, 0.1813, -0.028, 0.020)
		elif index % 3 == 2 and slot >= 6 and slot <= 9:
			if slot == 6:
				big_tf.append(here)
				_wiring.add_server(entry, Vector3(0, y, face_z), U * 4.0, 0.75)
			slot += 1
			continue
		elif slot * 100 / 41 < fill * 100 / 42:
			server_tf.append(here)
			server_dev.append(_wiring.add_server(entry, Vector3(0, y, face_z), U, 0.75))
		else:
			blank_tf.append(centred)
		slot += 1

	_fill(servers, server_tf)
	_fill(servers_far, server_tf)
	_assert_inside(root, server_tf, Assets.mesh("hardware/server_1u"), "server_1u")
	_assert_inside(root, big_tf, Assets.mesh("hardware/server_4u"), "server_4u")

	if "--rainbow" in OS.get_cmdline_user_args():
		_tint(servers, Color(1, 0.1, 0.1))
		_tint(servers_far, Color(0.1, 0.3, 1))
		_tint(blanks, Color(0.1, 1, 0.2))
		_tint(patch, Color(1, 0.9, 0.1))
		_tint(switches, Color(1, 0.2, 1))
		_tint(managers, Color(1, 0.55, 0.05))
	_fill(big, big_tf)
	_fill(blanks, blank_tf)
	_fill(patch, patch_tf)
	_fill(switches, switch_tf)
	_fill(managers, manager_tf)
	return {
		"root": root, "entry": entry, "face_z": face_z,
		"servers": servers, "servers_far": servers_far, "blanks": blanks,
		"server_tf": server_tf, "server_dev": server_dev, "blank_tf": blank_tf,
		"free": PackedInt32Array(),
	}


# --------------------------------------------------------------------- shed

func _shed() -> void:
	var shed := Node3D.new()
	shed.position = SHED_ORIGIN
	shed.add_to_group(NAV_SOURCE)
	add_child(shed)

	shed.add_child(Assets.instance("building/shed_shell"))
	# The slab is a collider with no mesh of its own, so the navigation bake has to be
	# told about it or there is nothing in the room to walk on.
	_static_box(Vector3(8.0, 0.2, 6.0), SHED_ORIGIN + Vector3(0, -0.1, 0)) 		.add_to_group(NAV_SOURCE)

	var gate := Assets.instance("building/shed_gate")
	gate.position = Vector3(-1.1, 0, -2.8)
	shed.add_child(gate)

	var door := Assets.instance("building/shed_door")
	door.position = Vector3(2.25, 0, -2.8)
	door.rotation.y = deg_to_rad(-75)
	shed.add_child(door)


	_place(shed, "furniture/desk", Vector3(2.0, 0, 1.2), PI * 0.5)
	_place(shed, "terminal/laptop_base", Vector3(2.0, 0.74, 1.2), PI * 0.5)
	var lid := _place(shed, "terminal/laptop_lid", Vector3(2.0, 0.74, 1.2), PI * 0.5)
	lid.rotate_object_local(Vector3.RIGHT, deg_to_rad(-18))
	var display := _place(shed, "terminal/laptop_display", Vector3(2.0, 0.74, 1.2), PI * 0.5)
	display.rotate_object_local(Vector3.RIGHT, deg_to_rad(-18))
	_laptop = Laptop.new()
	add_child(_laptop)
	_laptop.setup(display, _estate, self)

	_place(shed, "furniture/shelf", Vector3(-2.9, 0, 0.4), PI * 0.5)
	_place(shed, "props/box_large", Vector3(-2.75, 0.49, 0.1), 0.3)
	_place(shed, "props/box_large", Vector3(-2.75, 0.49, 0.55), -0.2)
	_place(shed, "props/box_small", Vector3(-2.8, 0.94, 0.3), 0.6)
	_place(shed, "power/ups", Vector3(-2.9, 0, 2.0), PI * 0.5)
	_place(shed, "power/breaker_panel", Vector3(-3.4, 1.5, -1.2), PI * 0.5)
	_place(shed, "cooling/ac_indoor", Vector3(0.0, 2.6, 2.6), PI)
	_place(shed, "props/extinguisher", Vector3(2.9, 0, -1.9), 0)
	_place(shed, "props/toolbox", Vector3(1.0, 0, 2.2), 0.4)
	_place(shed, "props/cable_coil", Vector3(0.4, 0, 2.3), 0)
	_place(shed, "props/cart", Vector3(0.2, 0, -0.6), PI * 0.25)
	_place(shed, "furniture/pallet", Vector3(-0.9, 0, -1.9), 0.1)
	_place(shed, "props/box_large", Vector3(-0.9, 0.145, -1.9), 0.1)
	_place(shed, "loto/loto_tag", Vector3(-1.6 + 0.62, 1.05, 0.98), 0)
	_place(shed, "loto/loto_lock", Vector3(-0.5, 0.75, 1.15), 0)

	for i in 2:
		var lamp := Assets.instance("props/ceiling_lamp")
		lamp.position = SHED_ORIGIN + Vector3(-1.2 + i * 2.6, 3.1, 0.4)
		add_child(lamp)
		var light := OmniLight3D.new()
		light.position = lamp.position + Vector3(0, -0.5, 0)
		light.light_energy = 3.0
		light.light_color = Color(0.95, 0.92, 0.84)
		light.omni_range = 8.0
		add_child(light)

	_place(self, "cooling/ac_outdoor", SHED_ORIGIN + Vector3(4.4, 0, 1.0), -PI * 0.5)

	# The shed starts bare. Everything in it is bought and carried in, which is the
	# loop the phase is about (docs/12, шаг 6) — a room that comes with three cabinets
	# already standing skips the only part of it worth playing.
	for i in SHED_SPOTS:
		var at := Vector3(-1.6 + i * 0.62, 0, 1.6)
		_spots.append({
			"at": at + SHED_ORIGIN, "taken": false, "index": _spots.size(),
			"mark": _floor_mark(shed, at),
			# low and inside its own rectangle: five of these at head height line up in
			# the view and read as one smeared row of text
			"sign": _sign(shed, at + Vector3(0, 0.32, 0), "ШКАФ"),
		})


# ---------------------------------------------------------------- catalogue

func _catalogue() -> void:
	var row := [
		["hardware/server_1u", "server_1u"],
		["hardware/server_2u", "server_2u"],
		["hardware/server_4u", "server_4u"],
		["hardware/drive_lff", "drive_lff"],
		["hardware/drive_sff", "drive_sff"],
		["hardware/patch_panel_1u", "patch_panel"],
		["hardware/switch_1u", "switch_1u"],
		["hardware/blanking_panel_1u", "blanking_1u"],
		["hardware/cable_manager_1u", "cable_manager"],
		["hardware/pdu_strip", "pdu_strip"],
		["room/floor_tile_solid", "floor_tile"],
		["room/floor_tile_grille", "floor_grille"],
		["room/floor_pedestal", "pedestal"],
		["room/cable_tray_straight", "cable_tray"],
		["room/cable_tray_corner", "tray_corner"],
		["room/ceiling_grid", "ceiling_grid"],
		["props/toolbox", "toolbox"],
		["props/extinguisher", "extinguisher"],
		["props/cable_coil", "cable_coil"],
		["props/box_large", "box_large"],
		["loto/loto_tag", "loto_tag"],
		["loto/loto_lock", "loto_lock"],
		["characters/helmet", "helmet"],
	]

	var origin := Vector3(-8.2, PLENUM, -9.4)
	var pitch := 1.45
	for i in row.size():
		var cell := origin + Vector3((i % 6) * pitch, 0, floori(i / 6.0) * pitch)
		var plinth_h := 0.62
		var plinth := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.62, plinth_h, 0.62)
		plinth.mesh = box
		plinth.position = cell + Vector3(0, plinth_h / 2, 0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.10, 0.11, 0.13)
		mat.roughness = 0.55
		plinth.material_override = mat
		add_child(plinth)

		var item := Assets.instance(row[i][0])
		item.rotation.y = deg_to_rad(-35)
		add_child(item)
		# sit each piece on the plinth by its own bounds: a 29 mm drive carrier and a
		# 1.5 m PDU cannot share one hardcoded height
		var aabb := item.get_aabb()
		var corners: Array[Vector3] = []
		for cx in [aabb.position.x, aabb.end.x]:
			for cy in [aabb.position.y, aabb.end.y]:
				for cz in [aabb.position.z, aabb.end.z]:
					corners.append(item.transform.basis * Vector3(cx, cy, cz))
		var low := corners[0].y
		var high := corners[0].y
		for c in corners:
			low = minf(low, c.y)
			high = maxf(high, c.y)
		item.position = cell + Vector3(0, plinth_h - low, 0)

		var label := Label3D.new()
		label.text = row[i][1]
		# fixed_size keeps the caption legible from across the room instead of
		# shrinking into a two-pixel smear
		label.fixed_size = true
		label.font_size = 64
		label.pixel_size = 0.00055
		label.position = cell + Vector3(0, plinth_h + (high - low) + 0.16, 0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = Color(0.78, 0.85, 0.95)
		label.outline_size = 16
		add_child(label)

		var light := OmniLight3D.new()
		light.position = cell + Vector3(0.25, plinth_h + 0.9, 0.25)
		light.light_energy = 1.6
		light.omni_range = 1.9
		add_child(light)


# ------------------------------------------------------------------- people

func _watch_pair(job: int) -> void:
	var place: int = _estate.JobPlaceOf(job)
	for i in 30:
		await get_tree().create_timer(1.0).timeout
		var spot: Dictionary = _spots[place]
		print("   %2d с: у места %d чел., готово %3d%%, собрано частей %d из %d"
			% [i + 1, _crew.at_job(job), roundi(_estate.JobProgressOf(job) * 100.0),
				int(spot.get("shown", 0)), (spot["stages"] as Array).size()
					if spot.has("stages") else 0])
		if _estate.JobStateOf(job) == 2:
			break
	get_tree().quit()


func _shoot_crew() -> void:
	## --crewshot: order one of each and photograph the crew actually doing it. A clip,
	## a prop and a cord between two moving bones are three things that read fine in a
	## log and wrong on screen, and there is no other way to see them.
	var camera := Camera3D.new()
	camera.fov = 55
	add_child(camera)

	for kind in [1, 0]:
		var spots := free_spots(kind)
		if spots.is_empty():
			continue
		var job := order(kind, spots[0]["place"], spots[0]["slot"])
		while _crew.at_job(job) == 0:
			await get_tree().create_timer(0.2).timeout
		await get_tree().create_timer(2.2).timeout

		var at := job_site(job)
		var ahead := job_facing(job).normalized()
		var beside := Vector3(ahead.z, 0, -ahead.x)
		# From the side at chest height: the hands and whatever is in them are between
		# the worker and the cabinet, and from behind the body hides both.
		var look := at + ahead * 0.35 + Vector3(0, 1.05, 0)
		var eye := at + beside * 1.9 + ahead * 0.4 + Vector3(0, 1.55, 0)
		camera.global_position = eye
		camera.look_at(look, Vector3.UP)
		camera.make_current()
		for i in 8:
			await RenderingServer.frame_post_draw
		var dir := "user://shots"
		DirAccess.make_dir_recursive_absolute(dir)
		print("камера %v, место %v" % [eye, at])
		print(_crew.cord_report())
		var name := "crew_patch" if kind == 0 else "crew_rack"
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, name])
		print("shot: ", ProjectSettings.globalize_path(dir), "/", name, ".png")
		# let it finish before ordering the next one, or the second photograph has the
		# first job's technician standing in front of the lens
		while _estate.JobStateOf(job) != 2:
			await get_tree().create_timer(0.5).timeout
	get_tree().quit()


func _watch_crowd() -> void:
	## Two servers into the same cabinet. There is one place to stand behind a rack, so
	## the second job has to wait for the first rather than put two people in it.
	var spots := free_spots(0)
	if spots.size() < 2 or spots[0]["place"] != spots[1]["place"]:
		print("crowd: в одном шкафу нет двух свободных мест")
		get_tree().quit()
		return
	for i in 2:
		print("заказан сервер -> работа %d"
			% order(0, spots[i]["place"], spots[i]["slot"]))
	for i in 34:
		await get_tree().create_timer(1.0).timeout
		print("   %2d с: у шкафа %d чел., в работе %d, в очереди %d, сделано %d"
			% [i + 1, _crew.at_job(0) + _crew.at_job(1), _estate.JobsRunning(),
				_estate.JobsQueued(), _estate.JobsDone()])
		if _estate.JobsDone() == 2:
			break
	get_tree().quit()


func _check_nav() -> void:
	## A path that bends has corners; one that goes through the furniture has two
	## points. Printing the count is the only way to tell the map is doing anything
	## without standing in the shed and watching.
	# The map rebuilds at the end of a physics frame, and until it has done so once a
	# query is an error rather than an empty answer
	var map := get_world_3d().navigation_map
	var post := SHED_ORIGIN + Vector3(0.9, 0, -1.4)
	var waited := 0
	while waited < 120:
		await get_tree().physics_frame
		waited += 1
		if NavigationServer3D.map_get_iteration_id(map) != 0 				and NavigationServer3D.map_get_closest_point(map, post) != Vector3.ZERO:
			break
	print("   карта: регионов %d, активна %s, кадров ждали %d, ближайшая точка %v"
		% [NavigationServer3D.map_get_regions(map).size(),
			NavigationServer3D.map_is_active(map), waited,
			NavigationServer3D.map_get_closest_point(map, post)])
	var from := SHED_ORIGIN + Vector3(0.9, 0, -1.4)
	for i in _bays.size():
		var to: Vector3 = _bays[i]["at"] - Vector3(0, 0, RACK_FRONT_Z + 0.55)
		var path := NavigationServer3D.map_get_path(map, from, to, true)
		var length := 0.0
		for c in range(1, path.size()):
			length += path[c - 1].distance_to(path[c])
		print("   путь к шкафу %d: %d точек, %.2f м (напрямую %.2f м)"
			% [i, path.size(), length, from.distance_to(to)])


func _watch_bays() -> void:
	## --order prints what the shed's cabinets hold, before and after. A purchase that
	## charges, queues, finishes and adds nothing to a MultiMesh looks exactly like a
	## purchase that worked, right up until you walk over and look.
	for i in _bays.size():
		var bay: Dictionary = _bays[i]
		print("   шкаф %d: серверов %d, в мешe %d, свободно %s" % [i,
			bay["entry"]["servers"].size(), bay["servers"].multimesh.instance_count,
			bay["free"]])


func _check_racking(player: ShowroomPlayer) -> void:
	## --rack: aim at a chassis, pull it out, aim at an empty unit, put it back — with
	## the real key and the real picking. Racking by hand touches the MultiMesh, the
	## free-unit list and the port positions at once, and all three are silent when
	## they disagree.
	player.frozen = true
	_stock_a_cabinet(4)
	if _bays.is_empty():
		print("rack: шкафов нет")
		get_tree().quit()
		return
	var bay: Dictionary = _bays[0]
	var eye := player.eye()
	print("rack: юнитов свободно %s, серверов %d"
		% [bay["free"], (bay["server_tf"] as Array).size()])

	await _look_at(eye, bay, 2)
	print("   навёлся: %s" % _racking.report())
	print("   подсказка: %s" % _racking.hud_text())
	await _snap("rack_highlight")
	await _press(KEY_X)
	await get_tree().create_timer(Racking.SLIDE + 0.4).timeout
	print("   вынул: %s, серверов %d, свободно %s"
		% [_racking.report(), (bay["server_tf"] as Array).size(), bay["free"]])
	await _snap("rack_empty_slot")

	# a technician in the cabinet locks the player out of it
	var room := free_spots(0)
	if not room.is_empty():
		var job := order(0, room[0]["place"], room[0]["slot"])
		while _crew.at_job(job) == 0:
			await get_tree().create_timer(0.2).timeout
		# a free unit, so the only thing that can refuse it is the lock
		await _look_at(eye, bay, 9)
		print("   при работнике: занято %s, под прицелом %s"
			% [rack_busy(int(bay["entry"]["index"])), _racking.report()])
		while _estate.JobStateOf(job) != 2:
			await get_tree().create_timer(0.3).timeout
		await _look_at(eye, bay, 9)
		print("   после работника: занято %s, под прицелом %s"
			% [rack_busy(int(bay["entry"]["index"])), _racking.report()])

	await _look_at(eye, bay, 7)
	print("   навёлся на пустой: %s" % _racking.report())
	await _press(KEY_X)
	await get_tree().create_timer(Racking.SLIDE + 0.4).timeout
	print("   вставил: %s, серверов %d, свободно %s"
		% [_racking.report(), (bay["server_tf"] as Array).size(), bay["free"]])
	get_tree().quit()


func _snap(name: String) -> void:
	for i in 8:
		await RenderingServer.frame_post_draw
	var dir := "user://shots"
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, name])
	print("shot: ", ProjectSettings.globalize_path(dir), "/", name, ".png")


func _stock_a_cabinet(servers: int) -> void:
	## A cabinet and a few boxes in it, without waiting for anyone to walk over. The
	## shed starts bare now, so every check that needs hardware has to put it there.
	var spots := free_spots(1)
	if spots.is_empty():
		return
	var job := order(1, spots[0]["place"], spots[0]["slot"])
	_estate.Claim(0)
	while not _estate.Advance(job, 5.0):
		pass
	job_done(job)
	for i in servers:
		var room := free_spots(0)
		if room.is_empty():
			break
		var one := order(0, room[0]["place"], room[0]["slot"])
		_estate.Claim(0)
		while not _estate.Advance(one, 5.0):
			pass
		job_done(one)


func _look_at(eye: Camera3D, bay: Dictionary, slot: int) -> void:
	var y: float = PLINTH + slot * U + 0.001 + U * 0.5
	var face: Vector3 = bay["at"] + Vector3(0, y, bay["face_z"])
	eye.global_position = face + Vector3(0, 0, 0.75)
	eye.look_at(face, Vector3.UP)
	await get_tree().process_frame
	await get_tree().process_frame


func _check_laptop(player: ShowroomPlayer) -> void:
	## --laptop: sit down and get up again through the real input path. Getting stuck
	## at a screen is the worst bug a diegetic interface can have — the player cannot
	## even quit to the menu, because there is no menu — so it is worth a check that
	## presses the keys rather than calls the methods.
	# standing at the desk, facing the screen — the state the prompt is written for
	var pose := _laptop.seat_pose()
	var centre: Vector3 = pose[1]
	var out: Vector3 = (pose[0] - centre).normalized()
	player.position = Vector3(centre.x + out.x * 0.7, SHED_ORIGIN.y, centre.z + out.z * 0.7)
	player.rotation.y = atan2(out.x, out.z)
	await get_tree().process_frame
	await get_tree().process_frame
	var numbers := _laptop.reach_numbers()
	print("laptop: до экрана %.2f м, прицел %.2f (нужно <= %.1f и >= %.2f)"
		% [numbers[0], numbers[1], Laptop.REACH, Laptop.AIM])
	print("laptop: в руках %s" % _laptop.prompt())
	print("laptop: сел %s" % _laptop.try_open())
	await get_tree().create_timer(Laptop.FLY + 0.2).timeout
	_report_laptop(player, "после E")
	await _press(KEY_ESCAPE)
	await get_tree().create_timer(Laptop.FLY + 0.2).timeout
	_report_laptop(player, "после Esc")

	# E is the other way out, and it goes through a different handler: the scene's,
	# which offers the key to the laptop before it opens a rack door
	await _press(KEY_E)
	await get_tree().create_timer(Laptop.FLY + 0.2).timeout
	_report_laptop(player, "сел по E")
	await _press(KEY_E)
	await get_tree().create_timer(Laptop.FLY + 0.2).timeout
	_report_laptop(player, "встал по E")
	get_tree().quit()


func _press(key: int) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = key
		event.physical_keycode = key
		event.pressed = pressed
		Input.parse_input_event(event)
		await get_tree().process_frame
	await get_tree().process_frame


func _report_laptop(player: ShowroomPlayer, when: String) -> void:
	var camera := get_viewport().get_camera_3d()
	print("   %s: открыт %s, заморожен %s, мышь %d, камера %s" % [
		when, _laptop.is_open(), player.frozen, Input.mouse_mode,
		"ноутбук" if camera != null and camera.get_parent() == _laptop else "игрок"])


func _check_shop() -> void:
	## --shop: buy one of everything the catalogue offers, finish the work the way a
	## worker would, and read the room back. Buying is the one path where money, the
	## job queue, the cabling core and three MultiMeshes all have to agree, and none
	## of that is visible in a screenshot until it is already wrong.
	print("shop: счёт %d, мест под сервер %d, под шкаф %d" % [
		_estate.Balance(), free_spots(0).size(), free_spots(1).size()])
	var servers: int = _wiring.racks().reduce(
		func(n, entry): return n + entry["servers"].size(), 0)

	for kind in [1, 0]:
		var spots := free_spots(kind)
		if spots.is_empty():
			print("   некуда ставить, вид %d" % kind)
			continue
		var spot: Dictionary = spots[0]
		var job: int = order(kind, spot["place"], spot["slot"])
		print("   куплено %d -> работа %d, осталось мест: %d, счёт %d"
			% [kind, job, free_spots(kind).size(), _estate.Balance()])
		if job < 0:
			continue
		print("   идти к %v" % job_site(job))
		_estate.Claim(0)
		while not _estate.Advance(job, 5.0):
			pass
		job_done(job)

	var after: int = _wiring.racks().reduce(
		func(n, entry): return n + entry["servers"].size(), 0)
	print("shop: серверов было %d, стало %d; стоек %d; очередь %d, сделано %d" % [
		servers, after, _wiring.racks().size(), _estate.JobsQueued(), _estate.JobsDone()])


func _navigation() -> void:
	## Walkable floor, baked from what is actually standing in the shed. Workers used
	## to go in a straight line and therefore through the desk, the pallets and each
	## other's cabinets; a path around them is not a detail, it is the difference
	## between a person and a marker sliding across the floor.
	##
	## Baked from the meshes rather than from collision shapes on purpose: almost
	## nothing in the room has a collider, because nothing needed one until now, and
	## giving every prop a body to please the baker is the wrong way round.
	var navmesh := NavigationMesh.new()
	navmesh.agent_radius = 0.34
	navmesh.agent_height = 1.75
	navmesh.agent_max_climb = 0.2
	navmesh.cell_size = 0.08
	navmesh.cell_height = 0.08
	# Both, because the room is a mix: the props are meshes with no collider and the
	# floor is a collider with no mesh.
	navmesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_BOTH
	navmesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	navmesh.geometry_source_group_name = NAV_SOURCE
	# Only the shed: the hall is on a raised floor the crew has no business on yet,
	# and baking it as well is seconds of startup for nothing.
	navmesh.filter_baking_aabb = AABB(SHED_ORIGIN + Vector3(-4.0, -0.4, -3.2),
		Vector3(8.0, 3.2, 6.4))

	# The map rasterises paths on its own grid, and a region registered against a
	# different one gets its edges rounded away — the seams between polygons stop
	# joining up. Set before the region exists, or it registers with the old grid.
	var map := get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(map, navmesh.cell_size)
	NavigationServer3D.map_set_cell_height(map, navmesh.cell_height)

	var region := NavigationRegion3D.new()
	region.navigation_mesh = navmesh
	add_child(region)
	var started := Time.get_ticks_msec()
	# On this thread, not the default background one: the crew is created immediately
	# after and would ask an empty map for its first path.
	region.bake_navigation_mesh(false)
	# Handing it back after the bake, because baking fills the resource and the region
	# is what puts a mesh on the server: without this the map has a region and no
	# surface, and every query answers the origin.
	region.navigation_mesh = navmesh
	print("навигация: %d полигонов за %d мс" % [
		navmesh.get_polygon_count(), Time.get_ticks_msec() - started])


func _shift() -> void:
	## The two on duty, as opposed to the five standing around for the asset shots.
	## They wait by the shed door and go wherever the queue sends them.
	_crew = Crew.new()
	add_child(_crew)
	_crew.setup(_estate, self, _wiring, [
		SHED_ORIGIN + Vector3(0.9, 0, -1.4),
		SHED_ORIGIN + Vector3(1.7, 0, -1.4),
	])


# ------------------------------------------------------------- места и покупки

## Everything the laptop is allowed to know about the room. The screen asks what is
## free and orders work; it never places anything itself, because a shop that could
## would be a second place where the world is built.

const TOP_U := 35              # the highest unit a server can take; 36+ is panels


func _open_bay(bay: Dictionary, at: Vector3) -> void:
	## Every unit above the last box, not a window of three. Hardware is racked upwards
	## from the bottom, so a hole in the middle of a filled rack is still not offered —
	## but a cabinet standing two-thirds empty with three units for sale reads as
	## broken, because it is nearly all free and the shop said no.
	##
	## The ceiling is not the cabinet, it is the strips: one feed has twenty-four
	## outlets and a server takes one from each, so a rack holds more boxes than it can
	## power and offering the difference is offering to buy something that arrives
	## dark.
	bay["at"] = at
	bay["at_xform"] = Transform3D(Basis(), at)
	var top := 0
	for tf in bay["server_tf"]:
		top = maxi(top, int(roundf((tf.origin.y - PLINTH - 0.001) / U)))
	var free := PackedInt32Array()
	for slot in range(top + 1, TOP_U + 1):
		if free.size() >= _wiring.spare_inlets(bay["entry"]):
			break
		free.append(slot)
	bay["free"] = free
	# An open U reads as free at a glance; a blanking panel over it does not. The
	# panels at those slots are dropped rather than marked.
	for slot in free:
		_drop_blank(bay, slot)
	_fill(bay["blanks"], bay["blank_tf"])
	_bays.append(bay)
	if not free.is_empty():
		_sign(bay["root"], Vector3(0, PLINTH + (free[0] + free.size() * 0.5) * U,
			RACK_FRONT_Z + 0.06), "%dU СВОБОДНО" % free.size())


func rack_busy(index: int) -> bool:
	## A cabinet a technician is inside. Reaching past him to pull a chassis out from
	## under his hands is not something the player gets to do.
	return locked_racks().has(index)


func locked_racks() -> PackedInt32Array:
	var busy := PackedInt32Array()
	for job in _tags:
		if _estate.JobStateOf(job) != 1:
			continue
		var place: int = _estate.JobPlaceOf(job)
		if _estate.JobKindOf(job) == 1:
			var spot: Dictionary = _spots[place]
			if spot.has("bay"):
				busy.append(int(spot["bay"]["entry"]["index"]))
		elif place < _bays.size():
			busy.append(int(_bays[place]["entry"]["index"]))
	return busy


func free_spots(kind: int) -> Array:
	## kind mirrors ItemKind in sim/Estate/Catalogue.cs: 0 a server, 1 a cabinet.
	var out := []
	if kind == 1:
		for spot in _spots:
			if not spot["taken"]:
				out.append({"place": spot["index"], "slot": 0,
					"label": "место %d в сарае" % (spot["index"] + 1)})
		return out
	for i in _bays.size():
		var bay: Dictionary = _bays[i]
		for slot in bay["free"]:
			out.append({"place": i, "slot": slot,
				"label": "шкаф %d, %dU" % [int(bay["entry"]["index"]) - SHED_RACK + 1, slot]})
	return out


func order(item: int, place: int, slot: int) -> int:
	var job: int = _estate.Buy(item, place, slot)
	if job < 0:
		return -1
	# Held the moment it is paid for, not when the worker arrives: the shop must not
	# offer the same shelf to two purchases while the first is still being carried in.
	if _estate.JobKindOf(job) == 1:
		_spots[place]["taken"] = true
	else:
		var free: PackedInt32Array = _bays[place]["free"]
		var at := free.find(slot)
		if at >= 0:
			free.remove_at(at)
			_bays[place]["free"] = free
	return job


func job_site(job: int, seat := 0) -> Vector3:
	## Where a worker stands to do it. A cabinet is built from its two front corners,
	## crouched, on the side the aisle is: that is the only place there is room, and a
	## pair kneeling at opposite corners is what assembling one looks like.
	var place: int = _estate.JobPlaceOf(job)
	if _estate.JobKindOf(job) == 1:
		var hand := 1.0 if seat == 0 else -1.0
		return _spots[place]["at"] + Vector3(hand * (RACK_W * 0.5 + 0.12), 0,
			-(RACK_D * 0.5 + 0.35))
	# Behind the cabinet, where the sockets are: that is where the cords go in, and in
	# the shed the front of a rack is a third of a metre from the back wall, which is
	# not a place a person fits at all.
	return _bays[place]["at"] - Vector3(0, 0, RACK_FRONT_Z + 0.55)


func job_facing(job: int, seat := 0) -> Vector3:
	## At the work, not a fixed direction. The two kinds are approached from opposite
	## sides of a cabinet, so one constant has to be wrong for one of them — and it
	## was: patching happens behind the rack and the technician faced the aisle.
	var place: int = _estate.JobPlaceOf(job)
	var at: Vector3 = (_spots[place]["at"] if _estate.JobKindOf(job) == 1
		else _bays[place]["at"])
	return at - job_site(job, seat)


func job_place(job: int) -> int:
	## Which cabinet or floor spot this is, as one number. Two jobs sharing it cannot
	## be worked at the same time, because there is one place to stand.
	return _estate.JobKindOf(job) * 1000 + _estate.JobPlaceOf(job)


func job_crew(job: int) -> int:
	return 2 if _estate.JobKindOf(job) == 1 else 1


func job_clip(job: int) -> String:
	return "work_crouch" if _estate.JobKindOf(job) == 1 else "patch"


func job_prop(job: int) -> String:
	## A cabinet is assembled with both hands. A server is patched, and a technician
	## doing that works out of a coil held in one hand — which is the difference
	## between the two jobs at a glance.
	return "" if _estate.JobKindOf(job) == 1 else "props/cable_coil"


func job_sound(_job: int) -> String:
	return ""


func job_beat(_job: int) -> float:
	## Nothing is on a timer any more: a cabinet makes its noise when a part appears and
	## a server when a cord goes in, so both are heard at the moment they happen.
	return 0.0


# What the work has produced so far, per job. A technician racks the box, then plugs
# one cord at a time — three of them, and the coil in their hand is whichever one is
# going in. All of it appearing at once was the whole job happening on the last frame.
# One noise per kind of part. The same sample four times over reads as a stutter,
# and the parts are not alike: a frame lands, rails clatter, panels click home, a
# door swings and catches.
const PART_SOUND := ["rack_frame", "rack_rail", "rack_panel", "rack_door"]
const BOX_IN := 0.20
const CORD_AT := [0.40, 0.60, 0.80]


func job_tick(job: int, _before: float, after: float) -> void:
	if _estate.JobKindOf(job) == 1:
		_show_rack(_estate.JobPlaceOf(job), after)
		return

	var step: Dictionary = _doing.get(job, {"device": -1, "cords": 0})
	var place: int = _estate.JobPlaceOf(job)
	var bay: Dictionary = _bays[place]
	var at := job_site(job)
	if step["device"] < 0 and after >= BOX_IN:
		step["device"] = _rack_server(place, _estate.JobSlotOf(job))
		_crew.say(at + Vector3(0, 0.8, 0), "rack_panel", -6.0)
	if step["device"] >= 0:
		for cord in CORD_AT.size():
			if int(step["cords"]) > cord or after < CORD_AT[cord]:
				continue
			var link: int = _wiring.wire_cord(bay["entry"], step["device"], cord)
			step["cords"] = cord + 1
			if link >= 0:
				_crew.hold_colour(job, _wiring.link_colour(link))
				_crew.say(at + Vector3(0, 1.0, 0), "plug_in", -8.0)
				if "--order" in OS.get_cmdline_user_args():
					print("   работа %d: шнур %d воткнут на %d%%, цвет %s"
						% [job, cord, roundi(after * 100.0), _wiring.link_colour(link)])
	_doing[job] = step


func job_started(job: int) -> void:
	## A tag over the place being worked on. Ordering something and then watching the
	## room for half a minute with no idea whether anything is happening is how a
	## purchase that worked reads as a purchase that did nothing.
	if _estate.JobKindOf(job) == 1:
		_start_rack(_estate.JobPlaceOf(job))
	var at := job_site(job) + Vector3(0, 1.75, 0)
	_tags[job] = _sign(self, at, "")
	_tags[job].modulate = Color(0.40, 0.86, 0.58)


func job_done(job: int) -> void:
	var place: int = _estate.JobPlaceOf(job)
	print("работа %d выполнена: вид %d, место %d, %dU"
		% [job, _estate.JobKindOf(job), place, _estate.JobSlotOf(job)])
	if _estate.JobKindOf(job) == 1:
		_raise_rack(place)
	else:
		# whatever the ticks have not got to yet — a job finished early, or one long
		# tick that crossed every threshold at once
		job_tick(job, 0.0, 1.0)
		_doing.erase(job)
	_wiring.grew()
	if _tags.has(job):
		_tags[job].queue_free()
		_tags.erase(job)
	if "--order" in OS.get_cmdline_user_args():
		_watch_bays()


func _rack_server(place: int, slot: int) -> int:
	## The box goes in. Its cords follow one at a time, so this does not patch it.
	var bay: Dictionary = _bays[place]
	var y := PLINTH + slot * U + 0.001
	var at := Vector3(0, y, bay["face_z"])
	bay["server_tf"].append(Transform3D(Basis(), at))
	_fill(bay["servers"], bay["server_tf"])
	_fill(bay["servers_far"], bay["server_tf"])
	# add_server appends, so the rack's server list stays in height order only while
	# the free units are the ones above the last box — which is what _open_bay hands out
	var device: int = _wiring.add_server(bay["entry"], at, U, 0.75)
	var devices: PackedInt32Array = bay["server_dev"]
	devices.append(device)
	bay["server_dev"] = devices
	_wiring.grew()
	return device


func _start_rack(place: int) -> void:
	## A cabinet is not carried in whole — it is built where it stands, and the parts
	## appear in the order someone would put them there. Everything is made at once and
	## hidden, because building it a stage at a time would have the wiring register its
	## ports halfway through, and nothing else in the scene expects that.
	var spot: Dictionary = _spots[place]
	if spot.has("stages"):
		return
	var root := Node3D.new()
	root.position = spot["at"]
	add_child(root)
	var stages: Array = []

	var frame := Assets.instance("hardware/rack_42u_frame")
	root.add_child(frame)
	stages.append([frame])

	var entry: Dictionary = _wiring.rack(SHED_RACK + 10 + place,
		Transform3D(Basis(), spot["at"]))
	var mark := root.get_child_count()
	_fittings(root, entry, 1)
	stages.append(root.get_children().slice(mark))

	mark = root.get_child_count()
	# A cabinet arrives empty. What goes in it is the next thing bought, which is the
	# whole point of it standing there.
	var bay: Dictionary = _populate(root, 0, entry, 0)
	stages.append(root.get_children().slice(mark))

	var front := Assets.instance("hardware/rack_42u_door_front")
	front.position = Vector3(-RACK_W / 2, 0.01, RACK_FRONT_Z + 0.004)
	root.add_child(front)
	stages.append([front])

	for group in stages:
		for node in group:
			node.visible = false
	spot["stages"] = stages
	spot["shown"] = 0
	spot["bay"] = bay
	_wiring.grew()


func _show_rack(place: int, progress: float) -> void:
	var spot: Dictionary = _spots[place]
	if not spot.has("stages"):
		return
	var stages: Array = spot["stages"]
	var want := clampi(floori(progress * stages.size()) + 1, 0, stages.size())
	while int(spot["shown"]) < want:
		for node in stages[int(spot["shown"])]:
			node.visible = true
		spot["shown"] = int(spot["shown"]) + 1
		_crew.say(spot["at"] + Vector3(0, 0.4, 0), PART_SOUND[
			mini(int(spot["shown"]) - 1, PART_SOUND.size() - 1)], -4.0)


func _raise_rack(place: int) -> void:
	var spot: Dictionary = _spots[place]
	_start_rack(place)
	_show_rack(place, 1.0)
	_open_bay(spot["bay"], spot["at"])
	if is_instance_valid(spot["mark"]):
		spot["mark"].queue_free()
	if is_instance_valid(spot["sign"]):
		spot["sign"].queue_free()


func _drop_blank(bay: Dictionary, slot: int) -> void:
	var y := PLINTH + slot * U + 0.001 + U * 0.5
	var panels: Array[Transform3D] = bay["blank_tf"]
	for i in panels.size():
		if absf(panels[i].origin.y - y) < U * 0.4:
			panels.remove_at(i)
			return


func _floor_mark(parent: Node3D, at: Vector3) -> Node3D:
	## A painted outline on the floor. Four thin quads rather than a textured plane:
	## the palette atlas has no decals, and an outline is what a real floor gets.
	const WIDE := 0.03
	var mark := Node3D.new()
	mark.position = at + Vector3(0, 0.008, 0)
	parent.add_child(mark)
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.95, 0.72, 0.14)
	paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var half := Vector2(RACK_W * 0.5, RACK_D * 0.5)
	for side in 4:
		var bar := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		var along := side < 2
		# The side bars stop short of the end ones rather than crossing them. Two
		# coplanar quads sharing a corner is z-fighting by construction, and no amount
		# of lifting the whole outline off the floor fixes it.
		plane.size = (Vector2(half.x * 2.0, WIDE) if along
			else Vector2(WIDE, half.y * 2.0 - WIDE * 2.0))
		bar.mesh = plane
		bar.material_override = paint
		bar.position = Vector3(0 if along else half.x * (1 if side == 2 else -1), 0,
			half.y * (1 if side == 0 else -1) if along else 0)
		mark.add_child(bar)
	return mark


func _sign(parent: Node3D, at: Vector3, text: String) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.fixed_size = true
	label.font_size = 34
	label.pixel_size = 0.0004
	label.modulate = Color(0.95, 0.72, 0.14)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = at
	parent.add_child(label)
	return label


# ---------------------------------------------------------------------- hud

func _prewire() -> void:
	## Some racks come already patched so the hall reads as a working room, and the
	## rest are left bare for the player. Rack 5 was done by a technician who was
	## having a bad morning — it looks the same until a feed goes down.
	for entry in _wiring.racks():
		if int(entry["index"]) >= SHED_RACK:
			continue
		match int(entry["index"]):
			2, 3:
				continue
			5:
				_wiring.wire_rack(entry, 4, 7, true)
			_:
				_wiring.wire_rack(entry, 0, 1, true)
	_wiring.clear_message()
	_wiring.refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		# the laptop gets first refusal: standing at the desk, E sits down; standing at
		# a cabinet it still opens the door
		if _laptop != null and _laptop.try_open():
			return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		_swing_door()


func _swing_door() -> void:
	## Opens the rear door of whichever cabinet the player is standing at. The ducts
	## and the whole rear channel are behind a perforated door, so without this the
	## thing the player is meant to be working on is only visible through holes.
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var best := {}
	var best_d := 2.0
	for door in _doors:
		var d: float = (door["at"] - camera.global_position).length()
		if d < best_d:
			best_d = d
			best = door
	if best.is_empty():
		return

	best["open"] = not best["open"]
	var node: Node3D = best["node"]
	var target: float = best["shut"] - (deg_to_rad(105) if best["open"] else 0.0)
	var tween := create_tween()
	tween.tween_property(node, "rotation:y", target, 0.45).set_trans(Tween.TRANS_CUBIC)


func _crosshair(layer: CanvasLayer) -> void:
	## Every piece has to ignore the mouse. A Control defaults to swallowing mouse
	## events, and this one sits exactly under the captured cursor in the middle of the
	## screen — it ate every motion event and the camera stopped turning.
	var dot := ColorRect.new()
	dot.color = Color(1, 1, 1, 0.85)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.set_anchors_preset(Control.PRESET_CENTER)
	dot.size = Vector2(3, 3)
	dot.position = Vector2(-1.5, -1.5)
	layer.add_child(dot)
	for horizontal in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color(1, 1, 1, 0.35)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var length := 11.0
		bar.size = Vector2(length, 1) if horizontal else Vector2(1, length)
		bar.set_anchors_preset(Control.PRESET_CENTER)
		bar.position = (Vector2(-length / 2, 0) if horizontal
			else Vector2(0, -length / 2))
		layer.add_child(bar)


func _hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_crosshair(layer)
	_hud_label = Label.new()
	_hud_label.position = Vector2(16, 12)
	_hud_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_label.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	_hud_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_hud_label.add_theme_constant_override("outline_size", 6)
	layer.add_child(_hud_label)


func _process(_delta: float) -> void:
	if _hud_label == null:
		return
	# Label re-lays out its text on every assignment, and most frames it is the same
	var text := ("WASD ходить · Shift бег · Space прыжок · F полёт · Esc мышь · Q выход"
		+ "   [" + _build_stamp() + "]"
		+ "\n" + _unwired_hint()
		+ "\n" + _wiring.hud_text())
	# The laptop takes the screen over while it is open, so its line replaces the
	# patching one rather than sitting under it
	if _racking != null:
		var racking := _racking.hud_text()
		if not racking.is_empty():
			text += "
" + racking
	var at_desk: String = _laptop.prompt() if _laptop != null else ""
	if _laptop != null and _laptop.is_open():
		text = at_desk
	elif not at_desk.is_empty():
		text += "\n" + at_desk
	if text != _hud_label.text:
		_hud_label.text = text

	if _wiring != null:
		_wiring.lock_racks(locked_racks())
	for job in _tags:
		var kind: int = _estate.JobKindOf(job)
		var what := ("ШКАФ" if kind == 1 else "СЕРВЕР %dU" % _estate.JobSlotOf(job))
		_tags[job].text = "%s · %d%%" % [what, roundi(_estate.JobProgressOf(job) * 100.0)]


func _build_stamp() -> String:
	## When the running scene's script and models were last written. A scene left
	## running does not pick up either, and then a fix that is already on disk looks
	## like it was never made — which cost a whole round of this.
	var offset: int = Time.get_time_zone_from_system()["bias"] * 60
	var script_at := FileAccess.get_modified_time("res://view/wiring.gd") + offset
	var model_at := FileAccess.get_modified_time(
		"res://assets/models/hardware/server_1u.glb") + offset
	return "код %s · модели %s" % [
		Time.get_time_string_from_unix_time(script_at).substr(0, 5),
		Time.get_time_string_from_unix_time(model_at).substr(0, 5)]


func _unwired_hint() -> String:
	## The shed is deliberately left unpatched — it is where you learn to do it by hand
	## (docs/12, шаг 1) — so saying which cabinets are bare is not a warning, it is the
	## job list. Without it a rack of cordless servers next to a shop that sells more
	## of them reads as something broken.
	var bare := PackedStringArray()
	var shed := 0
	for entry in _wiring.racks():
		if not _wiring.is_bare(entry):
			continue
		if int(entry["index"]) < SHED_RACK:
			bare.append(str(entry["index"]))
		else:
			shed += 1
	var hall := ("всё разведено" if bare.is_empty()
		else "не разведены стойки %s — патчить с задней стороны" % ", ".join(bare))
	if shed == 0:
		return hall
	return "%s; в сарае %d стойки без шнуров — это ваша работа, купленное бригада подключает сама" % [
		hall, shed]


# ------------------------------------------------------------------ helpers

func _multimesh(path: String, parent: Node = null) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = Assets.mesh(path)
	Assets.multimesh_safe(mm.mesh, path)
	mmi.multimesh = mm
	(parent if parent != null else self).add_child(mmi)
	return mmi


func _fill(mmi: MultiMeshInstance3D, transforms: Array[Transform3D]) -> void:
	mmi.multimesh.instance_count = transforms.size()
	for i in transforms.size():
		mmi.multimesh.set_instance_transform(i, transforms[i])


func _place(parent: Node, path: String, at: Vector3, yaw: float) -> Node3D:
	var node := Assets.instance(path)
	node.position = at if parent != self else at
	node.rotation.y = yaw
	parent.add_child(node)
	return node


func _static_box(size: Vector3, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = at
	add_child(body)
	return body


func _walk(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for child in node.get_children():
		out.append_array(_walk(child))
	return out
