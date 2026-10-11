extends SubViewportContainer

signal token_pressed(token_id: String)
signal step_landed(token_id: String)
signal token_captured(mover_id: String, captured_id: String)
const Design = preload("res://scripts/design.gd")
const BoardMath = preload("res://scripts/board_math.gd")
const Pawn = preload("res://scripts/pawn.gd")
const Geometry = preload("res://scripts/geometry.gd")
const BOARD_COLORS = Design.COLORS
var viewport: SubViewport
var world: Node3D
var camera: Camera3D
var pawns: Dictionary = {}
var tokens: Dictionary = {}
var enabled := false
var reduced_motion := false
var mats: Dictionary = {}
var board_shader: Shader
var stack_labels: Array[Label3D] = []
var rank_labels: Dictionary = {}
var trails: Array[MeshInstance3D] = []
var trail_shader: Shader

func _ready() -> void:
	stretch = true
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
	make_board()
	_fit_camera()

func _fit_camera() -> void:
	if camera and size.x > 0:
		# Fit the projected rail AND tall pins, including stack offsets, their
		# idle bounce and movement hop. Width-only fitting clips the top track
		# on short screens and lets pins spill behind the profile cards.
		var up := camera.global_basis.y
		var bottom := INF
		var top := -INF
		for x in [-8.1,8.1]:
			for z in [-8.1,8.1]:
				var rail_height := up.dot(Vector3(x,-0.8,z))
				bottom = minf(bottom,rail_height)
				for y in [0.0,0.5]:
					top = maxf(top,up.dot(Vector3(x,y,z)))
		for z in [-7.25,7.25]:
			top = maxf(top,up.dot(Vector3(0,0.9,z))+1.72)
		var center := up*((top+bottom)*0.5)
		camera.position = Vector3(0,30,5)+center
		camera.keep_aspect = Camera3D.KEEP_WIDTH
		camera.size = maxf(16.3,(top-bottom+0.25)*size.x/maxf(size.y,1.0))

func mat(color: Color, wood: bool = false) -> ShaderMaterial:
	# Matte printed board: flat color surfaces still receive the tokens' shadows.
	if not board_shader:
		board_shader = Shader.new()
		board_shader.code = """
		shader_type spatial;
		render_mode diffuse_burley, specular_schlick_ggx;
		uniform vec4 tint : source_color;
		uniform float wood_amount = 0.0;
		varying vec3 surface_normal;
		varying vec3 surface_position;
		void vertex() {
			surface_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
			surface_position = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
		}
		void fragment() {
			float grain = sin(surface_position.x*17.0+sin(surface_position.z*0.65)*1.7)*sin(surface_position.x*3.2+surface_position.z*0.19)*wood_amount;
			float chroma = max(tint.r,max(tint.g,tint.b))-min(tint.r,min(tint.g,tint.b));
			float depth = 1.0;
			if (chroma > 0.08 && abs(surface_position.x) > 1.5 && abs(surface_position.z) > 1.5) {
				vec2 home = (abs(surface_position.xz)-vec2(4.5))/2.9;
				depth = mix(1.06,0.86,smoothstep(0.3,1.0,max(abs(home.x),abs(home.y))));
			}
			ALBEDO = tint.rgb * (chroma < 0.08 ? 0.88 : 0.75) * (1.0+grain) * depth;
			ROUGHNESS = 1.0;
			METALLIC = 0.0;
			SPECULAR = 0.0;
		}
		"""
	var key := color.to_html()+str(wood)
	if not mats.has(key):
		var material := ShaderMaterial.new()
		material.shader = board_shader
		material.set_shader_parameter("tint",color)
		material.set_shader_parameter("wood_amount",0.075 if wood else 0.0)
		mats[key] = material
	return mats[key]

func flat_rect(at: Vector3, dimensions: Vector2, color: Color) -> MeshInstance3D:
	var mesh := PlaneMesh.new()
	mesh.size = dimensions
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = mat(color)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.position = at
	world.add_child(instance)
	return instance

func disc(at: Vector3, radius: float, color: Color) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.001
	mesh.radial_segments = 24
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = mat(color)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.position = at
	world.add_child(instance)

func triangle(points: Array, color: Color) -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	mesh.surface_set_normal(Vector3.UP)
	var ordered := points.duplicate()
	if (points[1]-points[0]).cross(points[2]-points[0]).y > 0:
		ordered.reverse()
	for point in ordered:
		mesh.surface_add_vertex(point)
	mesh.surface_end()
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = mat(color)
	world.add_child(instance)

