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

const HALL := Vector2i(20, 14)      # floor tiles
const LOD_SWITCH := 10.0             # metres: detailed chassis inside, lod1 beyond
const SHED_ORIGIN := Vector3(0, 0, 16.0)

var _label_font: Font


func _ready() -> void:
	_environment()
	_hall()
	_shed()
	_catalogue()
	_people()
	_hud()

	if "--matte" in OS.get_cmdline_user_args():
		_matte()

	if "--stats" in OS.get_cmdline_user_args():
		_stats()

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
	["rack_row", Vector3(5.2, 1.55, 0.2), Vector3(-2.0, 1.20, -0.4)],
	["shed_inside", Vector3(2.6, 1.65, 18.4), Vector3(-1.6, 1.2, 16.4)],
	["shed_terminal", Vector3(2.9, 1.45, 16.4), Vector3(2.0, 0.85, 17.2)],
	["catalogue", Vector3(-4.2, 2.1, -5.6), Vector3(-6.6, 0.95, -8.6)],
	["worker", Vector3(0.9, 1.5, 1.4), Vector3(-0.2, 1.05, 0.2)],
]


func _shoot() -> void:
	var camera := Camera3D.new()
	camera.fov = 70
	camera.far = 300
	add_child(camera)
	camera.make_current()

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
		var facing := PI if row == 0 else 0.0
		for i in 8:
			var x := (i - 3.5) * (RACK_W + 0.002)
			_rack(Vector3(x, PLENUM, z), facing, i)

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


func _rack(at: Vector3, yaw: float, index: int) -> void:
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
	front.position = Vector3(-RACK_W / 2, 0.01, -RACK_D / 2 - 0.004)
	# one rack stands open, the way it looks when someone is working in it
	front.rotation.y = deg_to_rad(-100 if index == 2 else 0)
	root.add_child(front)
	if glazed:
		var pane := Assets.instance("hardware/rack_42u_glass")
		pane.position = front.position
		pane.rotation = front.rotation
		root.add_child(pane)

	var rear := Assets.instance("hardware/rack_42u_door_rear")
	rear.position = Vector3(RACK_W / 2, 0.01, RACK_D / 2 + 0.004)
	rear.rotation.y = PI
	root.add_child(rear)

	var pdu := Assets.instance("hardware/pdu_strip")
	pdu.position = Vector3(RACK_W / 2 - 0.08, PLINTH + 0.1, RACK_D / 2 - 0.1)
	root.add_child(pdu)

	_populate(root, index)


func _populate(root: Node3D, index: int) -> void:
	## One MultiMesh per rack: a hall of 8400 chassis cannot be 8400 nodes.
	# Chassis LED pips are 4 mm: past a few metres they are sub-pixel and crawl as the
	# camera moves. Visibility ranges swap in the LOD mesh, which is the L0/L1 split
	# from docs/10-tech-architecture.md doing real work rather than an anti-alias hack.
	var servers := _multimesh("hardware/server_1u", root)
	var servers_far := _multimesh("hardware/server_1u_lod1", root)
	# fade across the switch: a hard swap pops the whole rack as you walk up to it
	servers.visibility_range_end = LOD_SWITCH
	servers.visibility_range_end_margin = 2.5
	servers.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	servers_far.visibility_range_begin = LOD_SWITCH
	servers_far.visibility_range_begin_margin = 2.5
	servers_far.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
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

	var face_z := -RACK_D / 2 + 0.09
	var fill: int = [34, 30, 38, 26, 40, 22][index % 6]
	var slot := 1
	while slot < 41:
		var y := PLINTH + slot * U + 0.001
		var here := Transform3D(Basis(), Vector3(0, y, face_z))
		if slot == 40:
			patch_tf.append(here)
		elif slot == 39 or slot == 36:
			manager_tf.append(here)
		elif slot == 38 or slot == 37:
			switch_tf.append(here)
		elif index % 3 == 2 and slot >= 6 and slot <= 9:
			if slot == 6:
				big_tf.append(here)
			slot += 1
			continue
		elif slot * 100 / 41 < fill * 100 / 42:
			server_tf.append(here)
		else:
			blank_tf.append(here)
		slot += 1

	_fill(servers, server_tf)
	_fill(servers_far, server_tf)

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
		front.position = Vector3(-RACK_W / 2, 0.01, -RACK_D / 2 - 0.004)
		front.rotation.y = deg_to_rad(-95 if i == 1 else 0)
		rack.add_child(front)
		_populate(rack, i)

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

func _hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var label := Label.new()
	label.text = ("WASD move   Shift run   Space jump   F fly   Esc release mouse   Q quit"
		+ "\nhall ahead · shed behind you · catalogue to the left")
	label.position = Vector2(16, 12)
	label.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 6)
	layer.add_child(label)


# ------------------------------------------------------------------ helpers

func _multimesh(path: String, parent: Node = null) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = Assets.mesh(path)
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
