extends SceneTree

# Offline board regression checks; no room/server mutation is involved.
const Board = preload("res://scripts/board.gd")
const BoardMath = preload("res://scripts/board_math.gd")
const Tokens = preload("res://resources/theme_tokens.tres")
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func home_pin_bounds(board: Control, pawn: Node3D) -> Rect2:
	var bounds := Rect2()
	var started := false
	for child in pawn.visual.get_children()+pawn.base_visual.get_children():
		if child is MeshInstance3D:
			for corner in range(8):
				var point: Vector2 = board.camera.unproject_position(child.to_global(child.mesh.get_aabb().get_endpoint(corner)))
				if not started:
					bounds = Rect2(point,Vector2.ZERO)
					started = true
				else:
					bounds = bounds.expand(point)
	return bounds

func run() -> void:
	var board := Board.new()
	root.add_child(board)
	var cache_draws := [0]
	board.artwork.draw.connect(func(): cache_draws[0] += 1)
	board.size = Vector2(420, 420)
	await process_frame
	check(Tokens is Theme, "Single editable resource is a Godot Theme")
	check(Tokens.red.to_html(false) == "f2131b" and Tokens.green.to_html(false) == "00a64b" and Tokens.blue.to_html(false) == "23ace8" and Tokens.yellow.to_html(false) == "ffeb00", "Vivid player palette remains consistent across the board and pawns")
	check(board.artwork_viewport.size == Vector2i(1024, 1024), "Board texture stays within the mobile texture budget")
	check(board.artwork_viewport.disable_3d and board.artwork_viewport.gui_disable_input, "Art cache cannot render 3D or intercept input")
	check(board.world.get_child_count() < 10, "Static board uses bounded scene complexity")
	for row in range(15):
		for col in range(15):
			var cell: Rect2 = board.artwork._cell_rect(row,col)
			check(cell.size == Vector2(64,64),"Every cell retains the same square dimensions")
			if col < 14:
				check(cell.end.x == board.artwork._cell_rect(row,col+1).position.x,"Adjacent columns share an exact edge")
			if row < 14:
				check(cell.end.y == board.artwork._cell_rect(row+1,col).position.y,"Adjacent rows share an exact edge")
	check(board.board_plane.material_override is StandardMaterial3D and board.board_plane.material_override.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, "Printed colors are independent of 3D lights")
	var state := {"players": [{"id": "local", "color": "coral"}], "currentPlayer": "local", "phase": "moving", "dice": 6, "tokens": []}
	for seat in range(4):
		for index in range(4):
			state.tokens.append({"id": "%s-%d" % [BoardMath.COLORS[seat], index], "color": BoardMath.COLORS[seat], "position": 0})
	board.apply_state(state, "local")
	check(board.pawns.size() == 16, "All existing pawn instances remain supported")
	# Neighboring home pins remain separate even at opposite selection phases.
	for color in BoardMath.COLORS:
		var bounds: Array[Rect2] = []
		for index in range(4):
			var pawn = board.pawns["%s-%d" % [color,index]]
			pawn.set_process(false)
			pawn.visual.position.y = pawn.YARD_BOB if index >= 2 else 0.0
			pawn.visual.scale = Vector3.ONE*(1.0+pawn.YARD_PULSE if index >= 2 else 1.0)
			bounds.append(home_pin_bounds(board,pawn))
		for first in range(4):
			for second in range(first+1,4):
				check(not bounds[first].intersects(bounds[second]),"All four home token bodies and bases have clear spacing")
		for index in range(4):
			var pawn = board.pawns["%s-%d" % [color,index]]
			pawn.set_process(true)
			pawn._process(0)
	for pawn in board.pawns.values():
		pawn.place_shadow()
		check(pawn.cell_shadow.visible and pawn.cell_shadow.material_override is StandardMaterial3D, "Every pawn has a permanent portable shadow")
		check(Color(pawn.cell_shadow.material_override.albedo_color, 1) == pawn.token_color, "Stationary shadow matches its pawn color")
		check(pawn.cell_shadow.material_override.albedo_texture == board.trail_texture, "Permanent and fading shadows reuse the same texture")
		check(pawn.cell_shadow.material_override.render_priority > board.board_plane.material_override.render_priority, "Board cannot cover stationary shadows")
	var shadow_pawn = board.pawns["coral-0"]
	shadow_pawn.set_process(false)
	shadow_pawn.reduced_motion = false
	shadow_pawn._process(0)
	check(shadow_pawn.ring.visible, "Legal pawn displays its feet ring during selection")
	check(shadow_pawn.ring.mesh is TorusMesh and shadow_pawn.ring.material_override.metallic > 0.7, "Selection uses a solid metal hoop instead of a flat glow")
	var ring_angle: float = shadow_pawn.ring.rotation.y
	shadow_pawn._process(0.25)
	check(is_equal_approx(shadow_pawn.ring.rotation.y-ring_angle,0.6), "Feet ring rotates continuously while a pawn is selectable")
	shadow_pawn.reduced_motion = true
	ring_angle = shadow_pawn.ring.rotation.y
	shadow_pawn._process(0.25)
	check(shadow_pawn.ring.visible and shadow_pawn.ring.rotation.y == ring_angle, "Reduced motion keeps the ring visible and stops its rotation")
	shadow_pawn.reduced_motion = false
	shadow_pawn.selection_enabled = false
	shadow_pawn._process(0.25)
	check(not shadow_pawn.ring.visible, "Ring disappears when pawn selection is locked")
	shadow_pawn.selection_enabled = true
	shadow_pawn._process(0)
	shadow_pawn.set_process(true)
	var departure: Vector3 = shadow_pawn.position
	shadow_pawn.hop_to(departure + Vector3.RIGHT, 0.24, false)
	await create_timer(0.10).timeout
	shadow_pawn.place_shadow()
	check(shadow_pawn.moving, "Hop is still underway during the shadow check")
	check(not shadow_pawn.ring.visible and not shadow_pawn.glow_floor.visible, "Ring and aura hide during a pawn hop")
	check(Vector2(shadow_pawn.cell_shadow.global_position.x, shadow_pawn.cell_shadow.global_position.z).is_equal_approx(Vector2(departure.x, departure.z)), "Shadow remains on the departure cell while the pawn hops")
	await create_timer(0.20).timeout
	check(Vector2(shadow_pawn.cell_shadow.global_position.x, shadow_pawn.cell_shadow.global_position.z).is_equal_approx(Vector2(departure.x + 1, departure.z)), "Shadow transfers to the landing cell")
	board.apply_state(state, "local")
	var mesh := board.board_plane.mesh as PlaneMesh
	for seat in range(4):
		var color: String = BoardMath.COLORS[seat]
		for index in range(4):
			var id := "%s-%d" % [color, index]
			var at := BoardMath.world(color, 0, index)
			check(board.pawns[id].position.is_equal_approx(at), "Yard pawn coordinate stays authoritative")
			# Map the artwork pixel center back through the actual plane bounds.
			var ink_point: Vector2 = board.artwork.ORIGIN + Vector2(at.x + 7.5, at.z + 7.5) * board.artwork.CELL
			var plane_point: Vector2 = ink_point / float(board.artwork.RESOLUTION) * mesh.size - mesh.size * 0.5
			check(plane_point.is_equal_approx(Vector2(at.x, at.z)), "Artwork slots line up with existing pawn anchors")
		var entry: Array = BoardMath.TRACK[seat * 13]
		check(board.artwork.cell_color(entry[0], entry[1]) == Tokens.player_colors()[color], "Entry cell retains its player's color")
		var lane := BoardMath.coordinate(color, 54, 0)
		check(board.artwork.cell_color(lane.x, lane.y) == Tokens.player_colors()[color], "Home lane agrees with existing coordinate adapter")
	for dimensions in [Vector2(320, 260), Vector2(420, 420), Vector2(560, 300)]:
		board.size = dimensions
		await process_frame
		board._fit_camera()
		var pawn = board.pawns["coral-0"]
		pawn.reduced_motion = true
		pawn._process(0)
		var point := board.camera.unproject_position(pawn.visual.to_global(Vector3(0, 1.0, 0.22)))
		check(board.token_at_screen(point) == "coral-0", "Legal pawn remains tappable after board replacement")
	for color in BoardMath.COLORS:
		var at := BoardMath.world(color, 1, 0)
		board.leave_trail(at, Tokens.player_colors()[color])
		var mark: MeshInstance3D = board.trails.back()
		var tint: Color = mark.material_override.albedo_color
		check(Color(tint, 1) == Tokens.player_colors()[color], "Step shadow retains the exact pawn color")
		check(is_equal_approx(mark.position.y, 0.224), "Step shadow stays on the board floor")
		check(mark.material_override.albedo_texture == board.trail_texture, "Shadow marks share one small texture")
		check(mark.material_override.render_priority > board.board_plane.material_override.render_priority, "Transparent board cannot cover the step marks")
	for mark in board.trails.duplicate():
		board.clear_trail(mark)
	state.tokens[0].position = 1
	board.apply_state(state, "local")
	for frame in range(3):
		await process_frame
	var draws_before_move: int = cache_draws[0]
	var steps: Array[String] = []
	board.step_landed.connect(func(id: String): steps.append(id))
	await board.animate_move({"tokenId": "coral-0", "from": 1, "to": 4, "durationMs": 720})
	check(cache_draws[0] == draws_before_move,"Multi-frame movement and shadows do not redraw the static artwork")
	check(steps.size() == 3, "Move presentation still lands once per step")
	check(board.trails.size() == 4, "Move leaves marks at departure and every landing")
	for index in range(board.trails.size()):
		var expected := BoardMath.world("coral", index + 1, 0)
		var at := board.trails[index].position
		check(Vector2(at.x, at.z).is_equal_approx(Vector2(expected.x, expected.z)), "Trail follows the step-by-step path")
	check(board.pawns["coral-0"].position.is_equal_approx(BoardMath.world("coral", 4, 0)), "Trail effect leaves the movement destination unchanged")
	for index in range(board.TRAIL_POOL_SIZE + 2):
		board.leave_trail(Vector3(index, 1, index), Tokens.blue)
	check(board.trails.size() == board.TRAIL_POOL_SIZE, "Long trails reuse the bounded effect pool")
	await create_timer(Tokens.step_shadow_hold + Tokens.step_shadow_fade + 0.10).timeout
	check(board.trails.is_empty() and board.trail_fades.is_empty(), "Shadow marks finish fading and return to the pool")
	check(board.pawns["coral-0"].cell_shadow.visible and board.pawns["coral-0"].cell_shadow.material_override.albedo_color.a > 0.6, "Destination shadow remains after old step marks fade")
	check(board.trail_pool.all(func(mark): return is_instance_valid(mark) and not mark.visible), "Pool nodes remain reusable after fading")
	board.reduced_motion = true
	board.leave_trail(Vector3.ZERO, Tokens.red)
	check(board.trails.is_empty(), "Existing reduced-motion setting suppresses shadow trails")
	check(board.pawns["coral-0"].cell_shadow.visible, "Reduced motion keeps the permanent pawn shadow")
	# Eight pins share the same safe star, with four pins in each color group.
	for token in state.tokens:
		token.position = 9 if token.color == "coral" else 35 if token.color == "mint" else 0
	board.apply_state(state, "local")
	var stack_shadows: Dictionary = {}
	for color in ["coral", "mint"]:
		for index in range(4):
			var pawn = board.pawns["%s-%d" % [color, index]]
			pawn.place_shadow()
			check(pawn.cell_shadow.visible, "Each stacked pawn retains its own visible shadow")
			stack_shadows[str(pawn.cell_shadow.global_position)] = true
	check(stack_shadows.size() == 8, "Mixed-color safe-cell stacks expose eight different shadow anchors")
	var finish_cells := [Vector2i(7,6), Vector2i(6,7), Vector2i(7,8), Vector2i(8,7)]
	for seat in range(4):
		var color: String = BoardMath.COLORS[seat]
		state.players = [{"id": "local", "color": color}]
		state.dice = 1
		for token in state.tokens:
			token.position = BoardMath.HOME if token.color == color else 0
		board.apply_state(state, "local")
		var anchors: Dictionary = {}
		for index in range(4):
			var pawn = board.pawns["%s-%d" % [color, index]]
			pawn._process(0)
			check(pawn.completed and pawn.finish_badge.visible, "Finished pawn has a visible completion check")
			check(pawn.finish_badge.get_parent() == board.viewport, "Completion check uses an overlay above the 3D board")
			check(not pawn.legal_move and not pawn.highlight and not pawn.ring.visible and not pawn.glow_floor.visible, "Finished pawn cannot reactivate on a roll of one")
			check(pawn.position.is_equal_approx(BoardMath.world(color, BoardMath.HOME, index)), "Finished pawn stays in its center triangle")
			anchors[str(pawn.position)] = true
			var point: Vector2 = board.camera.unproject_position(pawn.visual.to_global(Vector3(0, 1.0, 0.22)))
			check(board.token_at_screen(point).is_empty(), "Finished pawn cannot be selected by tapping")
		check(anchors.size() == 4, "Four finished pawns have separate visible anchors")
		check(BoardMath.coordinate(color, BoardMath.HOME, 0) == finish_cells[seat], "Finish cell is the appropriate colored triangle")
		check(BoardMath.coordinate(color, 58, 0) == finish_cells[seat], "Legacy completed positions still display inside their triangle")
		for dice in range(1, 7):
			check(not BoardMath.legal({"position": BoardMath.HOME}, dice), "Finish triangle stays terminal for every die")
	# Final landing displays completion before the following server snapshot.
	state.players = [{"id": "local", "color": "mint"}]
	for token in state.tokens:
		token.position = BoardMath.HOME - 1 if token.id == "mint-0" else 0
	board.apply_state(state, "local")
	steps.clear()
	await board.animate_move({"tokenId": "mint-0", "from": BoardMath.HOME - 1, "to": BoardMath.HOME, "durationMs": 240})
	check(steps == ["mint-0"], "Finish requires exactly one last hop")
	check(board.pawns["mint-0"].completed and board.pawns["mint-0"].finish_badge.visible, "Completion is shown as soon as the pawn lands")
	var finished_pawn = board.pawns["mint-0"]
	var badge_position: Vector2 = board.camera.unproject_position(finished_pawn.visual.to_global(Vector3(0, 1.46, 0.54))) - finished_pawn.finish_badge.size * 0.5
	check(finished_pawn.finish_badge.position.is_equal_approx(badge_position), "Completion check is correctly placed before the next frame or snapshot")
	state.tokens[8].position = BoardMath.HOME
	board.apply_state(state, "local")
	check(board.pawns["mint-0"].position.is_equal_approx(BoardMath.world("mint", BoardMath.HOME, 0)), "Authoritative finish snapshot keeps the pawn in place")
	for token in state.tokens:
		token.position = 0
	board.apply_state(state, "local")
	check(board.pawns.values().all(func(pawn): return not pawn.completed and not pawn.finish_badge.visible), "Restart clears all pawn completion markers")
	check(board.artwork_viewport.render_target_update_mode != SubViewport.UPDATE_ALWAYS,"Art cache never switches to continuous rendering")
	board.queue_free()
	await process_frame
	print("Board visuals: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
