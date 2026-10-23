extends Control

signal token_pressed(token_id: String)
signal step_landed(token_id: String)
signal capture_passed(token_id: String)
signal token_captured(mover_id: String, captured_id: String)
signal move_preview_finished
const Design = preload("res://scripts/design.gd")
const BoardMath = preload("res://scripts/board_math.gd")
const Pawn = preload("res://scripts/pawn.gd")
const Geometry = preload("res://scripts/geometry.gd")
const BoardSurface = preload("res://scripts/board_surface.gd")
static var BOARD_COLORS: Dictionary = Design.COLORS
var viewport: SubViewport
var world: Node3D
var camera: Camera3D
var pawns: Dictionary = {}
var tokens: Dictionary = {}
var display_positions: Dictionary = {}
var move_preview: Dictionary = {}
var enabled := false
var reduced_motion := false
var artwork_viewport: SubViewport
var artwork: Control
var board_plane: MeshInstance3D
var stack_labels: Array[Label3D] = []
var rank_labels: Dictionary = {}
var departure_labels: Dictionary = {}
var trails: Array[MeshInstance3D] = []
const TRAIL_POOL_SIZE := 16
const FRAMING_WIDTH := 16.0
# Bound the animated scene's render target; the static square art cache stays 1024px.
const MAX_RENDER_EDGE := 1024
var framing_width := FRAMING_WIDTH:
	set(value):
		if is_equal_approx(framing_width,value): return
		framing_width = value
		_fit_camera()
const CAPTURE_STEP_MS := 64
const CAPTURE_HOME_MS := 128
var trail_pool: Array[MeshInstance3D] = []
var trail_fades: Dictionary = {}
var trail_texture: GradientTexture2D

func _ready() -> void:
	clip_contents = true
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.size = Vector2i(420, 420)
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	world = Node3D.new()
	viewport.add_child(world)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_CLEAR_COLOR
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color.WHITE
	settings.ambient_light_energy = 0.16
	environment.environment = settings
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48, -38, 0)
	light.light_energy = 0.65
	light.shadow_enabled = true
	light.directional_shadow_max_distance = 55
	light.shadow_bias = 0.025
	world.add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-32,140,0)
	fill.light_color = Color("bbd5ff")
	fill.light_energy = 0.12
	world.add_child(fill)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 16.6
	camera.position = Vector3(0, 30, 5)
	world.add_child(camera)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	resized.connect(_fit_camera)
	get_viewport().size_changed.connect(_fit_camera)
	make_board()
	make_trail_pool()
	_fit_camera()

func projected_vertical_bounds() -> Vector2:
	# Include the printed frame shadow and the pins at their highest idle bounce.
	var up := camera.global_basis.y
	var bottom := INF
	var top := -INF
	for x in [-7.85,7.85]:
		for z in [-7.85,7.85]:
			bottom = minf(bottom,up.dot(Vector3(x,0.20,z)))
			for y in [0.0,0.5]:
				top = maxf(top,up.dot(Vector3(x,y,z)))
	for z in [-7.21,7.21]:
		top = maxf(top,up.dot(Vector3(0,0.46,z))+1.85)
	return Vector2(bottom,top)

func preferred_height(width: float) -> float:
	var bounds := projected_vertical_bounds()
	return width*(bounds.y-bounds.x+0.25)/framing_width

func top_headroom_fraction() -> float:
	var bounds := projected_vertical_bounds()
	var board_center := camera.global_basis.y.dot(Vector3(0,0.20,0))
	return maxf(0.0,(bounds.x+bounds.y-2.0*board_center)/(bounds.y-bounds.x+0.25))

func display_point(render_point: Vector2) -> Vector2:
	return render_point * size / Vector2(viewport.size)

func _draw() -> void:
	if is_instance_valid(viewport):
		draw_texture_rect(viewport.get_texture(),Rect2(Vector2.ZERO,size),false)

func printed_rect() -> Rect2:
	var rect := Rect2(camera.unproject_position(Vector3(-7.5,0.20,-7.5)),Vector2.ZERO)
	for x in [-7.5,7.5]:
		for z in [-7.5,7.5]:
			rect = rect.expand(camera.unproject_position(Vector3(x,0.20,z)))
	return Rect2(display_point(rect.position),display_point(rect.size))

