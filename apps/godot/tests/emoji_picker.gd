extends SceneTree

const MainScene = preload("res://scenes/main.tscn")
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

func layout() -> void:
	for frame in range(6):
		await process_frame

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
		var color: String = client.BoardMath.COLORS[seat]
		players.append({"id":str(seat),"name":["Maya","Arjun","Sam","Priya"][seat],"color":color,"ready":true})
		for index in range(4):
			tokens.append({"id":"%d-%d" % [seat,index],"color":color,"position":0})
	client._receive({"type":"STATE","roomCode":"PICKER","state":{"version":1,"players":players,"tokens":tokens,"currentPlayer":"0","phase":"rolling","dice":null}})
	for dimensions in [Vector2i(420,860),Vector2i(390,844),Vector2i(764,815),Vector2i(320,640)]:
		root.size = dimensions
		client._safe_area()
		await layout()
		for seat in [1,2,3]:
			client.cards[seat].gift.pressed.emit()
			await layout()
			check(client.sticker_picker.visible,"Tapped emoji icon opens picker")
			check(client.sticker_target == str(seat) and client.sticker_anchor == client.cards[seat].gift,"Picker follows the tapped recipient")
			var rect := Rect2(Vector2(client.sticker_picker.position),Vector2(client.sticker_picker.size))
			var anchor: Rect2 = client.cards[seat].gift.get_global_rect()
			if not client.sticker_picker.is_embedded():
				rect = client.get_viewport().get_screen_transform().affine_inverse()*rect
			check(client.get_viewport_rect().grow(-4).encloses(rect),"Picker stays within the screen")
			if client.get_viewport_rect().end.y-8-anchor.end.y-8 >= 128:
				check(absf(rect.position.y-anchor.end.y-8) <= 2,"Picker opens directly below tapped emoji icon")
			else:
				check(absf(rect.end.y-anchor.position.y+8) <= 2,"Bottom-edge picker stays beside its icon by flipping above")
			check(rect.size.x <= 282 and rect.size.y <= 346,"Picker uses a compact footprint")
			check(client.sticker_grid.get_child_count() == 24,"All 24 stickers and emotions remain available")
			var panel_style: StyleBoxFlat = client.sticker_picker.get_theme_stylebox("panel")
			check(panel_style.bg_color.srgb_to_linear().get_luminance() < 0.05,"Picker matches the dark game theme")
			var tile = client.sticker_grid.get_child(0)
			check(tile.get_theme_stylebox("normal").bg_color.srgb_to_linear().get_luminance() < 0.05 and tile.get_theme_color("font_color").get_luminance() > 0.8,"Tiles have readable light captions on navy")
			client.sticker_scroll.scroll_vertical = 9999
			await layout()
			check(client.sticker_scroll.get_global_rect().encloses(client.sticker_grid.get_child(23).get_global_rect()),"Last emoji remains reachable in the scroll area")
			client.sticker_picker.hide()
			await layout()
	root.size = Vector2i(420,860)
	client._safe_area()
	await layout()
	client.cards[1].gift.pressed.emit()
	await layout()
	await screenshot("emoji-picker-top")
	root.size = Vector2i(390,844)
	client._safe_area()
	await layout()
	var resized := Rect2(Vector2(client.sticker_picker.position),Vector2(client.sticker_picker.size))
	check(client.get_viewport_rect().encloses(resized),"Open picker follows viewport resizing")
	client.sticker_picker.hide()
	await layout()
	client.cards[2].gift.pressed.emit()
	await layout()
	await screenshot("emoji-picker-bottom")
	client.sticker_picker.hide()
	await layout()
	client.open_sticker_picker(client.self_id)
	check(not client.sticker_picker.visible,"Own profile cannot open a self-send picker")
	# Exercise the short-below case where scrolling preserves proximity.
	var anchor := Button.new()
	client.add_child(anchor)
	anchor.position = Vector2(24,client.get_viewport_rect().end.y-220)
	anchor.size = Vector2(40,28)
	client.sticker_anchor = anchor
	client.position_sticker_picker()
	client.sticker_picker.popup(Rect2i(client.sticker_picker.position,client.sticker_picker.size))
	await layout()
	check(client.sticker_picker.size.y < 220 and client.sticker_picker.position.y > anchor.global_position.y,"A short picker stays below when there is space for a row")
	client.sticker_scroll.scroll_vertical = 9999
	await layout()
	check(client.sticker_scroll.scroll_vertical > 0,"Constrained picker scrolls")
	check(client.sticker_scroll.get_global_rect().encloses(client.sticker_grid.get_child(23).get_global_rect()),"Constrained picker still reaches the last emoji")
	client.sticker_picker.hide()
	for kind in client.StickerArt.EMOTIONS:
		client.show_sticker({"targetPlayerId":"1","fromPlayerId":"0","sticker":kind})
		await process_frame
		var effect = client.sticker_layer.get_child(client.sticker_layer.get_child_count()-1)
		effect._process(0.8)
		check(effect.art.model.get_child_count() > 0,"Emotion %s has dedicated artwork" % kind)
		check(effect.art.playing,"Emotion %s animates after delivery" % kind)
		var before: Transform3D = effect.art.model.transform
		effect.art._process(0.3)
		check(effect.art.model.transform != before,"Emotion %s moves its expression" % kind)
		effect.queue_free()
		await process_frame
		client.reduced_motion = true
		client.show_sticker({"targetPlayerId":"1","fromPlayerId":"0","sticker":kind})
		await process_frame
		effect = client.sticker_layer.get_child(client.sticker_layer.get_child_count()-1)
		effect._process(0.8)
		check(not effect.art.playing,"Emotion %s respects reduced motion" % kind)
		before = effect.art.model.transform
		effect.art._process(0.3)
		check(effect.art.model.transform == before,"Reduced-motion emotion stays still")
		effect._process(4.0)
		await process_frame
		check(client.sticker_layer.get_child_count() == 0,"Emotion effect cleans itself up")
		client.reduced_motion = false
	client.queue_free()
	await process_frame
	print("Emoji picker: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func screenshot(filename: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../../test-results/"+filename+".png"))
