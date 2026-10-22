extends SceneTree

const MainScene = preload("res://scenes/main.tscn")
var failures := 0
var checks := 0

func _initialize() -> void:
	ProjectSettings.set_setting("rally/realtime_url","ws://127.0.0.1:1")
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
	check(client.dashboard.visible and not client.friends_setup.visible,"Home opens on mode cards without form fields")
	for viewport_size in [Vector2i(320,568),Vector2i(393,852),Vector2i(420,860),Vector2i(844,390),Vector2i(1440,900)]:
		root.content_scale_size = viewport_size
		root.size = viewport_size
		client._safe_area()
		for frame in range(5):
			await process_frame
		var friends_rect: Rect2 = client.friends_button.get_global_rect()
		var computer_rect: Rect2 = client.computer_button.get_global_rect()
		print("Dashboard %s: friends %s AI %s" % [viewport_size,friends_rect,computer_rect])
		check(friends_rect.end.x <= computer_rect.position.x,"Mode cards never overlap")
		check(absf(friends_rect.size.x-computer_rect.size.x) <= 1,"Mode cards keep balanced widths with pixel rounding")
		check(friends_rect.size.x >= 135,"Cards remain usable on narrow phones")
		check(computer_rect.end.x <= viewport_size.x,"Cards remain inside screen width")
		client.friends_button.pressed.emit()
		for frame in range(3):
			await process_frame
		check(client.friends_setup.visible and not client.dashboard.visible,"Friends opens its own setup screen")
		check(client.name_input.is_visible_in_tree() and client.join_input.is_visible_in_tree(),"Name and room code are only shown inside friend setup")
		check(not client.computer_button.is_visible_in_tree(),"AI card stays on the dashboard")
		check(client.create_button.size.y >= 44 and client.join_button.size.y >= 44,"Room actions preserve touch target sizes")
		client.name_input.text = "Remember me"
		client.join_input.text = "ABCD-EF12"
		client.show_friends_setup(false)
		check(client.name_input.text == "Remember me" and client.join_input.text == "ABCD-EF12","Back navigation preserves entered values")
	client.show_friends_setup(true)
	client.return_home()
	check(client.dashboard.visible and not client.friends_setup.visible,"Leaving a match returns to the mode dashboard")
	client.queue_free()
	await process_frame
	print("Dashboard: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
