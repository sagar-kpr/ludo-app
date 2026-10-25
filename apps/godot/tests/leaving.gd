extends SceneTree

const MainScene = preload("res://scenes/main.tscn")
var failures := 0
var checks := 0
var clients: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func wait_until(condition: Callable, seconds: float = 10.0) -> bool:
	var deadline := Time.get_ticks_msec()+int(seconds*1000)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await create_timer(0.02).timeout
	return bool(condition.call())

func run() -> void:
	for index in range(3):
		var client = MainScene.instantiate()
		root.add_child(client)
		clients.append(client)
		client.visible = index == 2
		client.name_input.text = ["Leaving Host","Friend","Last Player"][index]
	var host = clients[0]
	var friend = clients[1]
	var third = clients[2]
	check(await wait_until(func(): return clients.all(func(client): return client.online)),"Three clients connect")
	host.name_input.text = "Leaving Host"
	host.request_room(false)
	check(await wait_until(func(): return not host.room_code.is_empty() and not host.pending),"Room created")
	for client in [friend,third]:
		client.join_input.text = host.room_code
		client.request_room(true)
		check(await wait_until(func(): return client.game.get("players",[]).size() == clients.find(client)+1),"Player joins")
	host.send({"type":"START_GAME"})
	check(await wait_until(func(): return clients.all(func(client): return client.game.get("phase") == "rolling")),"Match starts")
	check(host.cards[0].leave_button.visible and not friend.cards[0].leave_button.visible,"Only the owner can leave from their profile")
	host.cards[0].leave_button.pressed.emit()
	check(host.leave_dialog.visible,"Leave icon opens confirmation")
	host.leave_dialog.canceled.emit()
	host.leave_dialog.hide()
	check(host.game.players.size() == 3 and host.board.pawns.size() == 12,"Cancel keeps player and pawns")
	var departed_id: String = host.self_id
	host.open_leave_confirmation()
	host.leave_dialog.confirmed.emit()
	host.leave_dialog.hide()
	check(await wait_until(func(): return friend.board.pawns[departed_id+"-0"].departing),"Pawn starts cinematic departure")
	check(friend.presenting and not friend.board.enabled,"Input waits for departure presentation")
	await create_timer(0.4).timeout
	await screenshot("leave-smoke")
	check(friend.board.pawns[departed_id+"-0"].get_node("PinVisual/PinBody").material_override.get_shader_parameter("exit_amount") > 0,"Pawn dissolves into a shadow")
	check(friend.board.pawns[departed_id+"-0"].base_visual.get_children().all(func(mesh): return mesh.material_override.get_shader_parameter("exit_amount") > 0),"Silver foot ring dissolves together with the white pin")
	check(await wait_until(func(): return host.home.visible and friend.game.players.size() == 2),"Leaving player returns home after animation")
	check(host.room_code.is_empty() and host.board.pawns.is_empty(),"Leaving player clears table")
	check(friend.game.currentPlayer == friend.self_id,"Next remaining player receives turn")
	check(friend.board.pawns.size() == 8 and friend.board.departure_labels.has(departed_id),"Departed corner is empty with a large label")
	check(await wait_until(func(): return third.game.players.size() == 2),"Departure reaches every client")
	await screenshot("leave-empty-corner")
	check(friend.cards[0].status_label.text == "Left game" and not friend.cards[0].roll.visible,"Departed profile cannot roll")
	friend.reduced_motion = true
	friend.board.reduced_motion = true
	friend.open_leave_confirmation()
	friend.leave_dialog.confirmed.emit()
	friend.leave_dialog.hide()
	check(await wait_until(func(): return third.game.get("phase") == "finished"),"Last remaining player wins")
	check(third.result.visible and third.result_list.get_child_count() == 1,"Winner is announced with an avatar")
	await create_timer(4.2).timeout
	check(third.result.visible and not third.home.visible,"Winner stays at the results until choosing OK")
	third.result.confirmed.emit()
	check(await wait_until(func(): return third.home.visible),"Winner returns home after OK")
	check(third.room_code.is_empty(),"Winner detached from server room")
	third.request_room(false)
	check(await wait_until(func(): return not third.room_code.is_empty() and third.game.get("phase") == "lobby"),"Winner can immediately create another room")
	for client in clients:
		client.network.disconnect_server()
		client.queue_free()
	await process_frame
	print("Leaving: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func screenshot(filename: String) -> void:
	if DisplayServer.get_name() != "headless":
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../../test-results/"+filename+".png"))
