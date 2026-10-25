extends SceneTree

const BoardMath = preload("res://scripts/board_math.gd")
const MainScene = preload("res://scenes/main.tscn")
const Geometry = preload("res://scripts/geometry.gd")
const Dice = preload("res://scripts/dice.gd")
const Board = preload("res://scripts/board.gd")
const Pawn = preload("res://scripts/pawn.gd")
var failures := 0
var checks := 0
var host
var friend

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func wait_until(condition: Callable, seconds: float = 8.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds*1000)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await create_timer(0.02).timeout
	return bool(condition.call())

func run() -> void:
	check_mesh_winding(Geometry.bevel_box(Vector3(5.9,0.15,5.9)),"Beveled board")
	check_mesh_winding(Geometry.rounded_slab(Vector3(5.78,0.28,5.78),0.3),"Rounded home tray")
	var dice_mesh = Dice.new()
	check_mesh_winding(dice_mesh.rounded_cube(),"Rounded dice")
	dice_mesh.free()
	check(BoardMath.TRACK.size() == 52, "Track must have 52 cells")
	for color in BoardMath.COLORS:
		for index in range(4):
			for position in range(59):
				var coordinate := BoardMath.coordinate(color,position,index)
				check(coordinate.x >= 0 and coordinate.x < 15 and coordinate.y >= 0 and coordinate.y < 15, "Coordinate out of bounds")
	check(not BoardMath.legal({"position":0},5), "Base requires six")
	check(BoardMath.legal({"position":0},6), "Six allows base entry")
	check(BoardMath.legal({"position":BoardMath.HOME-1},1), "Final lane cell can enter the finish triangle")
	check(not BoardMath.legal({"position":BoardMath.HOME},1), "Finish triangle is immediately terminal")
	check(not BoardMath.legal({"position":58},1), "Legacy finished pawn cannot move")
	await check_token_framing()
	# Two complete Godot clients connected to the real local Node.js server.
	host = MainScene.instantiate()
	friend = MainScene.instantiate()
	root.add_child(host)
	root.add_child(friend)
	check(await wait_until(func(): return host.online and friend.online), "Both Godot clients must connect")
	if not host.online or not friend.online:
		finish()
		return
	host.name_input.text = "Godot Host"
	host.request_room(false)
	check(await wait_until(func(): return not host.room_code.is_empty() and not host.pending), "Host creates room")
	friend.name_input.text = "Godot Friend"
	friend.join_input.text = host.room_code.to_lower()
	friend.request_room(true)
	check(await wait_until(func(): return host.game.get("players",[]).size() == 2 and friend.game.get("players",[]).size() == 2), "Friend joins same room")
	check(host.room_code == friend.room_code, "Room codes match")
	check(host.cards.size() == 4 and friend.cards.size() == 4, "Four persistent cards")
	host.send({"type":"START_GAME"})
	check(await wait_until(func(): return host.game.get("phase") == "rolling" and friend.game.get("phase") == "rolling"), "Host starts match")
	check(host.board.pawns.size() == 8, "Eight pawns modeled for two players")
	check(host.turn_duration_ms == 30000 and friend.turn_duration_ms == 30000,"Both clients receive the 30-second phase duration")
	check(host.board.board_plane.mesh is PlaneMesh,"Board artwork is a flat printed surface")
	check(host.board.artwork_viewport.size.x == 1024 and host.board.artwork_viewport.size.y >= 1024,"Board artwork cache matches its rectangular layout")
	for seat in range(4):
		check(BoardMath.world(BoardMath.COLORS[seat],0,0).y > host.board.board_plane.position.y,"Home pawn sits above the flat board")
	for pawn in host.board.pawns.values():
		var body: MeshInstance3D = pawn.get_node("PinVisual/PinBody")
		check(body.material_override is ShaderMaterial, "Location pin has portable glossy studio material")
		check_mesh_winding(body.mesh,"Beveled location pin")
		check(body.mesh.get_aabb().size.y > 1.4, "Token has a tall location-pin silhouette")
		check(pawn.has_node("PinVisual/PinBadge"), "Location pin has a contrasting round badge")
		check(is_instance_valid(pawn.cell_shadow) and pawn.cell_shadow.visible, "Pawn has grounding contact shadow")
	check(host.game_view.visible and not host.content.get_node("SetupScroll").visible, "Game is non-scrollable")
	await process_frame
	check(host.game_background.visible, "Clean game background is visible during play")
	check(host.game_background.get_child(0) is ColorRect, "Game background has no decorative artwork")
	check(host.cards[0].avatar.size.y > host.cards[0].roll.size.y and host.cards[0].roll.size.y >= 48, "Avatars are taller than the dice while preserving a usable roll button")
	check(not Rect2(host.board.printed_rect().position+host.board.global_position,host.board.printed_rect().size).intersects(host.cards[0].get_global_rect()), "Top player card does not overlap board")
	check(not Rect2(host.board.printed_rect().position+host.board.global_position,host.board.printed_rect().size).intersects(host.cards[3].get_global_rect()), "Bottom player card does not overlap board")
	check(host.cards[1].invite.visible and host.cards[3].invite.visible and not host.cards[2].invite.visible, "Only open seats expose invite controls")
	check(host.cards[0].player_id == host.self_id and host.cards[2].player_id == friend.self_id,"Two-player profiles occupy opposite board corners")
	check(JSON.stringify(host.game) == JSON.stringify(friend.game), "Initial authoritative states match")
	check(host.cards[2].gift.visible and not host.cards[2].gift.disabled, "Opponent has an enabled sticker button")
	check(host.cards[2].gift.size.x == 32 and host.cards[2].gift.size.y == 24,"Emoji icon uses compact reference-style dimensions")
	check(host.cards[0].chat.visible and host.cards[0].camera_button.visible and not host.cards[0].gift.visible,"Own profile shows only chat and camera, never a self-send emoji")
	check(not host.cards[2].chat.visible and not host.cards[2].camera_button.visible and host.cards[2].gift.visible,"Opponent profile shows only an emoji icon")
	check(friend.cards[2].chat.visible and not friend.cards[0].chat.visible,"Each client sees controls only on their own profile")
	check(not host.cards[1].gift.visible and not host.cards[1].chat.visible,"Open seats show no social icons")
	check(host.cards[0].actions.global_position.y >= host.cards[0].panel.get_global_rect().end.y,"Social icons sit below the rounded profile panel")
	check(host.cards[0].status_label.size.x >= 50 and host.cards[0].status_label.text.contains(":"),"Profile header reserves a visible countdown beside the name")
	host.cards[0].chat.pressed.emit()
	check(host.chat_dialog.visible,"Own chat icon opens table chat")
	host.chat_dialog.hide()
	host.cards[0].camera_button.pressed.emit()
	check(not host.menu.visible and host.call_error.visible,"Headless camera action explains the supported web/Android call platforms")
	host.call_error.hide()
	host.open_sticker_picker(host.self_id)
	check(not host.sticker_picker.visible,"Self-targeted sticker picker is rejected")
	check(is_equal_approx(host.cards[2].gift.global_position.x,host.cards[2].global_position.x),"Single opponent emoji sits at the beginning of its toolbar")
	var original_window_size := root.size
	root.size = Vector2i(420,1000)
	await process_frame
	host._safe_area()
	check(host.board.custom_minimum_size.y > host.content.custom_minimum_size.x,"Board uses spare vertical room instead of capping itself to a square on tall screens")
	root.size = original_window_size
	await process_frame
	host._safe_area()
	var profile = host.cards[2].avatar
	check(profile.clip_contents and is_equal_approx(profile.size.x,profile.size.y),"Avatar is clipped to a square frame")
	for card in host.cards:
		check(card.avatar.size.x >= 52 and is_equal_approx(card.avatar.size.x,card.avatar.size.y),"Mobile portraits stay compact and square")
	check(host.cards[0].name_label.get_global_rect().end.y <= host.cards[0].avatar.global_position.y,"Player name stays above the video square")
	check(not host.cards[0].avatar.get_global_rect().intersects(host.cards[0].roll.get_global_rect()),"Video square and dice do not overlap")
	var photo := GradientTexture2D.new()
	profile.set_portrait(photo)
	check(profile.portrait.visible and profile.portrait.texture == photo and profile.portrait.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_COVERED,"Photo texture replaces avatar and fills frame without distortion")
	profile.set_portrait(null)
	check(not profile.portrait.visible,"Clearing portrait restores illustrated avatar")
	host.cards[2].gift.pressed.emit()
	check(host.sticker_picker.visible and host.sticker_target == friend.self_id, "Gift button opens picker for selected opponent")
	await process_frame
	check(host.sticker_title.text == "Send to Godot Friend","Sticker header names the tapped recipient without a dropdown")
	check(host.sticker_title.size.x >= 160 and host.sticker_title.size.y >= 24 and host.sticker_title.autowrap_mode == TextServer.AUTOWRAP_OFF,"Recipient name remains visible in the compact single-line popup header")
	check(host.sticker_picker.get_child(0).get_child(0).size.y <= 36 and host.sticker_picker.size.y < 440,"Sticker popup has a compact header rather than an oversized blank block")
	var sticker_grid = host.sticker_grid
	var hammer_choice = sticker_grid.get_children().filter(func(choice): return choice.get_child(0).kind == "HAMMER")[0]
	check(hammer_choice.get_child(0).kind == "HAMMER", "Hammer option contains rendered artwork")
	hammer_choice.pressed.emit()
	check(await wait_until(func(): return host.sticker_layer.get_child_count() > 0 and friend.sticker_layer.get_child_count() > 0), "Sticker reaches sender and recipient over real server")
	if host.sticker_layer.get_child_count() > 0 and friend.sticker_layer.get_child_count() > 0:
		check(host.sticker_layer.get_child(0).kind == "HAMMER" and friend.sticker_layer.get_child(0).kind == "HAMMER", "Both clients animate the selected hammer")
		check(host.sticker_layer.get_child(0).get_meta("target_player_id") == friend.self_id, "Sticker animation targets the chosen recipient")
	check(host.notice.text.contains("delivered"), "Delivery confirmation waits for server broadcast")
	check(await wait_until(func(): return host.sticker_layer.get_child_count() == 0 and friend.sticker_layer.get_child_count() == 0,5), "Sticker animation cleans itself up")
	var active = host if host.game.get("currentPlayer") == host.self_id else friend
	# A non-active participant cannot roll through the UI.
	var other = friend if active == host else host
	check(other.cards[0].roll.disabled and other.cards[2].roll.disabled, "Opponent dice controls disabled")
	var dice_contacts: Array[bool] = []
	for card in host.cards:
		card.dice.roll_contact.connect(func(settled: bool, _strength: float): dice_contacts.append(settled))
	for attempt in range(50):
		dice_contacts.clear()
		active = host if host.game.get("currentPlayer") == host.self_id else friend
		var before := int(host.game.version)
		var roll_started := Time.get_ticks_msec()
		active.send({"type":"ROLL_DICE"})
		check(await wait_until(func(): return int(host.game.get("version",0)) > before and not host.presenting and not friend.presenting and not host.processing_events and not friend.processing_events, 6), "Roll completes after presentation")
		if attempt == 0:
			check(Time.get_ticks_msec()-roll_started < 3500,"First roll resumes without an extra three-second pause")
		check(JSON.stringify(host.game) == JSON.stringify(friend.game), "Both clients agree after dice")
		check(dice_contacts.size() == 9 and dice_contacts.back(), "Dice emits eight slowing contacts followed by one settle")
		if host.game.get("phase") == "moving":
			break
	check(host.game.get("phase") == "moving", "A six eventually enables pawn selection")
	if host.game.get("phase") == "moving":
		active = host if host.game.currentPlayer == host.self_id else friend
		var token_id: String = str(active.self_id) + "-0"
		check(active.board.pawns[token_id].legal_move, "Active pawn is selectable")
		check(active.board.custom_minimum_size.y >= 300, "Board remains usable without the yellow instruction strip")
		var pin = active.board.pawns[token_id]
		pin.reduced_motion = true
		pin._process(0)
		check(pin.ring.visible and pin.visual.scale == Vector3.ONE and pin.visual.position.y == 0, "Reduced motion retains legal ring without bounce or scaling")
		pin.reduced_motion = active.reduced_motion
		check(pin.ring.mesh is TorusMesh and pin.ring.material_override.metallic > 0.7, "Selectable feet have a solid metallic ring")
		check(not pin.glow_floor.visible,"Selectable pawn keeps its ring without a colored floor glow")
		for height in [0.05,0.75,1.40]:
			var point: Vector2 = active.board.display_point(active.board.camera.unproject_position(pin.visual.to_global(Vector3(0,height,0.22))))
			check(active.board.token_at_screen(point) == token_id, "Head, center and feet select the complete visible token")
		var observer = friend if active == host else host
		for pawn in observer.board.pawns.values():
			pawn._process(0)
			check(not pawn.ring.visible, "Opponent tokens do not glow on someone else's turn")
		var before := int(host.game.version)
		await physics_frame
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		click.position = active.board.display_point(active.board.camera.unproject_position(active.board.pawns[token_id].global_position + Vector3.UP*0.8))
		active.board._gui_input(click)
		check(active.pending, "3D ray picking submits the legal pawn intent")
		check(await wait_until(func(): return int(host.game.get("version",0)) > before and not host.processing_events and not friend.processing_events), "Pawn move and animation finish")
		check(int(host.board.tokens[token_id].position) == 1, "Pawn enters track")
		check(host.board.pawns[token_id].position.is_equal_approx(host.board.world_position(str(host.board.tokens[token_id].color),1,0)), "3D pawn lands at authoritative coordinate")
		check(JSON.stringify(host.game) == JSON.stringify(friend.game), "Both clients agree after movement")
	host.chat_input.text = "Hello from Godot"
	friend.presenting = true
	host.send_chat()
	check(await wait_until(func(): return friend.chat_log.get_parsed_text().contains("Hello from Godot")), "Room chat reaches friend")
	check(friend.chat_bubbles.entries.has(host.self_id), "Incoming chat appears over sender profile without opening chat")
	check(friend.cards[2].chat.unread,"Incoming chat adds a red unread badge to the owner's chat icon")
	friend.cards[2].chat.pressed.emit()
	check(friend.chat_dialog.visible and not friend.cards[2].chat.unread,"Opening chat clears the unread icon badge")
	friend.chat_dialog.hide()
	check(friend.feedback.last_cue == "chat", "Incoming chat plays notification cue")
	check(friend.presenting, "Chat can arrive without waiting for gameplay presentation")
	friend.presenting = false
	host.board.token_captured.emit(host.self_id+"-0",friend.self_id+"-0")
	check(host.feedback.last_cue == "capture", "Capture presentation triggers its feedback cue")
	check(host.feedback.samples.size() == 7, "Gameplay and sticker audio are preloaded")
	for sample in host.feedback.samples.values():
		check(sample.data.size() > 100 and sample.mix_rate == 22050, "Feedback contains valid PCM samples")
	var pulses: Array[int] = []
	host.feedback.haptic_pulse.connect(func(duration: int): pulses.append(duration))
	host.feedback.haptics_enabled = true
	host.feedback.cue("capture",true)
	await create_timer(0.15).timeout
	check(pulses == [55,30], "Capture requests a distinct two-pulse haptic pattern")
	pulses.clear()
	host.feedback.haptics_enabled = false
	host.feedback.cue("step",true)
	check(pulses.is_empty(), "Vibration setting suppresses haptic pulses")
	friend.chat_bubbles.lifetime = 0.04
	friend.chat_bubbles.reduced_motion = true
	friend.chat_bubbles.show_message(friend.cards[0],"Godot Host","Replacement bubble")
	check(await wait_until(func(): return not friend.chat_bubbles.entries.has(host.self_id),1.0), "Replacement chat bubble expires and removes itself")
	# Presentation fixtures stay client-local and never alter the test server.
	var fixture: Dictionary = host.game.duplicate(true)
	fixture.currentPlayer = host.self_id
	fixture.phase = "moving"
	fixture.dice = 6
	for token in fixture.tokens:
		if token.color == fixture.players[0].color:
			token.position = 1
		elif token.id.ends_with("-0"):
			token.position = (52-int(BoardMath.OFFSETS[token.color]))%52+1
	host.board.apply_state(fixture,host.self_id)
	var distinct: Dictionary = {}
	for i in range(4):
		distinct[str(host.board.pawns[host.self_id+"-"+str(i)].position)] = true
	check(distinct.size() == 4, "Four same-cell pins have distinct visible offsets")
	check(host.board.stack_labels.size() == 2, "Mixed-color stack shows a count for each color")
	for badge in host.board.stack_labels:
		check(badge.text in ["4","1"], "Stack head badge explicitly shows its color group count")
	var stack_pin = host.board.pawns[host.self_id+"-0"]
	var stack_point: Vector2 = host.board.display_point(host.board.camera.unproject_position(stack_pin.visual.to_global(Vector3(0,1.02,0.26))))
	check(host.board.token_at_screen(stack_point).begins_with(host.self_id+"-"), "Mixed stacks cannot let an opponent occlude a selectable pin")
	host.board.leave_trail(Vector3.ZERO,host.board.BOARD_COLORS.coral)
	check(not host.board.trails.is_empty(), "Each step creates a colored fading trail")
	await create_timer(1.55).timeout
	check(host.board.trails.is_empty(), "Step trails clean themselves up")
	fixture.phase = "finished"
	fixture.finishOrder = [host.self_id,friend.self_id]
	fixture.winner = host.self_id
	for token in fixture.tokens:
		if token.color == fixture.players[0].color:
			token.position = BoardMath.HOME
	host.game = fixture.duplicate(true)
	friend.game = fixture.duplicate(true)
	host.show_state()
	host.refresh_controls()
	await process_frame
	check(host.result.size.y < 420, "Ranked results remain a compact popup")
	check(host.result.visible, "Host receives ranked results popup")
	host.result.hide() # Both fixture clients share one root, unlike real devices.
	friend.show_state()
	check(friend.result.visible, "Friend receives ranked results popup")
	check(host.result.get_ok_button().text == "OK" and friend.result.get_ok_button().text == "OK", "Host and guests have the same OK action")
	check(host.result.borderless and host.result.title.is_empty(), "Results have no match-complete heading")
	check(friend.result_celebration.visible, "Results popup includes its own celebration")
	check(host.cards[0].celebration.visible and host.cards[0].celebration.rank == 0, "First finisher receives a persistent celebration in their own card")
	check(host.result_list.get_child_count() == 2, "Results show an avatar row for every ranked player")
	check(host.result_stats.text.contains("1st") and host.result_stats.text.contains("2nd"), "Results list every placement")
	check(host.board.rank_labels.size() == 2, "Each home box receives a placement badge")
	fixture.phase = "rolling"
	fixture.finishOrder = []
	for token in fixture.tokens:
		token.position = 0
	host.game = fixture
	host.show_state()
	host.refresh_controls()
	check(not host.result.visible and host.board.rank_labels.is_empty(), "Restart clears results and placement badges")
	check(not host.cards[0].celebration.visible and not host.cards[0].celebration.is_processing(), "Restart clears the celebration and its animation processing")
	for kind in host.StickerArt.CATALOG:
		host.show_sticker({"targetPlayerId":friend.self_id,"fromPlayerId":host.self_id,"sticker":kind})
		await process_frame
		var effect = host.sticker_layer.get_child(host.sticker_layer.get_child_count()-1)
		effect._process(1.1)
		check(effect.art.model.get_child_count() > 0,"Sticker %s has actual 3D geometry" % kind)
		check(effect.size.x >= 64 and effect.size.x <= 104,"Sticker %s uses bounded responsive size" % kind)
		var bounds: Vector2 = host.get_viewport_rect().size
		check(effect.position.x >= 0 and effect.position.y >= 0 and effect.position.x+effect.size.x <= bounds.x and effect.position.y+effect.size.y <= bounds.y,"Sticker %s stays inside screen: %s %s in %s" % [kind,effect.position,effect.size,bounds])
		if kind == "HAMMER":
			check(effect.strikes == 1 and effect.recipient.avatar.reaction == "hit","Hammer contact triggers recipient recoil")
		if kind in ["GIFT","CLAP","FIRE","LOVE"]:
			check(not effect.art.parts.is_empty(),"Sticker %s has separately animated parts" % kind)
		effect.queue_free()
		await process_frame
	finish()