func star(at: Vector3, colored: bool = false) -> void:
	for index in range(10):
		var a := index * TAU / 10 - PI / 2
		var b := (index + 1) * TAU / 10 - PI / 2
		var r1 := 0.32 if index % 2 == 0 else 0.14
		var r2 := 0.14 if index % 2 == 0 else 0.32
		triangle([at, at + Vector3(cos(a)*r1, 0, sin(a)*r1), at + Vector3(cos(b)*r2, 0, sin(b)*r2)], Color.WHITE if colored else Color("4b5568"))

func arrow(at: Vector3, direction: Vector3, color: Color) -> void:
	var side := Vector3(-direction.z, 0, direction.x)
	triangle([at+direction*0.32, at-direction*0.03+side*0.22, at-direction*0.03-side*0.22], color)
	var tail := at-direction*0.29
	triangle([tail-side*0.085, tail+side*0.085, at+side*0.085],color)
	triangle([tail-side*0.085, at+side*0.085, at-side*0.085],color)

func make_board() -> void:
	flat_rect(Vector3(0,0.18,0),Vector2(15.35,15.35),Color("18304a"))
	flat_rect(Vector3(0,0.19,0),Vector2(15.05,15.05),Color("556071"))
	var corners := [Vector2i(0,0), Vector2i(0,9), Vector2i(9,9), Vector2i(9,0)]
	for seat in range(4):
		var color: Color = BOARD_COLORS[BoardMath.COLORS[seat]]
		var corner: Vector2i = corners[seat]
		var center := Vector3(corner.y - 4.5, 0, corner.x - 4.5)
		flat_rect(center+Vector3(0,0.20,0),Vector2(5.98,5.98),color)
		# A printed outline and white inset, not a recessed tray or raised frame.
		flat_rect(center+Vector3(0,0.202,0),Vector2(4.5,4.5),color.darkened(0.22)).name = "HomeRim%d" % seat
		flat_rect(center+Vector3(0,0.204,0),Vector2(4.44,4.44),Color.WHITE).name = "HomeFloor%d" % seat
		for index in range(4):
			var dock := BoardMath.world(BoardMath.COLORS[seat], 0, index)
			dock.y = 0.206
			disc(dock,0.37,color.lightened(0.60))
			disc(dock+Vector3(0,0.002,0),0.29,color.lightened(0.83))
	for row in range(15):
		for col in range(15):
			if (row < 6 or row > 8) and (col < 6 or col > 8):
				continue
			if row >= 6 and row <= 8 and col >= 6 and col <= 8:
				continue
			var color := Color.WHITE
			if row == 7 and col >= 1 and col <= 5:
				color = BOARD_COLORS.coral
			elif col == 7 and row >= 1 and row <= 5:
				color = BOARD_COLORS.sun
			elif row == 7 and col >= 9 and col <= 13:
				color = BOARD_COLORS.mint
			elif col == 7 and row >= 9 and row <= 13:
				color = BOARD_COLORS.violet
			var coord := [row,col]
			for seat in range(4):
				if coord == BoardMath.TRACK[seat * 13]:
					color = BOARD_COLORS[BoardMath.COLORS[seat]]
			var at := Vector3(col-7,0.20,row-7)
			flat_rect(at,Vector2(0.975,0.975),color)
			if BoardMath.TRACK.find(coord) in BoardMath.SAFE:
				star(at+Vector3(0,0.002,0),color != Color.WHITE)
	var middle := Vector3(0,0.20,0)
	triangle([Vector3(-1.5,0.20,-1.5),Vector3(-1.5,0.20,1.5),middle],BOARD_COLORS.coral)
	triangle([Vector3(-1.5,0.20,-1.5),middle,Vector3(1.5,0.20,-1.5)],BOARD_COLORS.sun)
	triangle([Vector3(1.5,0.20,-1.5),middle,Vector3(1.5,0.20,1.5)],BOARD_COLORS.mint)
	triangle([Vector3(-1.5,0.20,1.5),Vector3(1.5,0.20,1.5),middle],BOARD_COLORS.violet)
	arrow(Vector3(-7,0.202,0),Vector3.LEFT,BOARD_COLORS.coral)
	arrow(Vector3(0,0.202,-7),Vector3.FORWARD,BOARD_COLORS.sun)
	arrow(Vector3(7,0.202,0),Vector3.RIGHT,BOARD_COLORS.mint)
	arrow(Vector3(0,0.202,7),Vector3.BACK,BOARD_COLORS.violet)

