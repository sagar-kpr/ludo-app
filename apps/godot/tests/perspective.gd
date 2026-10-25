extends SceneTree

const MainScene = preload("res://scenes/main.tscn")
const BoardMath = preload("res://scripts/board_math.gd")
const Perspective = preload("res://scripts/board_perspective.gd")
var checks := 0
var failures := 0
var scenarios := 0

func _initialize() -> void:
	ProjectSettings.set_setting("rally/realtime_url","ws://127.0.0.1:1")
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		if failures <= 12:
			push_error(message)

func fixture(count: int) -> Dictionary:
	var state := {"version":1,"phase":"moving","players":[],"tokens":[],"currentPlayer":"0","dice":1,"finishOrder":[]}
	for index in range(count):
		var color: String = ["coral","mint","sun","violet"][index]
		state.players.append({"id":str(index),"name":"Player "+str(index),"color":color,"ready":true})
		for pin in range(4):
			state.tokens.append({"id":"%d-%d" % [index,pin],"color":color,"position":0})
	return state

func apply(client, state: Dictionary) -> void:
	client.game = state
	client.show_state()
	client.refresh_controls()

func run() -> void:
	var client = MainScene.instantiate()
	root.add_child(client)
	client.network.disconnect_server()
	client.network.set_process(false)
	client.online = true
	client.pending = false
	client.reduced_motion = true
	client.board.reduced_motion = true
	root.size = Vector2i(420,860)
	check(client.color_choices.size() == 4 and client.color_choices[0].color_key == "coral","First pawn is the default Red option")
	for choice in client.color_choices:
		check(choice.text.is_empty() and choice.preview != null,"Color selection uses real pawn previews without letter boxes")
		check(choice.preview == client.color_choices[0].preview,"All four choices share one cached pawn atlas")
		check(choice.preview.render_target_update_mode != SubViewport.UPDATE_ALWAYS,"Pawn preview textures remain cached")
	for count in [2,3,4]:
		for local in range(count):
			for preference in BoardMath.COLORS:
				scenarios += 1
				var state := fixture(count)
				state.currentPlayer = str(local)
				state.tokens[local*4].position = 1
				var original := state.duplicate(true)
				client.self_id = str(local)
				client.preferred_color = preference
				apply(client,state)
				for frame in range(3):
					await process_frame
				var view = client.perspective
				var own_color: String = state.players[local].color
				check(view.visual_seat(own_color) == 3,"Local home maps to bottom-left")
				check(view.display_key(own_color) == preference,"Local home uses chosen color")
				check(client.card_at_corner(3).player_id == str(local),"Local card is bottom-left")
				check(client.card_at_corner(3).get_parent() == client.player_rows[1],"Local card uses the lower row on mobile")
				check(client.card_at_corner(3).lives.accent == client.Design.COLORS[preference],"Own card and life dots use selected color")
				var home: Vector3 = client.board.world_position(own_color,0,0)
				check(home.x < 0 and home.z > 0,"Base geometry is actually transformed to bottom-left")
				var corners := {}
				var hues := {}
				for color in BoardMath.COLORS:
					corners[view.visual_seat(color)] = true
					hues[view.display_key(color)] = true
					check(view.logical_seat(view.visual_seat(color)) == BoardMath.COLORS.find(color),"Corner mapping is invertible")
					for position in range(1,57):
						var logical: Vector3 = BoardMath.world(color,position,0)
						var actual: Vector3 = client.board.world_position(color,position,0)
						var printed: Vector3 = client.board.board_plane.to_global(Vector3(logical.x,0,logical.z))
						check(Vector2(actual.x,actual.z).is_equal_approx(Vector2(printed.x,printed.z)),"Every track and home-lane position matches the rotated board plane")
						var cell: Vector2i = view.cell(BoardMath.coordinate(color,position,0))
						check(Vector2(actual.x,actual.z).is_equal_approx(Vector2(cell.y-7,cell.x-7)),"Coordinate and world adapters agree")
					check(client.board.artwork.colors[color] == view.display_color(color),"Procedural yards, tracks, arrows and docks share the display palette")
				check(corners.size() == 4 and hues.size() == 4,"All four corners and display colors stay unique")
				check(client.board.artwork_viewport.render_target_update_mode != SubViewport.UPDATE_ALWAYS,"Board artwork remains cached")
				var own = client.board.pawns[str(local)+"-0"]
				check(own.token_color == client.Design.COLORS[preference],"Pawn enamel matches selected color")
				var point: Vector2 = client.board.display_point(client.board.camera.unproject_position(own.visual.to_global(Vector3(0,0.75,0.22))))
				check(client.board.token_at_screen(point) == str(local)+"-0","Touch selection returns the original logical token ID")
				check(state == original,"Rendering never mutates authoritative state")
				var victim: int = (local+1)%count
				var victim_color: String = state.players[victim].color
				# Two different logical paths meet at the same physical capture cell.
				state.tokens[local*4].position = 2
				state.tokens[victim*4].position = posmod(int(BoardMath.OFFSETS[own_color])+4-int(BoardMath.OFFSETS[victim_color]),52)+1
				state.dice = 3
				apply(client,state)
				check(client.board.world_position(own_color,5,0).is_equal_approx(client.board.world_position(victim_color,int(state.tokens[victim*4].position),0)),"Capture destination coincides across player paths")
				await client.board.animate_move({"tokenId":str(local)+"-0","from":2,"to":5,"captured":[str(victim)+"-0"],"durationMs":0})
				check(client.board.pawns[str(victim)+"-0"].position.is_equal_approx(client.board.world_position(victim_color,0,0)),"Captured pawn returns along its transformed path to its own base")
				# Safe-cell stacking remains a logical-rule decision, with visible groups.
				state.tokens[local*4].position = 1
				state.tokens[victim*4].position = posmod(int(BoardMath.OFFSETS[own_color])-int(BoardMath.OFFSETS[victim_color]),52)+1
				state.dice = 1
				apply(client,state)
				check(client.board.stack_labels.size() == 2,"Mixed-color star stack is preserved by every perspective")
				# Entering home and winning keep the same token IDs and placements.
				state.tokens[victim*4].position = 0
				state.tokens[local*4].position = 56
				apply(client,state)
				await client.board.animate_move({"tokenId":str(local)+"-0","from":56,"to":57,"durationMs":0})
				check(own.completed and own.position.is_equal_approx(client.board.world_position(own_color,57,0)),"Final hop reaches the correct transformed home triangle")
				state.phase = "finished"
				state.finishOrder = [str(local)]
				for index in range(count):
					if index != local:
						state.finishOrder.append(str(index))
				state.winner = str(local)
				for token in state.tokens:
					if token.color == own_color:
						token.position = 57
				apply(client,state)
				check(client.result.visible and client.result_list.get_child_count() == count,"Winner popup preserves authoritative rankings")
				check(client.cards[BoardMath.COLORS.find(own_color)].celebration.rank == 0,"Own winner celebration remains attached to own logical identity")
				client.result.hide()
	# Two clients may independently prefer red while preserving shared collision cells.
	var players: Array = fixture(4).players
	var first = Perspective.for_player(players,"0","coral")
	var second = Perspective.for_player(players,"1","coral")
	check(first.display_key(players[0].color) == "coral" and second.display_key(players[1].color) == "coral","Both clients can select Red independently")
	check(first.world(BoardMath.world("coral",5,0)).is_equal_approx(first.world(BoardMath.world("mint",31,0))) and second.world(BoardMath.world("coral",5,0)).is_equal_approx(second.world(BoardMath.world("mint",31,0))),"Shared capture cells remain identical within both independent views")
	var remaining: Array = players.slice(1)
	var leaving_view = Perspective.for_player(remaining + [players[0]],"0","coral")
	check(leaving_view.signature() == first.signature(),"Departure keeps the same perspective until the local player reaches the dashboard")
	client.queue_free()
	await process_frame
	print("Perspective: %d scenarios, %d checks, %d failures" % [scenarios,checks,failures])
	quit(0 if failures == 0 else 1)
