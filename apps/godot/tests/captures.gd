extends SceneTree

const MainScene = preload("res://scenes/main.tscn")
const Board = preload("res://scripts/board.gd")
const BoardMath = preload("res://scripts/board_math.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	ProjectSettings.set_setting("rally/realtime_url","ws://127.0.0.1:1")
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func fixture() -> Dictionary:
	var tokens: Array = []
	for player in [{"id":"a","color":"coral"},{"id":"b","color":"mint"}]:
		for index in range(4):
			tokens.append({"id":"%s-%d" % [player.id,index],"color":player.color,"position":16 if player.id == "a" and index == 0 else 43 if player.id == "b" and index == 2 else 0})
	return {"version":1,"players":[{"id":"a","name":"Capturer","color":"coral"},{"id":"b","name":"Captured","color":"mint"}],"tokens":tokens,"phase":"moving","dice":1,"currentPlayer":"a","finishOrder":[]}

func run() -> void:
	var actor = MainScene.instantiate()
	var observer = MainScene.instantiate()
	var clients: Array = [actor,observer]
	for client in clients:
		root.add_child(client)
		client.network.disconnect_server()
		client.network.set_process(false)
		client.online = true
		client.reduced_motion = false
		client.board.reduced_motion = false
		client.feedback.sound_enabled = false
		client.feedback.haptics_enabled = false
	actor.self_id = "a"
	observer.self_id = "b"
	var paths: Array = [[],[]]
	var capture_sounds: Array[int] = [0,0]
	var reverse_step_sounds: Array[String] = []
	for slot in range(2):
		var client = clients[slot]
		client._receive({"type":"STATE","state":fixture(),"roomCode":"CAPTURE"})
		client.board.token_captured.connect(func(_mover: String, _victim: String): capture_sounds[slot] += 1)
		client.board.step_landed.connect(func(id: String):
			if id == "b-2": reverse_step_sounds.append(id)
		)
		client.board.capture_passed.connect(func(id: String):
			if id == "b-2":
				paths[slot].append(client.board.pawns[id].position)
				check(client.presenting and not client.board.enabled,"Both clients lock gameplay throughout the reverse journey")
				check(not client.board.pawns[id].ring.visible,"Captured pawn cannot display a selectable ring")
		)
	var after := fixture()
	after.version = 3
	after.tokens[0].position = 17
	after.tokens[6].position = 0
	after.phase = "rolling"
	after.dice = null
	var now := int(Time.get_unix_time_from_system()*1000)
	var snapshot := {"type":"STATE","roomCode":"CAPTURE","state":after,"serverTime":now,"turnDeadline":now+30000+240+42*Board.CAPTURE_STEP_MS+Board.CAPTURE_HOME_MS,"turnDurationMs":30000}
	# Actor missed the move event, observer received it normally. Both must
	# visit the identical reverse path instead of jumping to the yard.
	var recovery := snapshot.duplicate(true)
	recovery.recovered = true
	actor._receive(recovery)
	observer._receive({"type":"TOKEN_MOVED","tokenId":"a-0","from":16,"to":17,"captured":["b-2"],"durationMs":240,"version":3})
	observer._receive(snapshot)
	var deadline := Time.get_ticks_msec()+12000
	while clients.any(func(client): return client.processing_events) and Time.get_ticks_msec() < deadline:
		await process_frame
		for client in clients:
			var pawn = client.board.pawns["b-2"]
			if pawn.sliding:
				check(is_equal_approx(pawn.position.y,0.22) and pawn.visual.position == Vector3.ZERO and pawn.visual.scale == Vector3.ONE,"Reverse glide stays flat with no bounce or squash between cells")
	check(clients.all(func(client): return not client.processing_events),"Capture queues finish on both screens")
	check(capture_sounds == [1,1] and reverse_step_sounds.is_empty(),"Normal and recovered captures play one cut cue and no reverse footstep cues")
	var expected: Array = []
	for position in range(42,-1,-1):
		expected.append(BoardMath.world("mint",position,2))
	check(paths[0] == expected and paths[1] == expected,"Normal and recovered captures retrace all 42 track cells, then the original yard slot")
	for client in clients:
		check(client.board.display_positions["b-2"] == 0,"Capture reaches the authoritative base position")
		check(client.game == after and not client.presenting,"Capture finishes before applying the next-turn snapshot")
		check(client.turn_deadline_ticks-Time.get_ticks_msec() >= 28500,"Reverse glide does not consume the next player's clock")
	actor._receive(recovery)
	observer._receive({"type":"TOKEN_MOVED","tokenId":"a-0","from":16,"to":17,"captured":["b-2"],"durationMs":240,"version":3})
	await process_frame
	check(paths[0].size() == 43 and paths[1].size() == 43,"Duplicate snapshots and old events cannot replay a capture")
	actor.reduced_motion = true
	actor.turn_deadline_ticks = Time.get_ticks_msec()+actor.turn_duration_ms+180
	actor.refresh_controls()
	check(not actor.board.enabled and actor.cards[0].roll.disabled,"Reduced motion cannot roll during the server's reverse-glide lead-in")
	await create_timer(0.25).timeout
	check(actor.board.enabled and not actor.cards[0].roll.disabled,"Next roll unlocks when the server animation period ends")
	for client in clients:
		client.queue_free()
	await process_frame
	# Every color has a different starting offset. Exercise the complete route
	# at accelerated test time, while preserving the actual continuous glide tween.
	Engine.time_scale = 6.0
	var board := Board.new()
	root.add_child(board)
	var positions: Array = []
	board.capture_passed.connect(func(id: String): positions.append(board.pawns[id].position))
	for color in BoardMath.COLORS:
		var state := {"players":[],"tokens":[{"id":"pin-3","color":color,"position":51}],"phase":"rolling","dice":null}
		board.apply_state(state,"")
		positions.clear()
		await board.animate_capture("pin-3")
		expected.clear()
		for position in range(50,-1,-1):
			expected.append(BoardMath.world(color,position,3))
		check(positions == expected,"Every color follows its own reverse route through every corner")
		await board.animate_capture("pin-3")
		check(positions.size() == 51,"Already returned pawn has no additional reverse animation")
		state.tokens[0].position = 51
		board.apply_state(state,"")
		board.reduced_motion = true
		positions.clear()
		await board.animate_capture("pin-3")
		check(positions == [BoardMath.world(color,0,3)],"Reduced motion returns directly without a burst of 51 simultaneous sounds")
		board.reduced_motion = false
	Engine.time_scale = 1.0
	board.queue_free()
	await process_frame
	print("Captured pawn reverse paths: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
