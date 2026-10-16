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

func run() -> void:
	var client = MainScene.instantiate()
	root.add_child(client)
	client.network.disconnect_server()
	client.network.set_process(false)
	client.online = true
	client.self_id = "0"
	var players: Array = []
	var tokens: Array = []
	for seat in range(4):
		var id := str(seat)
		var color: String = client.BoardMath.COLORS[seat]
		players.append({"id": id, "name": "Player " + id, "color": color, "ready": true})
		for index in range(4):
			tokens.append({"id": id + "-" + str(index), "color": color, "position": 0})
	client._receive({"type": "STATE", "roomCode": "TEST", "state": {"version": 1, "players": players, "tokens": tokens, "currentPlayer": "0", "phase": "rolling", "dice": null, "finishOrder": []}})
	for viewport_size in [Vector2i(420,860), Vector2i(764,815), Vector2i(390,844), Vector2i(320,740), Vector2i(1440,900), Vector2i(1366,600), Vector2i(1920,507), Vector2i(844,390), Vector2i(640,360), Vector2i(390,844)]:
		root.content_scale_size = viewport_size
		root.size = viewport_size
		client._safe_area()
		for frame in range(5):
			await process_frame
		var red: Rect2 = client.cards[0].get_global_rect()
		var green: Rect2 = client.cards[1].get_global_rect()
		var yellow: Rect2 = client.cards[2].get_global_rect()
		var blue: Rect2 = client.cards[3].get_global_rect()
		check(red.end.x <= green.position.x, "Red and green cards stay on opposite sides")
		check(blue.end.x <= yellow.position.x, "Blue and yellow cards stay on opposite sides")
		check(absf(red.position.x-blue.position.x) < 1 and absf(green.end.x-yellow.end.x) < 1, "Both rows align symmetrically")
		check(red.position.y < blue.position.y, "Cards keep their matching board corners")
		var board_rect: Rect2 = client.board.printed_rect()
		board_rect.position += client.board.global_position
		check(absf(board_rect.get_center().x-client.get_viewport_rect().get_center().x) <= 1.0,"Board stays horizontally centered at %s (offset %.2f)" % [viewport_size,board_rect.get_center().x-client.get_viewport_rect().get_center().x])
		check(not board_rect.intersects(red) and not board_rect.intersects(blue),"Player rows never overlap the play area")
		check(client.get_viewport_rect().encloses(board_rect),"Board fits the available viewport")
		check(board_rect.size.y <= client.board.preferred_height(board_rect.size.x)+1,"Printed board uses the available height")
		if client.using_landscape:
			check(red.end.x <= board_rect.position.x and green.position.x >= board_rect.end.x,"Wide windows place profiles beside the board")
			check(board_rect.size.y >= client.cards[0].size.y*1.5,"Short desktop windows keep the board larger than the profile cards")
		else:
			var top_row: Rect2 = client.player_rows[0].get_global_rect()
			var bottom_row: Rect2 = client.player_rows[1].get_global_rect()
			check(absf(board_rect.position.y-top_row.end.y-(bottom_row.position.y-board_rect.end.y)) <= 2,"Visible board and player rows keep balanced spacing")
		for card in client.cards:
			check(client.get_viewport_rect().encloses(card.get_global_rect()),"Profile and actions fit even on narrow screens")
			check(card.avatar.global_position.y-card.name_label.get_global_rect().end.y >= 4,"Player name has breathing room above the avatar")
			check(card.panel.get_global_rect().end.y-card.lives.get_global_rect().end.y >= 10,"Life dots stay clear of the timer path")
			var frame_style: StyleBoxFlat = card.panel.get_theme_stylebox("panel")
			check(frame_style.border_width_left == 1,"Profile border remains thin for every color")
			if card.roll.visible:
				check(card.roll.global_position.x-card.avatar.get_global_rect().end.x >= 12,"Avatar and dice have a distinct gap")
				check(card.avatar.size.y > card.roll.size.y and card.roll.size.y >= 48,"Avatar remains taller than the dice with a usable roll target")
			check(card.lives.remaining == 5,"Every player starts with five filled life dots")
			check(is_equal_approx(card.lives.size.x,card.avatar.size.x),"Five dots span exactly the avatar width")
			check(card.lives.global_position.y >= card.avatar.get_global_rect().end.y+4,"Life dots sit below the portrait")
			check(is_equal_approx(card.lives.global_position.x,card.avatar.global_position.x),"Life dots align with the avatar")
			check(card.lives.accent == client.Design.COLORS[client.BoardMath.COLORS[int(card.player_id)]],"Life dots use the player's board color")
	var emoji_style: StyleBoxFlat = client.cards[1].gift.get_theme_stylebox("normal")
	var chat_style: StyleBoxFlat = client.cards[0].chat.get_theme_stylebox("normal")
	check(emoji_style.bg_color == chat_style.bg_color and emoji_style.border_color == chat_style.border_color,"Emoji, chat and camera buttons share the same theme")
	var chat_center: Vector2 = client.cards[0].chat.get_global_rect().get_center()-client.board.global_position
	check(not client.board._has_point(chat_center),"Board headroom cannot intercept the profile toolbar")
	client.game.timeoutLives = {"0":3,"1":1,"2":5,"3":0}
	client.refresh_controls()
	for seat in range(4):
		check(client.cards[seat].lives.remaining == [3,1,5,0][seat],"Server balances update each player's dots independently")
	# Missing seats must not collapse the other card into the wrong corner.
	client.cards[0].hide()
	await process_frame
	await process_frame
	check(client.cards[1].get_global_rect().get_center().x > client.get_viewport_rect().get_center().x, "Green remains right aligned when red is absent")
	client.cards[0].show()
	client.game.finishOrder = ["2"]
	client.game.currentPlayer = "2"
	client.turn_deadline_ticks = Time.get_ticks_msec() + 30000
	client.refresh_controls()
	await create_timer(0.12).timeout
	check(client.cards[2].status_label.text == "Winner · 1st", "Winner badge survives periodic clock updates")
	check(not client.cards[2].turn_active and not client.cards[2].roll.visible, "Ranked player never shows an active clock or dice")
	check(client.cards[2].panel.timer_fraction == -1, "Completed player has no active timer border")
	client.game.finishOrder = []
	client.game.currentPlayer = "0"
	client.refresh_controls()
	check(client.cards[2].finish_rank == -1 and client.cards[2].status_label.text != "Winner · 1st", "Restart clears the winner badge")
	for seat in range(4):
		client.chat_bubbles.show_message(client.cards[seat], "Player " + str(seat), "Hello table! This is a longer message to check wrapping and readable captions on every corner.")
	for frame in range(5):
		await process_frame
	for entry in client.chat_bubbles.entries.values():
		var bubble: PanelContainer = entry.panel
		var caption: Label = bubble.get_child(0)
		check(bubble.size.x <= 200 and bubble.size.y < 70, "Chat caption remains compact")
		check(client.get_viewport_rect().encloses(bubble.get_global_rect()), "Chat stays within the viewport at every corner")
		check(not bubble.get_global_rect().intersects(entry.card.panel.get_global_rect()), "Caption does not cover sender identity or dice")
		var background: StyleBoxFlat = bubble.get_theme_stylebox("panel")
		check(background.bg_color.srgb_to_linear().get_luminance() < 0.05 and caption.get_theme_color("font_color").get_luminance() > 0.9, "Chat uses readable light text on dark background")
	client.chat_bubbles.show_message(client.cards[0], "Player 0", "Replacement")
	check(client.chat_bubbles.entries.size() == 4, "New sender message replaces the existing caption")
	client.queue_free()
	await process_frame
	print("UI regressions: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