func _has_point(point: Vector2) -> bool:
	# Transparent pawn headroom can extend behind the upper toolbar. Let
	# those buttons receive clicks while retaining full-height pawn picking.
	return camera != null and (printed_rect().has_point(point) or (enabled and not token_at_screen(point).is_empty()))

func world_position(color: String, position: int, index: int) -> Vector3:
	return BoardMath.world(color,position,index)

func _fit_camera() -> void:
	if camera and size.x > 0 and size.y > 0:
		# Match physical screen pixels on dense phones instead of upscaling a
		# low-resolution UI-sized render. Apply one density to both axes.
		var screen_scale := (get_viewport_transform()*get_global_transform()).get_scale().abs()
		var density := minf(maxf(1.0,minf(screen_scale.x,screen_scale.y)),MAX_RENDER_EDGE/maxf(size.x,size.y))
		var render_size := Vector2i(maxi(1,roundi(size.x*density)),maxi(1,roundi(size.y*density)))
		if viewport.size != render_size:
			viewport.size = render_size
		var bounds := projected_vertical_bounds()
		camera.position = Vector3(0,30,5)+camera.global_basis.y*((bounds.x+bounds.y)*0.5)
		camera.keep_aspect = Camera3D.KEEP_WIDTH
		camera.size = maxf(framing_width,(bounds.y-bounds.x+0.25)*viewport.size.x/viewport.size.y)
		queue_redraw()

func make_board() -> void:
	# Render Theme/StyleBoxFlat/GradientTexture2D artwork once. A single unlit
	# plane preserves the established 3D pawn coordinates and input projection.
	artwork_viewport = SubViewport.new()
	artwork_viewport.name = "BoardArtworkCache"
	artwork_viewport.size = Vector2i(BoardSurface.RESOLUTION, BoardSurface.RESOLUTION)
	artwork_viewport.disable_3d = true
	artwork_viewport.gui_disable_input = true
	artwork_viewport.transparent_bg = true
	artwork_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	world.add_child(artwork_viewport)
	artwork = BoardSurface.new()
	artwork.name = "PremiumBoardSurface"
	artwork_viewport.add_child(artwork)
	var mesh := PlaneMesh.new()
	# 1024px / 64px per cell = 16 world units including the shadow gutter.
	mesh.size = Vector2.ONE * float(BoardSurface.RESOLUTION) / BoardSurface.CELL
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = artwork_viewport.get_texture()
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	board_plane = MeshInstance3D.new()
	board_plane.name = "PremiumBoard"
	board_plane.mesh = mesh
	board_plane.material_override = material
	board_plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	board_plane.position = Vector3(0, 0.20, 0)
	world.add_child(board_plane)

func apply_state(state: Dictionary, self_id: String, highlight_color: String = "") -> void:
	var present: Dictionary = {}
	var dice_value := int(state.dice) if state.get("dice") != null else 0
	for token in state.get("tokens", []):
		present[str(token.id)] = true
	for id in pawns.keys():
		if not present.has(id):
			pawns[id].queue_free()
			pawns.erase(id)
			tokens.erase(id)
			display_positions.erase(id)
	var active_color := ""
	for player in state.get("players", []):
		if player.id == state.get("currentPlayer"):
			active_color = str(player.color)
	for token in state.get("tokens", []):
		var id := str(token.id)
		var index := int(id.get_slice("-", id.get_slice_count("-") - 1))
		if not pawns.has(id):
			var pawn := Pawn.new()
			world.add_child(pawn)
			pawn.configure(id, BOARD_COLORS[token.color])
			pawn.finish_badge = make_completion_check()
			pawns[id] = pawn
		var pawn: Node3D = pawns[id]
		pawn.reduced_motion = reduced_motion
		pawn.position = world_position(str(token.color), int(token.position), index)
		var completed := int(token.position) >= BoardMath.HOME
		pawn.scale = Vector3.ONE * (0.64 if completed else 1.0)
		pawn.set_completed(completed)
		if completed:
			place_completion_check(pawn)
		pawn.legal_move = not completed and state.get("currentPlayer") == self_id and state.get("phase") == "moving" and token.color == active_color and BoardMath.legal(token, dice_value, state.get("tokens",[]))
		var fits_roll: bool = state.get("phase") == "moving" and BoardMath.legal(token, dice_value, state.get("tokens",[]))
		pawn.highlight = not completed and fits_roll and state.get("phase") in ["rolling","moving"] and token.color == (highlight_color if not highlight_color.is_empty() else active_color)
		tokens[id] = token.duplicate()
		display_positions[id] = int(token.position)
	layout_stacks()
	show_ranks(state)
	show_departed(state)

