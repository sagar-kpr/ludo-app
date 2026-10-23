extends SceneTree

const MainScene = preload("res://scenes/main.tscn")
var client
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func wait_until(condition: Callable, seconds: float = 12.0) -> bool:
	var deadline := Time.get_ticks_msec()+int(seconds*1000)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await create_timer(0.02).timeout
	return bool(condition.call())

func run() -> void:
	client = MainScene.instantiate()
	root.add_child(client)
	client.reduced_motion = true
	client.feedback.sound_enabled = false
	check(await wait_until(func(): return client.online),"Connect to the server")
	if not client.online:
		finish()
		return
	client.request_room(false,true)
	check(await wait_until(func(): return client.game.get("phase") == "rolling" and not client.pending and not client.loading_overlay.visible),"Start a real A.I match")
	var original_id: String = client.self_id
	var original_room: String = client.room_code
	var net = client.network
	var original_socket = net.socket
	net.set_process(false)
	net.send_intent({"type":"PING"})
	await create_timer(0.12).timeout
	# Model a stalled render loop while the server reply waits in the socket.
	net.last_reply_ms = Time.get_ticks_msec()-13000
	net._process(0.02)
	check(net.socket == original_socket,"Queued replies are drained before a stale clock can replace a healthy socket")
	check(client.room_code == original_room and client.game_view.visible,"A stalled frame does not return an active A.I match to the dashboard")
	check(client.game.timeoutLives[original_id] == 5,"Recovery does not consume a player's inactivity dots")
	# No queued reply: probe a quiet connection before tearing it down.
	net.awaiting_probe = false
	net.last_reply_ms = Time.get_ticks_msec()-13000
	net._process(0.02)
	check(net.socket == original_socket and net.awaiting_probe,"A quiet socket is probed before reconnecting")
	await create_timer(0.12).timeout
	net._process(0.02)
	check(not net.awaiting_probe and net.socket == original_socket,"A successful probe preserves the same socket and match")
	# Repeated focus/online notifications must not replace an in-flight connection.
	net.connect_server(net.endpoint)
	var connecting_socket = net.socket
	net.probe_connection()
	net.probe_connection()
	check(net.socket == connecting_socket,"Focus notifications do not restart an in-flight reconnect")
	net.set_process(true)
	check(await wait_until(func(): return client.online and client.self_id == original_id and not net.awaiting_probe),"Reconnect resumes the original player")
	check(client.room_code == original_room and client.game_view.visible and not client.recovery_lost_dialog.visible,"A reconnect preserves the A.I table and does not show a false lost-match message")
	check(not client.server_instance_id.is_empty(),"Handshake identifies the running server instance")
	# A genuinely lost session must explain the loss instead of silently navigating.
	net.session_token = "missing-session-for-recovery-test"
	net.connect_server(net.endpoint)
	check(await wait_until(func(): return client.recovery_lost_dialog.visible),"A server-confirmed missing session shows a clear recovery failure")
	check(client.room_code.is_empty() and client.home.visible and client.board.pawns.is_empty(),"An unrecoverable match clears the old board and returns safely home")
	client.recovery_lost_dialog.hide()
	client.request_room(false)
	check(await wait_until(func(): return client.game.get("phase") == "lobby" and not client.pending),"A new friend room works after a lost session")
	client.send({"type":"LEAVE_GAME"})
	check(await wait_until(func(): return client.room_code.is_empty() and not net.has_room),"Leaving clears the networking room flag")
	net.probe_connection()
	check(await wait_until(func(): return not net.awaiting_probe and client.online),"Dashboard focus can recover without waiting for a nonexistent room snapshot")
	finish()

func finish() -> void:
	if is_instance_valid(client):
		client.network.disconnect_server()
		client.queue_free()
	await process_frame
	print("Connection recovery: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
