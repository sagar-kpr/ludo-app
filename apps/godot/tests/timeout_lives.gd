extends SceneTree

const MainScene = preload("res://scenes/main.tscn")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func wait_until(condition: Callable, seconds: float = 16.0) -> bool:
	var deadline := Time.get_ticks_msec()+int(seconds*1000)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await create_timer(0.02).timeout
	return bool(condition.call())

func run() -> void:
	var host = MainScene.instantiate()
	var friend = MainScene.instantiate()
	root.add_child(host)
	root.add_child(friend)
	friend.hide()
	check(await wait_until(func(): return host.online and friend.online),"Both clients connect")
	host.name_input.text = "Idle Player"
	host.request_room(false)
	check(await wait_until(func(): return not host.room_code.is_empty() and not host.pending),"Host creates room")
	friend.name_input.text = "Active Player"
	friend.join_input.text = host.room_code
	friend.request_room(true)
	check(await wait_until(func(): return host.game.get("players",[]).size() == 2 and not host.pending),"Friend joins")
	host.send({"type":"START_GAME"})
	check(await wait_until(func(): return host.game.get("phase") == "rolling"),"Match starts")
	check(host.turn_duration_ms == 1000,"Test uses an accelerated timeout clock")
	var idle_id: String = host.self_id
	for remaining in [5,4,3,2,1,0]:
		check(await wait_until(func(): return host.cards[0].lives.remaining == remaining),"Timeout reduces the displayed life count to %d" % remaining)
		check(host.cards[0].lives.size.x == host.cards[0].avatar.size.x,"Dots match portrait width")
	check(host.game.players.size() == 2 and not host.home.visible,"Using the fifth dot keeps the player in the game")
	check(host.board.pawns.has(idle_id+"-0") and not host.board.pawns[idle_id+"-0"].departing,"Last automatic action finishes without washing pawns out")
	check(await wait_until(func(): return host.board.pawns.has(idle_id+"-0") and host.board.pawns[idle_id+"-0"].departing,30.0),"A later timeout at zero dots triggers departure")
	check(host.cards[0].lives.remaining == 0,"No filled dots remain during the smoke effect")
	if DisplayServer.get_name() != "headless":
		await create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../../test-results/timeout-lives-smoke.png"))
	check(await wait_until(func(): return host.home.visible and host.room_code.is_empty()),"Inactive player returns home after pawns disappear")
	check(host.notice.text.contains("no chances left"),"Home explains inactivity removal")
	check(await wait_until(func(): return friend.game.get("phase") == "finished"),"Remaining player wins")
	check(friend.board.departure_labels.has(idle_id) and friend.cards[0].lives.remaining == 0,"Other player sees empty marked corner and zero lives")
	check(await wait_until(func(): return friend.home.visible),"Winner returns home automatically")
	host.request_room(false)
	check(await wait_until(func(): return not host.room_code.is_empty() and host.game.get("phase") == "lobby"),"Removed player can create another room")
	check(host.game.get("timeoutLives",{}).get(host.self_id) == 5,"A new match restores five chances")
	for client in [host,friend]:
		client.network.disconnect_server()
		client.queue_free()
	await process_frame
	print("Timeout lives: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