func make_completion_check() -> Control:
	# Flat canvas overlay avoids 3D alpha sorting and font/glyph dependencies.
	var badge := Control.new()
	badge.name = "CompletedPawnCheck"
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.size = Vector2(16, 16)
	badge.draw.connect(func():
		badge.draw_circle(Vector2(8, 8), 7, Design.GOLD)
		badge.draw_circle(Vector2(8, 8), 6, Color("10213c"))
		badge.draw_polyline(PackedVector2Array([Vector2(4, 8), Vector2(7, 11), Vector2(12, 5)]), Design.GOLD, 2.0, true)
	)
	viewport.add_child(badge)
	badge.hide()
	return badge

func place_completion_check(pawn: Node3D) -> void:
	# Changing between sidebars and rows reparents the board. A pawn's exit
	# cleanup can free its canvas badge while retaining the pawn itself.
	if not is_instance_valid(pawn.finish_badge):
		pawn.finish_badge = make_completion_check()
	pawn.finish_badge.visible = pawn.completed
	# Keep the canvas overlay at the same visible size at any render density.
	pawn.finish_badge.scale = Vector2(viewport.size)/size
	pawn.finish_badge.position = camera.unproject_position(pawn.visual.to_global(Vector3(0, 1.46, 0.54))) - pawn.finish_badge.size * pawn.finish_badge.scale * 0.5

func make_badge(text: String, color: Color, at: Vector3) -> Label3D:
	var badge := Label3D.new()
	badge.text = text
	badge.modulate = color
	badge.outline_modulate = Color("101c30")
	badge.outline_size = 12
	badge.font_size = 48
	badge.pixel_size = 0.012
	badge.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	badge.no_depth_test = true
	badge.position = at
	world.add_child(badge)
	return badge

func layout_stacks(moving_id: String = "") -> void:
	for badge in stack_labels:
		badge.queue_free()
	stack_labels.clear()
	var groups: Dictionary = {}
	for id in tokens:
		var token: Dictionary = tokens[id]
		var displayed := int(display_positions.get(id, token.position))
		if id == moving_id:
			continue
		if not moving_id.is_empty():
			var index := int(str(id).get_slice("-",str(id).get_slice_count("-")-1))
			pawns[id].position = world_position(str(token.color),displayed,index)
			pawns[id].scale = Vector3.ONE * (0.64 if displayed >= BoardMath.HOME else 1.0)
		if displayed <= 0 or displayed >= BoardMath.HOME:
			continue
		var cell := BoardMath.coordinate(str(token.color),displayed,0)
		var key := str(cell)
		if not groups.has(key):
			groups[key] = []
		groups[key].append(id)
	for ids in groups.values():
		if ids.size() < 2:
			continue
		ids.sort()
		var color_groups: Dictionary = {}
		var center := world_position(str(tokens[ids[0]].color), int(display_positions[ids[0]]), 0)
		for id in ids:
			var color: String = tokens[id].color
			if not color_groups.has(color):
				color_groups[color] = []
			color_groups[color].append(id)
		var colors: Array = color_groups.keys()
		colors.sort()
		for i in range(colors.size()):
			var members: Array = color_groups[colors[i]]
			var offset := Vector3((i-(colors.size()-1)*0.5)*0.56,0,0)
			if colors.size() > 2:
				offset = Vector3((i%2-0.5)*0.55,0,(floor(float(i)/2)-0.5)*0.55)
			for j in range(members.size()):
				var pawn: Node3D = pawns[members[j]]
				var fan := (j - (members.size() - 1) * 0.5) * 0.13
				pawn.position = center+offset+Vector3(fan,0,-fan)
				pawn.scale = Vector3.ONE*(0.80 if colors.size() == 1 else 0.64)
			var representative: Node3D = pawns[members[0]]
			var badge := make_badge(str(members.size()),Color("142a46"),representative.visual.to_global(Vector3(0,1.05,0.51)))
			badge.pixel_size = 0.008
			badge.outline_size = 2
			badge.outline_modulate = Color.WHITE
			badge.set_meta("pin",members[0])
			stack_labels.append(badge)

