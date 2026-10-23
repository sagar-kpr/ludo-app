extends SceneTree

const MainScene = preload("res://scenes/main.tscn")
var checks := 0
var failures := 0

func _initialize() -> void:
	ProjectSettings.set_setting("rally/realtime_url", "ws://127.0.0.1:1")
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func wait_idle(clients: Array) -> void:
	var deadline := Time.get_ticks_msec() + 10000
	while clients.any(func(client): return client.processing_events) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(clients.all(func(client): return not client.processing_events), "Both clients finish their presentation queues")

func fixture(version: int, position: int) -> Dictionary:
	var tokens: Array = []
	for player in [{"id": "a", "color": "coral"}, {"id": "b", "color": "mint"}]:
		for index in range(4):
			tokens.append({"id": "%s-%d" % [player.id, index], "color": player.color, "position": position if player.id == "a" and index == 0 else 0})
	return {"version": version, "players": [{"id": "a", "name": "Actor", "color": "coral", "ready": true}, {"id": "b", "name": "Observer", "color": "mint", "ready": true}], "tokens": tokens, "currentPlayer": "a", "phase": "rolling", "dice": null, "finishOrder": []}

func state_event(snapshot: Dictionary, recovered: bool = false) -> Dictionary:
	return {"type": "STATE", "state": snapshot.duplicate(true), "roomCode": "TEST-ROOM", "recovered": recovered}

