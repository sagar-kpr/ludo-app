extends SceneTree

const MainScene = preload("res://scenes/main.tscn")
var checks := 0
var failures := 0
var client
var computer_rolls: Array[int] = []
var computer_moves := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func wait_until(condition: Callable, seconds: float = 20.0) -> bool:
	var deadline := Time.get_ticks_msec()+int(seconds*1000)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await create_timer(0.02).timeout
	return bool(condition.call())

func run() -> void:
	client = MainScene.instantiate()
	root.add_child(client)
	client.reduced_motion = true
	client.board.reduced_motion = true
	client.feedback.sound_enabled = false
	check(await wait_until(func(): return client.online),"Client connects for a server-controlled computer match")
	if not client.online:
		finish()
		return
	check(not client.computer_button.disabled,"Play vs Computer is available when connected")
	client.name_input.text = "Solo player"
	client.computer_button.pressed.emit()
	check(await wait_until(func(): return client.game.get("phase") == "rolling" and not client.pending),"Computer button starts directly without waiting in a lobby")
	var players: Array = client.game.get("players",[])
	check(players.size() == 2,"Match has one human and one computer")
	if players.size() != 2:
		finish()
		return
	var opponent: Dictionary = players[1]
	check(opponent.get("isComputer",false) and opponent.color == "mint","Computer occupies the opposite corner")
	check(client.cards[2].player_id == opponent.id and client.cards[2].name_label.text == "Computer","Existing profile card identifies the computer")
	check(not client.cards[2].gift.visible and not client.cards[2].camera_button.visible and not client.cards[0].chat.visible,"Computer match hides unused social controls")
	check(client.cards[0].camera_button.visible and client.cards[0].leave_button.visible,"Settings and leaving stay available")
	check(client.board.pawns.size() == 8,"The existing board renders both players' four pawns")
	client.network.event_received.connect(func(event: Dictionary):
		if event.get("type") == "DICE_ROLLED" and event.get("playerId") == opponent.id:
			computer_rolls.append(int(event.value))
		if event.get("type") == "TOKEN_MOVED" and str(event.get("tokenId","")).begins_with(str(opponent.id)+"-"):
			computer_moves += 1
	)
	client.cards[0].roll.pressed.emit()
	check(await wait_until(func(): return computer_moves == 3 and client.game.get("currentPlayer") == client.self_id and not client.processing_events),"Computer rolls and moves through the normal presentation queue")
	check(computer_rolls == [6,6,5],"Computer follows the same two-consecutive-sixes limit")
	check(client.game.get("timeoutLives",{}).get(opponent.id) == 5,"Computer actions never spend inactivity dots")
	check(client.game.get("timeoutLives",{}).get(client.self_id) == 5,"Manual human play preserves its inactivity dots")
	check(client.game.tokens.any(func(token: Dictionary): return token.color == "mint" and int(token.position) > 0),"Computer's moved pawn matches the authoritative state")
	check(await wait_until(func(): return client.board.enabled and not client.presenting),"Human input unlocks after the final computer animation")
	client.cards[0].leave_button.pressed.emit()
	check(client.leave_dialog.visible,"Existing leave confirmation works in computer mode")
	client.leave_dialog.hide()
	client.leave_dialog.confirmed.emit()
	check(await wait_until(func(): return client.room_code.is_empty() and client.home.visible),"Leaving returns to the existing home screen")
	client.request_room(false)
	check(await wait_until(func(): return client.game.get("phase") == "lobby" and not client.pending),"The same client can still create a normal friend room")
	check(client.game.players.size() == 1 and not client.game.players[0].get("isComputer",false),"Friend-room creation adds no computer")
	client.send({"type":"LEAVE_GAME"})
	await wait_until(func(): return client.room_code.is_empty())
	finish()

func finish() -> void:
	if is_instance_valid(client):
		client.network.disconnect_server()
		client.queue_free()
	await process_frame
	print("Computer match: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