func _process(_delta: float) -> void:
	for badge in stack_labels:
		var id: String = badge.get_meta("pin","")
		if pawns.has(id):
			badge.position = pawns[id].visual.to_global(Vector3(0,1.05,0.51))
	for pawn in pawns.values():
		if pawn.completed:
			place_completion_check(pawn)

func show_ranks(state: Dictionary) -> void:
	var order: Array = state.get("finishOrder",[])
	for id in rank_labels.keys():
		if not order.has(id):
			rank_labels[id].queue_free()
			rank_labels.erase(id)
	for player in state.get("players",[]):
		var rank := order.find(player.id)
		if rank < 0 or rank_labels.has(player.id):
			continue
		var center := world_position(str(player.color),0,0).lerp(world_position(str(player.color),0,3),0.5)
		# A crown-and-rank badge stays on the winner's home dock, matching the
		# celebratory board treatment instead of only showing the results dialog.
		var badge := make_badge("♛\n"+["1st","2nd","3rd","4th"][rank],BOARD_COLORS[player.color],center+Vector3(0,0.72,0.75))
		badge.font_size = 58
		badge.pixel_size = 0.009
		rank_labels[player.id] = badge
		if not reduced_motion:
			badge.scale = Vector3.ONE*0.35
			var tween := badge.create_tween()
			tween.tween_property(badge,"scale",Vector3.ONE*1.2,0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tween.parallel().tween_property(badge,"rotation:y",TAU*2.0,0.65).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tween.tween_property(badge,"scale",Vector3.ONE,0.20)

func make_trail_pool() -> void:
	# One soft radial texture and a bounded pool: no shaders or per-step nodes.
	trail_texture = Design.pawn_shadow_texture()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.85,0.85)
	var pool := Node3D.new()
	pool.name = "StepShadowPool"
	world.add_child(pool)
	for index in range(TRAIL_POOL_SIZE):
		var mark := MeshInstance3D.new()
		mark.mesh = mesh
		var finish := StandardMaterial3D.new()
		finish.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		finish.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		finish.cull_mode = BaseMaterial3D.CULL_DISABLED
		finish.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		# The board's transparent gutter makes its entire plane alpha-sorted.
		# Draw marks afterward so distant track cells cannot hide their decals.
		finish.render_priority = 1
		finish.albedo_texture = trail_texture
		mark.material_override = finish
		mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mark.rotation.x = -PI / 2
		mark.hide()
		pool.add_child(mark)
		trail_pool.append(mark)

func leave_trail(at: Vector3, color: Color) -> void:
	if reduced_motion:
		return
	var mark: MeshInstance3D = null
	for available in trail_pool:
		if not available.visible:
			mark = available
			break
	if mark == null:
		mark = trails[0]
		clear_trail(mark)
	var finish := mark.material_override as StandardMaterial3D
	# Preserve the pawn hue rather than washing it out with white.
	finish.albedo_color = Color(color, Design.TOKENS.step_shadow_opacity)
	mark.position = Vector3(at.x, 0.224, at.z)
	mark.show()
	trails.append(mark)
	var tween := create_tween()
	trail_fades[mark] = tween
	tween.tween_interval(Design.TOKENS.step_shadow_hold)
	tween.tween_property(finish, "albedo_color:a", 0.0, Design.TOKENS.step_shadow_fade).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func(): clear_trail(mark))

func clear_trail(mark: MeshInstance3D) -> void:
	if trail_fades.has(mark):
		var tween: Tween = trail_fades[mark]
		if tween.is_valid():
			tween.kill()
		trail_fades.erase(mark)
	trails.erase(mark)
	mark.hide()

func highlight_player(color: String, dice_value: int) -> void:
	for id in pawns:
		pawns[id].highlight = tokens[id].color == color and BoardMath.legal(tokens[id],dice_value,tokens.values())

func begin_move_preview(id: String, dice_value: int) -> void:
	if reduced_motion or not move_preview.is_empty() or not pawns.has(id) or not pawns[id].legal_move:
		return
	var token: Dictionary = tokens[id]
	if not BoardMath.legal(token,dice_value,tokens.values()):
		return
	var start := int(token.position)
	var landing := 1 if start == 0 else start+1
	var finish := 1 if start == 0 else start+dice_value
	var index := int(id.get_slice("-",id.get_slice_count("-")-1))
	var preview := {"id":id,"from":start,"to":finish,"landing":landing,"origin":pawns[id].position,"done":false,"cancelled":false,"confirmed":false}
	move_preview = preview
	layout_stacks(id)
	pawns[id].scale = Vector3.ONE
	# Start only the first visual hop. Game state remains server-authoritative.
	await pawns[id].hop_to(world_position(str(token.color),landing,index),0.24,false)
	preview.done = true
	move_preview_finished.emit()

