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

var _label_font: Font
var _cabling := CablingBridge.new()
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
	_people()
	_hud()

	if "--matte" in OS.get_cmdline_user_args():
		_matte()

	if "--stats" in OS.get_cmdline_user_args():
		_stats()

	if "--flicker" in OS.get_cmdline_user_args():
		_flicker()
		return

	if "--shots" in OS.get_cmdline_user_args():
		_shoot()
		return

	var player := ShowroomPlayer.new()
	player.position = Vector3(3.4, PLENUM + 0.1, 0.0)
	add_child(player)


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

	var dir := "user://shots"
	DirAccess.make_dir_recursive_absolute(dir)
	for shot in SHOTS:
		camera.position = shot[1]
		camera.look_at(shot[2], Vector3.UP)
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
			_wiring.add_strip(entry, pos,
				Wiring.FeedId.A if hand < 0 else Wiring.FeedId.B)
	_fill(strips, strip_tf)

	var spines := _multimesh("hardware/cable_spine", root)
	var spine_tf: Array[Transform3D] = []
	for hand in [-1, 1]:
		var pos := Vector3(hand * SPINE_X, PLINTH, CHANNEL_Z)
		spine_tf.append(Transform3D(Basis(Vector3.UP, PI), pos))
		_wiring.add_spine(entry, pos)
	_fill(spines, spine_tf)


func _populate(root: Node3D, index: int, entry: Dictionary) -> void:
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
	var big_tf: Array[Transform3D] = []
	var blank_tf: Array[Transform3D] = []
	var patch_tf: Array[Transform3D] = []
	var switch_tf: Array[Transform3D] = []
	var manager_tf: Array[Transform3D] = []

	var face_z := RACK_FRONT_Z - CHASSIS_INSET
	# what 48 outlets can actually feed, two inlets each, is where this stops
	var fill: int = [22, 18, 24, 16, 24, 14][index % 6]
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
			# 24 in a row, 34 mm in from each edge of a 19" panel
			_wiring.add_panel(entry, Vector3(0, y + U * 0.5, -face_z - 0.004),
				Wiring.Kind.PATCH, 24, -0.2073, 0.018026, 0.0)
		elif slot == 39 or slot == 36:
			manager_tf.append(turned)
		elif slot == 38 or slot == 37:
			switch_tf.append(turned)
			# two rows of twelve on a 28 mm pitch, starting 60 mm in on the left
			_wiring.add_panel(entry, Vector3(0, y + U * 0.5, -face_z - 0.004),
				Wiring.Kind.SWITCH, 24, -0.1813, 0.028, 0.020)
		elif index % 3 == 2 and slot >= 6 and slot <= 9:
			if slot == 6:
				big_tf.append(here)
				_wiring.add_server(entry, Vector3(0, y, face_z), U * 4.0, 0.75)
			slot += 1
			continue
		elif slot * 100 / 41 < fill * 100 / 42:
			server_tf.append(here)
			_wiring.add_server(entry, Vector3(0, y, face_z), U, 0.75)
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


# --------------------------------------------------------------------- shed

func _shed() -> void:
	var shed := Node3D.new()
	shed.position = SHED_ORIGIN
	add_child(shed)

	shed.add_child(Assets.instance("building/shed_shell"))
	_static_box(Vector3(8.0, 0.2, 6.0), SHED_ORIGIN + Vector3(0, -0.1, 0))

	var gate := Assets.instance("building/shed_gate")
	gate.position = Vector3(-1.1, 0, -2.8)
	shed.add_child(gate)

	var door := Assets.instance("building/shed_door")
	door.position = Vector3(2.25, 0, -2.8)
	door.rotation.y = deg_to_rad(-75)
	shed.add_child(door)

	for i in 3:
		var rack := Node3D.new()
		rack.position = Vector3(-1.6 + i * 0.62, 0, 1.6)
		shed.add_child(rack)
		rack.add_child(Assets.instance("hardware/rack_42u_frame"))
		var front := Assets.instance("hardware/rack_42u_door_front")
		front.position = Vector3(-RACK_W / 2, 0.01, RACK_FRONT_Z + 0.004)
		front.rotation.y = deg_to_rad(-95 if i == 1 else 0)
		rack.add_child(front)
		# phase-1 racks are numbered away from the hall so nothing reaches between the
		# two rooms; the shed is left unpatched on purpose, it is where you start
		var entry: Dictionary = _wiring.rack(SHED_RACK + i,
			Transform3D(Basis(), rack.position + SHED_ORIGIN))
		_fittings(rack, entry, 1)
		_populate(rack, i, entry)

	_place(shed, "furniture/desk", Vector3(2.0, 0, 1.2), PI * 0.5)
	_place(shed, "terminal/laptop_base", Vector3(2.0, 0.74, 1.2), PI * 0.5)
	var lid := _place(shed, "terminal/laptop_lid", Vector3(2.0, 0.74, 1.2), PI * 0.5)
	lid.rotate_object_local(Vector3.RIGHT, deg_to_rad(-18))
	var display := _place(shed, "terminal/laptop_display", Vector3(2.0, 0.74, 1.2), PI * 0.5)
	display.rotate_object_local(Vector3.RIGHT, deg_to_rad(-18))

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

func _people() -> void:
	var poses := [
		[Vector3(1.9, PLENUM, 0.1), deg_to_rad(90), "walk"],
		[Vector3(-0.9, PLENUM, 0.05), deg_to_rad(0), "work_stand"],
		[Vector3(0.3, PLENUM, -0.1), deg_to_rad(180), "work_crouch"],
		[SHED_ORIGIN + Vector3(1.4, 0, 1.2), deg_to_rad(-90), "type"],
		[SHED_ORIGIN + Vector3(-0.3, 0, 0.2), deg_to_rad(150), "carry_idle"],
	]
	for pose in poses:
		var worker: Node3D = Assets.scene("characters/worker")
		worker.position = pose[0]
		worker.rotation.y = pose[1]
		add_child(worker)

		var helmet := Assets.instance("characters/helmet")
		var skeleton := _find_skeleton(worker)
		if skeleton != null:
			var attach := BoneAttachment3D.new()
			attach.bone_name = "Head"
			skeleton.add_child(attach)
			attach.add_child(helmet)

		var player := _find_player(worker)
		if player != null:
			var name: String = pose[2]
			if player.has_animation(name):
				var anim := player.get_animation(name)
				anim.loop_mode = Animation.LOOP_LINEAR
				player.play(name)


func _find_skeleton(root: Node) -> Skeleton3D:
	for node in _walk(root):
		if node is Skeleton3D:
			return node
	return null


func _find_player(root: Node) -> AnimationPlayer:
	for node in _walk(root):
		if node is AnimationPlayer:
			return node
	return null


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
		+ "\n" + _unwired_hint()
		+ "\n" + _wiring.hud_text())
	if text != _hud_label.text:
		_hud_label.text = text


func _unwired_hint() -> String:
	var bare := PackedStringArray()
	for entry in _wiring.racks():
		if int(entry["index"]) < SHED_RACK and _wiring.is_bare(entry):
			bare.append(str(entry["index"]))
	if bare.is_empty():
		return "всё разведено"
	return "не разведены стойки %s — патчить с задней стороны" % ", ".join(bare)


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


func _static_box(size: Vector3, at: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = at
	add_child(body)


func _walk(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for child in node.get_children():
		out.append_array(_walk(child))
	return out