func apply_state(state: Dictionary, self_id: String, highlight_color: String = "") -> void:
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
			pawns[id] = pawn
		var pawn: Node3D = pawns[id]
		pawn.reduced_motion = reduced_motion
		pawn.position = BoardMath.world(str(token.color), int(token.position), index)
		pawn.scale = Vector3.ONE
		# Finished pins return to their own docks beneath the placement badge.
		if int(token.position) == 58:
			pawn.position = BoardMath.world(str(token.color),0,index)
		pawn.legal_move = int(token.position) < 58 and state.get("currentPlayer") == self_id and state.get("phase") == "moving" and token.color == active_color and BoardMath.legal(token, int(state.get("dice", 0)))
		pawn.highlight = token.color == highlight_color
		tokens[id] = token.duplicate()
	layout_stacks()
	show_ranks(state)

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
		if id == moving_id:
			continue
		if not moving_id.is_empty():
			var index := int(str(id).get_slice("-",str(id).get_slice_count("-")-1))
			pawns[id].position = BoardMath.world(str(token.color),0 if int(token.position) == 58 else int(token.position),index)
			pawns[id].scale = Vector3.ONE
		if int(token.position) <= 0 or int(token.position) >= 58:
			continue
		var cell := BoardMath.coordinate(str(token.color),int(token.position),0)
		var key := str(cell)
		if not groups.has(key):
			groups[key] = []
		groups[key].append(id)
	for ids in groups.values():
		if ids.size() < 2:
			continue
		ids.sort()
		var color_groups: Dictionary = {}
		var center: Vector3 = pawns[ids[0]].position
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
				pawn.position = center+offset+Vector3(j*0.07,0,-j*0.07)
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
		var center := BoardMath.world(str(player.color),0,0).lerp(BoardMath.world(str(player.color),0,3),0.5)
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

func leave_trail(at: Vector3, color: Color) -> void:
	if reduced_motion:
		return
	var mark := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.85,0.85)
	mark.mesh = mesh
	if not trail_shader:
		trail_shader = Shader.new()
		trail_shader.code = "shader_type spatial; render_mode unshaded,cull_disabled,depth_draw_never; uniform vec4 tint : source_color; uniform float fade = 1.0; void fragment(){float r=length((UV-vec2(0.5))*2.0); ALBEDO=tint.rgb; ALPHA=(1.0-smoothstep(0.0,1.0,r))*0.45*fade;}"
	var finish := ShaderMaterial.new()
	finish.shader = trail_shader
	finish.set_shader_parameter("tint",color)
	mark.material_override = finish
	mark.position = at+Vector3(0,0.025,0)
	mark.rotation.x = -PI/2
	world.add_child(mark)
	trails.append(mark)
	var tween := create_tween()
	tween.tween_method(func(value: float): finish.set_shader_parameter("fade",value),1.0,0.0,0.7)
	tween.tween_callback(func():
		trails.erase(mark)
		mark.queue_free()
	)

func highlight_player(color: String) -> void:
	for id in pawns:
		pawns[id].highlight = tokens[id].color == color

func animate_move(event: Dictionary) -> void:
	var id := str(event.get("tokenId", ""))
	if not pawns.has(id):
		return
	var token: Dictionary = tokens[id]
	var index := int(id.get_slice("-", id.get_slice_count("-") - 1))
	var start := int(event.get("from", token.position))
	var finish := int(event.get("to", token.position))
	var steps := 1 if start == 0 else finish - start
	var duration := float(event.get("durationMs", steps*160)) / 1000.0
	layout_stacks(id)
	pawns[id].scale = Vector3.ONE
	for step in range(steps):
		var landing := finish if start == 0 else start + step + 1
		# Completed pawns land in their own dock instead of briefly moving to the
		# center, where they can be hidden by the HUD during the state update.
		var destination := BoardMath.world(str(token.color),0,index) if landing >= 58 else BoardMath.world(str(token.color),landing,index)
		leave_trail(pawns[id].position,BOARD_COLORS[token.color])
		await pawns[id].hop_to(destination, duration / maxf(steps, 1), reduced_motion)
		step_landed.emit(id)
	for captured_id in event.get("captured", []):
		if pawns.has(captured_id):
			token_captured.emit(id,str(captured_id))
			var captured: Dictionary = tokens[captured_id]
			var captured_index := int(str(captured_id).get_slice("-", str(captured_id).get_slice_count("-") - 1))
			await pawns[captured_id].hop_to(BoardMath.world(str(captured.color), 0, captured_index), 0.20, reduced_motion)

func token_at_screen(point: Vector2) -> String:
	# Test the complete visible pin, including its animated head, rather than
	# only the board-level base collider. Ignore non-selectable occluders.
	var selected := ""
	var nearest := INF
	for id in pawns:
		var pawn: Node3D = pawns[id]
		if not pawn.legal_move or pawn.moving:
			continue
		var pin: Node3D = pawn.visual
		var corners := [Vector3(-0.49,0,0.22),Vector3(0.49,0,0.22),Vector3(0.49,1.55,0.22),Vector3(-0.49,1.55,0.22)]
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