func check_token_framing() -> void:
	var frame := Board.new()
	root.add_child(frame)
	var pin := Pawn.new()
	frame.world.add_child(pin)
	pin.configure("frame-test",Color.RED)
	frame.framing_width = 15.8
	for dimensions in [Vector2(420,420),Vector2(420,460),Vector2(320,260),Vector2(560,300)]:
		frame.size = dimensions
		await process_frame
		frame._fit_camera()
		var contained := true
		for color in BoardMath.COLORS:
			for index in range(4):
				for position in range(59):
					pin.position = BoardMath.world(color,position,index)+Vector3(0.21,0.24,-0.21)
					pin.visual.position.y = 0.43
					pin.visual.scale = Vector3.ONE*1.12
					for child in pin.visual.get_children():
						if not child is MeshInstance3D:
							continue
						var bounds: AABB = child.mesh.get_aabb()
						for corner in range(8):
							var screen := frame.camera.unproject_position(child.to_global(bounds.get_endpoint(corner)))
							contained = contained and Rect2(Vector2.ZERO,Vector2(frame.viewport.size)).has_point(screen)
		check(contained,"All token mesh corners, stack offsets and bounce fit inside board at %s" % dimensions)
	check(frame.clip_contents,"Board rendering cannot overlap profile cards")
	frame.queue_free()
	await process_frame

func check_mesh_winding(mesh: Mesh, description: String) -> void:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var correct := true
	for index in range(0,vertices.size(),3):
		var winding := (vertices[index+1]-vertices[index]).cross(vertices[index+2]-vertices[index])
		if winding.dot(normals[index]) > 0.00001:
			correct = false
	check(correct,description + " front faces are clockwise and match outward normals")

func finish() -> void:
	if is_instance_valid(host):
		host.network.disconnect_server()
		host.queue_free()
	if is_instance_valid(friend):
		friend.network.disconnect_server()
		friend.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	print("Godot: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