func run() -> void:
	var actor = MainScene.instantiate()
	var observer = MainScene.instantiate()
	var clients: Array = [actor, observer]
	for client in clients:
		root.add_child(client)
		client.network.disconnect_server()
		client.network.set_process(false)
		client.online = true
		client.reduced_motion = false
		client.board.reduced_motion = false
		client.feedback.sound_enabled = true
		client.feedback.haptics_enabled = false
		client.board.step_landed.connect(func(_id: String):
			var sound = client.feedback
			var voice = sound.voices[(sound.next_voice+sound.voices.size()-1)%sound.voices.size()]
			check(sound.last_cue == "step" and voice.stream == sound.samples["step"] and voice.playing and voice.get_playback_position() < 0.06, "Every landing starts a fresh hop sound on actor and observer")
			check(voice.volume_db >= -14.0 and voice.volume_db <= -9.0, "Movement tap retains the existing boosted volume")
		)
	actor.self_id = "a"
	observer.self_id = "b"
	var preview = actor.cards[0].dice
	preview.reduced_motion = false
	preview.show_face(2)
	preview.begin_roll_preview()
	check(preview.rolling and preview.preview_pending and preview.settled_value == 2,"Roll tap starts a preview without guessing the result")
	preview.preview_tween.custom_step(0.08)
	check(not preview.die.rotation.is_equal_approx(preview.FACE_ROTATIONS[2]),"Dice spins while waiting for the server")
	await preview.animate_roll(6)
	check(not preview.rolling and not preview.preview_pending and preview.settled_value == 6,"Confirmed result replaces the preview and settles on the server face")
	preview.begin_roll_preview()
	preview.cancel_roll_preview()
	check(not preview.rolling and preview.settled_value == 6 and preview.die.rotation.is_equal_approx(preview.FACE_ROTATIONS[6]),"Failed roll restores the previous face and stops the preview")
	var actor_steps: Array[Vector3] = []
	var observer_steps: Array[Vector3] = []
	actor.board.step_landed.connect(func(id: String): actor_steps.append(actor.board.pawns[id].position))
	observer.board.step_landed.connect(func(id: String): observer_steps.append(observer.board.pawns[id].position))
	for client in clients:
		client._receive(state_event(fixture(1, 1)))
		client._receive({"type": "DICE_ROLLED", "playerId": "a", "color": "coral", "value": 3, "version": 2})
		client._receive({"type": "TOKEN_MOVED", "tokenId": "a-0", "from": 1, "to": 4, "durationMs": 720, "captured": [], "version": 3})
		client._receive(state_event(fixture(3, 4)))
	# Exact regression: the active user's focus probe returns while dice rolls.
	actor._receive(state_event(fixture(3, 4), true))
	check(actor.presenting, "Focus resync cannot unlock input during the dice animation")
	check(actor.events.any(func(event): return event.type == "TOKEN_MOVED"), "Focus resync preserves the pending move")
	await wait_idle(clients)
	check(actor_steps.size() == 3 and observer_steps.size() == 3, "Actor and observer both show all three landing steps")
	check(actor_steps == observer_steps, "Both screens visit the same per-cell positions")
	check(actor.game == observer.game and actor.game.version == 3, "Presentation fix preserves authoritative state")
	check(not actor.presenting and not actor.awaiting_move_state, "Resync releases the presentation lock after applying state")
	# Genuine missing move: actor gets only a recovery snapshot; observer gets
	# the normal move broadcast. Their visible paths must still match.
	for client in clients:
		client._receive(state_event(fixture(10, 1)))
	actor_steps.clear()
	observer_steps.clear()
	actor._receive(state_event(fixture(11, 6), true))
	observer._receive({"type": "TOKEN_MOVED", "tokenId": "a-0", "from": 1, "to": 6, "durationMs": 1200, "captured": [], "version": 11})
	observer._receive(state_event(fixture(11, 6)))
	await wait_idle(clients)
	check(actor_steps.size() == 5 and actor_steps == observer_steps, "Missing move event recovers five hops instead of teleporting")
	check(actor.board.display_positions["a-0"] == 6, "Visible movement progress is tracked independently of snapshots")
	actor._receive(state_event(fixture(11, 6), true))
	actor._receive({"type": "TOKEN_MOVED", "tokenId": "a-0", "from": 1, "to": 6, "durationMs": 1200, "captured": [], "version": 11})
	await wait_idle([actor])
	check(actor_steps.size() == 5, "Repeated recovery or old move events cannot replay completed hops")
	# A recovery containing both base entry and later movement visits each cell.
	actor._receive(state_event(fixture(20, 0)))
	actor_steps.clear()
	actor._receive(state_event(fixture(21, 3), true))
	await wait_idle([actor])
	check(actor_steps.size() == 3, "Recovery from base includes entry followed by intermediate hops")
	actor._receive(state_event(fixture(22, 0), true))
	check(not actor.processing_events and actor.game.version == 22, "Empty-board restart applies without replaying pawn captures")
	# Finish the third pawn automatically. Both screens must retain the owner's
	# bonus turn and expose the next roll only after the final landing/snapshot.
	var before_finish := fixture(30, actor.BoardMath.HOME-2)
	before_finish.phase = "moving"
	before_finish.dice = 2
	before_finish.tokens[1].position = actor.BoardMath.HOME
	before_finish.tokens[2].position = actor.BoardMath.HOME
	var after_finish := before_finish.duplicate(true)
	after_finish.version = 32
	after_finish.tokens[0].position = actor.BoardMath.HOME
	after_finish.phase = "rolling"
	after_finish.dice = null
	actor_steps.clear()
	observer_steps.clear()
	for client in clients:
		client._receive(state_event(before_finish))
		client._receive({"type": "DICE_ROLLED", "playerId": "a", "color": "coral", "value": 2, "automatic": true, "version": 31})
		client._receive({"type": "TOKEN_MOVED", "tokenId": "a-0", "from": actor.BoardMath.HOME-2, "to": actor.BoardMath.HOME, "automatic": true, "durationMs": 480, "captured": [], "version": 32})
		client._receive(state_event(after_finish))
	actor._receive(state_event(after_finish, true))
	await wait_idle(clients)
	check(actor_steps.size() == 2 and actor_steps == observer_steps, "Automatic exact finish visits both steps on both screens")
	for client in clients:
		check(client.game.currentPlayer == "a" and client.game.phase == "rolling", "Finishing the third pawn keeps the bonus turn on both clients")
		check(client.board.pawns["a-0"].completed and not client.board.pawns["a-3"].completed, "Only the landed pawn becomes complete")
		check(client.cards[0].roll.visible, "Owner card shows its bonus roll after landing")
	check(not actor.cards[0].roll.disabled and observer.cards[0].roll.disabled, "Only the owner can use the bonus roll")
	# Timeout events use the regular queue and fresh phase deadlines. Neither
	# client submits roll/move input during this scenario.
	var waiting_roll := fixture(40, 0)
	for client in clients:
		client._receive(state_event(waiting_roll))
	actor_steps.clear()
	observer_steps.clear()
	var waiting_move := fixture(41, 0)
	waiting_move.phase = "moving"
	waiting_move.dice = 6
	var now := int(Time.get_unix_time_from_system()*1000)
	for client in clients:
		client._receive({"type": "DICE_ROLLED", "playerId": "a", "color": "coral", "value": 6, "timedOut": true, "version": 41})
		var timed_state := state_event(waiting_move)
		timed_state.merge({"serverTime": now, "turnDeadline": now+31200, "turnDurationMs": 30000})
		client._receive(timed_state)
	await wait_idle(clients)
	for client in clients:
		check(client.game.currentPlayer == "a" and client.game.phase == "moving", "Automatic roll retains the player's pawn-selection phase")
		check(client.turn_duration_ms == 30000 and client.cards[0].turn_duration_ms == 30000, "Both screens use the 30-second move clock")
		check(client.cards[0].status_label.text == "0:30", "Move choice gets a fresh 30 seconds after dice animation")
	var after_timeout := fixture(42, 1)
	now = int(Time.get_unix_time_from_system()*1000)
	for client in clients:
		client._receive({"type": "TOKEN_MOVED", "tokenId": "a-0", "from": 0, "to": 1, "automatic": true, "timedOut": true, "durationMs": 240, "captured": [], "version": 42})
		var timed_state := state_event(after_timeout)
		timed_state.merge({"serverTime": now, "turnDeadline": now+30240, "turnDurationMs": 30000})
		client._receive(timed_state)
	await wait_idle(clients)
	check(actor_steps.size() == 1 and actor_steps == observer_steps, "Timeout move animates the same legal pawn on both screens")
	for client in clients:
		check(client.game.phase == "rolling" and client.game.currentPlayer == "a", "Timeout move preserves the six bonus turn")
		check(client.cards[0].status_label.text == "0:30", "Next roll gets a fresh 30-second clock after landing")
	var blocked := fixture(50,2)
	blocked.tokens[1].position = 3
	blocked.tokens[2].position = 6
	blocked.tokens[3].position = 8
	var passed := blocked.duplicate(true)
	passed.version = 51
	passed.currentPlayer = "b"
	for client in clients:
		client._receive(state_event(blocked))
		client.pending = true
		var voice_before: int = client.feedback.next_voice
		client._receive({"type":"TURN_SKIPPED","playerId":"a","reason":"friendly_occupancy","version":51})
		client._receive(state_event(passed))
		check(not client.pending and not client.presenting and client.game.currentPlayer == "b","An entirely blocked roll passes cleanly on both clients")
		check(client.notice.text.contains("Turn passed") and not client.cards[0].dice.rolling and client.feedback.next_voice == voice_before,"Blocked rolls explain the pass without animating or sounding an invalid die")
	for client in clients:
		check(client.feedback.samples["step"].get_length() > 0.10 and client.feedback.samples["step"].get_length() < 0.24, "Hop sound ends before the next cell landing")
		client.feedback.sound_enabled = false
		var next_voice: int = client.feedback.next_voice
		client.feedback.cue("step")
		check(client.feedback.next_voice == next_voice, "Muting sound also silences pawn hops")
		client.queue_free()
	await process_frame
	print("Presentation: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