func cancel_move_preview() -> void:
	if move_preview.is_empty() or move_preview.confirmed:
		return
	var preview := move_preview
	move_preview = {}
	preview.cancelled = true
	if pawns.has(preview.id):
		pawns[preview.id].cancel_hop(preview.origin)
		layout_stacks()

func animate_move(event: Dictionary) -> void:
	var id := str(event.get("tokenId", ""))
	if not pawns.has(id):
		return
	var token: Dictionary = tokens[id]
	var index := int(id.get_slice("-", id.get_slice_count("-") - 1))
	var start := int(event.get("from", token.position))
	var finish := int(event.get("to", token.position))
	if int(display_positions.get(id, start)) == finish:
		return
	var steps := 1 if start == 0 else maxi(0, mini(finish, BoardMath.HOME) - mini(start, BoardMath.HOME))
	var duration := float(event.get("durationMs", steps*240)) / 1000.0
	var consumed := 0
	if not move_preview.is_empty():
		var preview := move_preview
		if preview.id == id and preview.from == start and preview.to == finish:
			preview.confirmed = true
			if not preview.done:
				await move_preview_finished
			move_preview = {}
			consumed = 1
			display_positions[id] = int(preview.landing)
			step_landed.emit(id)
		else:
			cancel_move_preview()
	layout_stacks(id)
	pawns[id].scale = Vector3.ONE
	if consumed == 0:
		leave_trail(pawns[id].position,BOARD_COLORS[token.color])
	for step in range(consumed,steps):
		var landing := finish if start == 0 else start + step + 1
		var destination := world_position(str(token.color), landing, index)
		await pawns[id].hop_to(destination, maxf(0.24,duration / maxf(steps, 1)), reduced_motion)
		if step < steps-1:
			leave_trail(destination,BOARD_COLORS[token.color])
		display_positions[id] = landing
		step_landed.emit(id)
	display_positions[id] = finish
	if finish >= BoardMath.HOME:
		pawns[id].scale = Vector3.ONE * 0.64
		pawns[id].set_completed(true)
		place_completion_check(pawns[id])
	for captured_id in event.get("captured", []):
		if pawns.has(captured_id):
			token_captured.emit(id,str(captured_id))
			await animate_capture(str(captured_id))
	layout_stacks()

func animate_capture(id: String) -> void:
	if not pawns.has(id):
		return
	var from := int(display_positions.get(id,tokens[id].position))
	if from <= 0:
		return
	var pawn: Node3D = pawns[id]
	var color := str(tokens[id].color)
	var index := int(id.get_slice("-",id.get_slice_count("-")-1))
	pawn.legal_move = false
	pawn.highlight = false
	pawn.selection_enabled = false
	pawn.scale = Vector3.ONE
	var points: Array[Vector3] = []
	var durations: Array[float] = []
	var positions: Array[int] = []
	for landing in range(from-1,-1,-1):
		points.append(world_position(color,landing,index))
		durations.append((CAPTURE_HOME_MS if landing == 0 else CAPTURE_STEP_MS)/1000.0)
		positions.append(landing)
	var passed := func(point_index: int):
		display_positions[id] = positions[point_index]
		# Capture progress is deliberately separate from audible step landings.
		capture_passed.emit(id)
	pawn.glide_passed.connect(passed)
	await pawn.glide_path(points,durations,reduced_motion)
	pawn.glide_passed.disconnect(passed)

func reconcile_state(snapshot: Dictionary) -> void:
	# A resync can arrive without its TOKEN_MOVED event. Animate the visible
	# progress to the snapshot, but never replay hops already presented.
	var incoming: Array = snapshot.get("tokens", [])
	# A fresh board/rematch is a reset, not a set of captures to replay.
	if snapshot.get("phase", "") == "lobby" or incoming.all(func(token): return int(token.position) == 0):
		return
	for token in incoming:
		var id := str(token.id)
		if not pawns.has(id):
			continue
		var from := int(display_positions.get(id, tokens[id].position))
		var to := int(token.position)
		if to > from:
			if from == 0 and to > 1:
				await animate_move({"tokenId": id, "from": 0, "to": 1, "durationMs": 240})
				from = 1
			await animate_move({"tokenId": id, "from": from, "to": to, "durationMs": maxi(1, to - from) * 240})
		elif to == 0 and from > 0:
			token_captured.emit("",id)
			await animate_capture(id)

func token_at_screen(point: Vector2) -> String:
	point = point * Vector2(viewport.size) / size
	# Test the complete visible pin, including its animated head, rather than
	# only the board-level base collider. Ignore non-selectable occluders.
	var selected := ""
	var nearest := INF
	for id in pawns:
		var pawn: Node3D = pawns[id]
		if not pawn.legal_move or pawn.moving:
			continue
		var pin: Node3D = pawn.visual
		var corners := [Vector3(-0.58,0,0.22),Vector3(0.58,0,0.22),Vector3(0.58,1.72,0.22),Vector3(-0.58,1.72,0.22)]
		var rect := Rect2(camera.unproject_position(pin.to_global(corners[0])),Vector2.ZERO)
		for corner in corners:
			rect = rect.expand(camera.unproject_position(pin.to_global(corner)))
		if rect.grow(3.0).has_point(point):
			var distance := point.distance_squared_to(rect.get_center())
			if distance < nearest:
				nearest = distance
				selected = str(id)
	return selected

func _gui_input(event: InputEvent) -> void:
	if not enabled or not camera:
		return
	var point := Vector2.ZERO
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		point = event.position
	elif event is InputEventScreenTouch and event.pressed:
		point = event.position
	else:
		return
	var id := token_at_screen(point)
	if not id.is_empty():
		token_pressed.emit(id)

func show_departed(state: Dictionary) -> void:
	var departed: Array = state.get("departedPlayers",[])
	for id in departure_labels.keys():
		if not departed.any(func(player): return str(player.id) == str(id)):
			departure_labels[id].queue_free()
			departure_labels.erase(id)
	for player in departed:
		if departure_labels.has(player.id):
			continue
		var center := world_position(str(player.color),0,0).lerp(world_position(str(player.color),0,3),0.5)
		var badge := make_badge("LEFT THE\nGAME",Color("14263f"),center+Vector3(0,0.8,0))
		# Draw after the alpha-sorted printed board so far corners stay readable.
		badge.render_priority = 8
		badge.outline_render_priority = 7
		badge.outline_modulate = Color("fff2cf")
		badge.outline_size = 8
		badge.font_size = 54
		badge.pixel_size = 0.012
		departure_labels[player.id] = badge

func animate_departures(snapshot: Dictionary) -> void:
	var present: Dictionary = {}
	for token in snapshot.get("tokens",[]):
		present[str(token.id)] = true
	var leaving: Array = []
	for id in pawns:
		if not present.has(id):
			leaving.append(id)
	if leaving.is_empty() or reduced_motion:
		return
	for badge in stack_labels:
		badge.hide()
	for id in leaving:
		var pawn = pawns[id]
		pawn.vanish()
		departure_smoke(pawn.position)
	await get_tree().create_timer(1.35).timeout

func departure_smoke(at: Vector3) -> void:
	# Soft overlapping billows rise as a ghost silhouette fades into shadow.
	for index in range(7):
		var puff := MeshInstance3D.new()
		var mesh := QuadMesh.new()
		mesh.size = Vector2.ONE*(0.65+index*0.09)
		puff.mesh = mesh
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		material.render_priority = 3
		material.albedo_texture = trail_texture
		material.albedo_color = Color(0.14,0.17,0.22,0.0)
		puff.material_override = material
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		puff.position = at+Vector3(sin(index*2.4)*0.25,0.25+index*0.12,cos(index*2.4)*0.18)
		world.add_child(puff)
		var tween := puff.create_tween()
		tween.tween_interval(index*0.035)
		tween.tween_property(material,"albedo_color:a",0.65,0.22)
		tween.parallel().tween_property(puff,"position",puff.position+Vector3(sin(index)*0.3,0.65,0),0.5)
		tween.parallel().tween_property(puff,"scale",Vector3.ONE*2.3,0.5)
		tween.tween_property(material,"albedo_color:a",0.0,0.55)
		tween.tween_callback(puff.queue_free)
