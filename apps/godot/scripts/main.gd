extends Control

const Design = preload("res://scripts/design.gd")
const Realtime = preload("res://scripts/realtime.gd")
const Board = preload("res://scripts/board.gd")
const BoardMath = preload("res://scripts/board_math.gd")
const PlayerCard = preload("res://scripts/player_card.gd")
const GameBackground = preload("res://scripts/game_background.gd")
const Feedback = preload("res://scripts/feedback.gd")
const ChatBubbles = preload("res://scripts/chat_bubbles.gd")
const StickerArt = preload("res://scripts/sticker_art.gd")
const StickerEffect = preload("res://scripts/sticker_effect.gd")
var feedback
var chat_bubbles
var network
var board
var board_holder: MarginContainer
var player_rows: Array[HBoxContainer] = []
var landscape_view: HBoxContainer
var left_profiles: VBoxContainer
var right_profiles: VBoxContainer
var using_landscape := false
var content: VBoxContainer
var home: VBoxContainer
var home_card: VBoxContainer
var lobby: VBoxContainer
var game_view: VBoxContainer
var status: Label
var notice: Label
var name_input: LineEdit
var join_input: LineEdit
var room_label: Label
var lobby_players: Label
var create_button: Button
var join_button: Button
var start_button: Button
var cards: Array = []
var game: Dictionary = {}
var self_id := ""
var room_code := ""
var online := false
var pending := false
var presenting := false
var awaiting_move_state := false
var processing_events := false
var events: Array[Dictionary] = []
var latest_version := -1
var chat_log: RichTextLabel
var chat_input: LineEdit
var chat_dialog: AcceptDialog
var menu: AcceptDialog
var leave_dialog: ConfirmationDialog
var exit_scheduled := false
var result: AcceptDialog
var result_stats: Label
var restart_button: Button
var connection_detail := "Connecting…"
var config := ConfigFile.new()
var reduced_motion := false
var endpoint := ""
var media_status: Label
var game_background
var brand_label: Label
var turn_deadline_ticks := 0
var turn_duration_ms := 30000
var sticker_picker: PopupPanel
var sticker_target := ""
var sticker_layer: Control
var sticker_title: Label
var sticker_scroll: ScrollContainer
var sticker_grid: GridContainer
var sticker_anchor: Control
var web_form_ready := false
var web_form_elapsed := 0.0
var web_focused_field := ""
var web_viewport_revision := -1
var web_safe_top := 0.0
var web_safe_bottom := 0.0

func _process(delta: float) -> void:
	if is_instance_valid(sticker_picker) and sticker_picker.visible:
		position_sticker_picker()
	web_form_elapsed += delta
	if OS.has_feature("web") and is_instance_valid(name_input) and (web_form_elapsed >= 0.1 or home.is_visible_in_tree()):
		web_form_elapsed = 0
		sync_web_form()
	if board and turn_deadline_ticks > 0 and online and not pending and not presenting:
		var now := Time.get_ticks_msec()
		var phase_open := now >= turn_deadline_ticks-turn_duration_ms and now < turn_deadline_ticks
		if board.enabled != phase_open:
			refresh_controls()

func sync_web_form() -> void:
	if not OS.has_feature("web"):
		return
	if not web_form_ready:
		JavaScriptBridge.eval(FileAccess.get_file_as_string("res://web/native_inputs.js"),true)
		web_form_ready = true
	var fields: Array = []
	for entry in [[name_input,"rally-name","Your player name",18],[join_input,"rally-code","Friend’s room code",9]]:
		var input: LineEdit = entry[0]
		var rect := input.get_global_rect()
		fields.append({"id":entry[1],"label":entry[2],"max":entry[3],"value":input.text,"placeholder":input.placeholder_text,"rect":[rect.position.x,rect.position.y,rect.size.x,rect.size.y]})
	var scroll := content.get_node("SetupScroll") as ScrollContainer
	var clip := scroll.get_global_rect()
	var data := {"fields":fields,"visible":home.is_visible_in_tree(),"width":get_viewport_rect().size.x,"height":get_viewport_rect().size.y,"clip":[clip.position.x,clip.position.y,clip.size.x,clip.size.y]}
	var values: Variant = JSON.parse_string(str(JavaScriptBridge.eval("window.__rallyNativeInputs("+JSON.stringify(data)+")",true)))
	if values is Dictionary:
		# Keep text and controls at their normal width when a keyboard shortens
		# the visible viewport. The setup panel scrolls instead of shrinking.
		var css_width := maxf(1,float(values.get("viewportWidth",420)))
		var css_height := maxf(1,float(values.get("viewportHeight",860)))
		var reference_width := maxf(420,css_width)
		var safe_top := float(values.get("safeTop",0))*reference_width/css_width
		var safe_bottom := float(values.get("safeBottom",0))*reference_width/css_width
		if not is_equal_approx(safe_top,web_safe_top) or not is_equal_approx(safe_bottom,web_safe_bottom):
			web_safe_top = safe_top
			web_safe_bottom = safe_bottom
			_safe_area.call_deferred()
		var reference := Vector2i(roundi(reference_width),roundi(css_height*reference_width/css_width))
		if get_window().content_scale_size != reference:
			get_window().content_scale_size = reference
		name_input.text = str(values.get("rally-name",name_input.text))
		join_input.text = str(values.get("rally-code",join_input.text))
		var focused := str(values.get("focused",""))
		var revision := int(values.get("viewportRevision",0))
		if focused != web_focused_field or revision != web_viewport_revision:
			web_focused_field = focused
			web_viewport_revision = revision
			# Let containers settle after a keyboard resize before scrolling once.
			if home.is_visible_in_tree() and focused in ["rally-name","rally-code"]:
				call_deferred("reveal_web_field",focused)

func reveal_web_field(id: String) -> void:
	await get_tree().process_frame
	if not home.is_visible_in_tree() or id != web_focused_field:
		return
	var scroll := content.get_node("SetupScroll") as ScrollContainer
	scroll.ensure_control_visible(name_input if id == "rally-name" else join_input)

func configure_web_field(input: LineEdit) -> void:
	if OS.has_feature("web"):
		# Keep the layout slot; the browser supplies its only visible input.
		input.modulate.a = 0.0
		input.mouse_filter = Control.MOUSE_FILTER_IGNORE
		input.focus_mode = Control.FOCUS_NONE
		input.virtual_keyboard_enabled = false

func _ready() -> void:
	theme = Design.make_theme()
	config.load("user://preferences.cfg")
	reduced_motion = bool(config.get_value("accessibility", "reduced_motion", false))
	endpoint = str(ProjectSettings.get_setting("rally/realtime_url"))
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--server="):
			endpoint = argument.trim_prefix("--server=")
	build_ui()
	feedback = Feedback.new()
	add_child(feedback)
	feedback.sound_enabled = bool(config.get_value("feedback","sound",true))
	feedback.haptics_enabled = bool(config.get_value("feedback","haptics",true))
	board.step_landed.connect(func(id: String): feedback.cue("step",id.begins_with(self_id+"-")))
	board.token_captured.connect(func(mover: String, captured: String): feedback.cue("capture",mover.begins_with(self_id+"-") or captured.begins_with(self_id+"-")))
	for card in cards:
		card.gift_pressed.connect(open_sticker_picker)
		card.chat_pressed.connect(open_table_chat)
		card.leave_pressed.connect(open_leave_confirmation)
		card.camera_pressed.connect(func(): menu.popup_centered())
		card.dice.roll_contact.connect(func(settled: bool, strength: float):
			feedback.cue("dice_settle" if settled else "dice",card.player_id == self_id,strength)
		)
	network = Realtime.new()
	add_child(network)
	network.event_received.connect(_receive)
	network.connection_changed.connect(func(connected: bool, detail: String):
		online = connected
		connection_detail = detail
		if not online:
			pending = false
			if not room_code.is_empty():
				connection_detail = "Connection lost · reconnecting…"
		refresh_controls()
	)
	network.connect_server(endpoint)
	if Engine.has_singleton("RallyMedia"):
		var media = Engine.get_singleton("RallyMedia")
		media.connect("media_status", func(_state: String, message: String): media_status.text = message)
	get_viewport().size_changed.connect(_safe_area)
	_safe_area()

func _safe_area() -> void:
	var inset_top := 8
	var inset_bottom := 8
	if OS.get_name() == "Android":
		var safe := DisplayServer.get_display_safe_area()
		var screen := DisplayServer.screen_get_size()
		var ratio := get_viewport_rect().size.y / maxf(screen.y, 1)
		inset_top = maxi(12, int(safe.position.y * ratio))
		inset_bottom = maxi(12, int((screen.y - safe.end.y) * ratio))
	if game_view.visible:
		# Leave breathing room below phone browser chrome and the status area.
		inset_top = maxi(inset_top,maxi(24 if get_viewport_rect().size.x < 640 else 8,ceili(web_safe_top)+8))
		inset_bottom = maxi(inset_bottom,ceili(web_safe_bottom)+8)
	var margin := get_node("SafeArea") as MarginContainer
	margin.add_theme_constant_override("margin_top", inset_top)
	margin.add_theme_constant_override("margin_bottom", inset_bottom)
	margin.add_theme_constant_override("margin_left",4)
	margin.add_theme_constant_override("margin_right",4)
	# Keep the entire safe area for the table; setup still needs its title and notices.
	content.get_child(0).visible = not game_view.visible
	notice.visible = not game_view.visible
	var available := get_viewport_rect().size
	if is_instance_valid(home_card):
		home_card.custom_minimum_size.y = maxf(420.0, available.y * 0.60)
	if game_view.visible and is_instance_valid(board):
		var width_limit := available.x-8.0
		var mobile_portrait := available.x < 640.0
		board.framing_width = 15.8 if mobile_portrait else board.FRAMING_WIDTH
		for card in cards:
			card.fit_width((width_limit-16.0)*0.5,available.y,mobile_portrait)
		set_game_layout(available.x >= 640.0 and available.x > available.y*1.25)
		if using_landscape:
			var profile_width := 156.0 if available.y < 680.0 else 180.0
			left_profiles.custom_minimum_size.x = profile_width
			right_profiles.custom_minimum_size.x = profile_width
			var chrome: float = inset_top + inset_bottom
			var height_limit := maxf(80.0,available.y-chrome)
			var width := floorf(minf(maxf(80.0,width_limit-profile_width*2-24.0),height_limit/board.preferred_height(1.0)))
			content.custom_minimum_size.x = width+profile_width*2+24.0
			board_holder.add_theme_constant_override("margin_top",0)
			board.custom_minimum_size = Vector2(width,floorf(minf(height_limit,board.preferred_height(width))))
			return
		board.custom_minimum_size.x = 0
		var top_row := player_rows[0]
		var bottom_row := player_rows[1]
		var rows := top_row.get_combined_minimum_size().y + bottom_row.get_combined_minimum_size().y
		var chrome: float = rows + inset_top + inset_bottom + game_view.get_theme_constant("separation")*2
		var height_limit := maxf(80.0,available.y-chrome)
		var row_width := maxf(top_row.get_combined_minimum_size().x,bottom_row.get_combined_minimum_size().x)
		# Use the same projected bounds as the camera: no guessed square size
		# or oversized viewport bands between the board and its player rows.
		var board_width := floorf(minf(width_limit,maxf(row_width,height_limit/(board.preferred_height(1.0)*(1.0-board.top_headroom_fraction())))))
		content.custom_minimum_size.x = board_width
		var headroom: float = board.top_headroom_fraction()
		var render_height := floorf(minf(height_limit/(1.0-headroom),board.preferred_height(board_width)))
		board_holder.add_theme_constant_override("margin_top",-roundi(render_height*headroom))
		board.custom_minimum_size.y = render_height
	else:
		content.custom_minimum_size.x = minf(600.0,available.x-24.0)

func set_game_layout(landscape: bool) -> void:
	if using_landscape == landscape:
		return
	using_landscape = landscape
	if landscape:
		for row in player_rows:
			row.hide()
		for seat in [0,3]:
			cards[seat].reparent(left_profiles)
		left_profiles.move_child(cards[0],0)
		for seat in [1,2]:
			cards[seat].reparent(right_profiles)
		right_profiles.move_child(cards[1],0)
		board_holder.reparent(landscape_view)
		landscape_view.move_child(board_holder,1)
		landscape_view.show()
	else:
		landscape_view.hide()
		for pair in range(2):
			var seats := [0,1] if pair == 0 else [3,2]
			for seat in seats:
				cards[seat].reparent(player_rows[pair])
			player_rows[pair].move_child(cards[seats[0]],0)
			player_rows[pair].show()
		board_holder.reparent(game_view)
		game_view.move_child(board_holder,1)

func label(text: String, font_size: int = 15, color: Color = Design.INK) -> Label:
	var item := Label.new()
	item.text = text
	item.add_theme_font_size_override("font_size", font_size)
	if font_size >= 19:
		var emphasis := FontVariation.new()
		emphasis.base_font = ThemeDB.fallback_font
		emphasis.variation_embolden = 0.55
		item.add_theme_font_override("font", emphasis)
	item.add_theme_color_override("font_color", color)
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return item

func button(text: String, action: Callable) -> Button:
	var item := Button.new()
	item.text = text
	item.custom_minimum_size.y = 48
	item.pressed.connect(action)
	item.resized.connect(func(): item.pivot_offset = item.size*0.5)
	item.button_down.connect(func():
		if not reduced_motion:
			item.create_tween().tween_property(item,"scale",Vector2(0.97,0.97),0.09).set_trans(Tween.TRANS_SINE)
	)
	item.button_up.connect(func():
		if reduced_motion:
			item.scale = Vector2.ONE
		else:
			item.create_tween().tween_property(item,"scale",Vector2.ONE,0.15).set_trans(Tween.TRANS_SINE)
	)
	return item

func secondary_button(text: String, action: Callable) -> Button:
	var item := button(text, action)
	item.add_theme_color_override("font_color", Color.WHITE)
	item.add_theme_color_override("font_hover_color", Color.WHITE)
	item.add_theme_color_override("font_pressed_color", Color.WHITE)
	item.add_theme_stylebox_override("normal", Design.surface(Color("1b2038"), 14, Design.DIVIDER))
	item.add_theme_stylebox_override("hover", Design.surface(Color("1f466b"), 14, Design.GOLD))
	item.add_theme_stylebox_override("pressed", Design.surface(Color("162e4b"), 14, Design.GOLD))
	item.add_theme_stylebox_override("disabled", Design.surface(Color("15192c"), 14, Design.DIVIDER))
	return item

func panel(parent: Node) -> VBoxContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	card.add_child(column)
	return column

func build_ui() -> void:
	var background := ColorRect.new()
	background.color = Design.CREAM
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	game_background = GameBackground.new()
	game_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game_background.show()
	add_child(game_background)
	var safe := MarginContainer.new()
	safe.name = "SafeArea"
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	safe.add_theme_constant_override("margin_left", 16)
	safe.add_theme_constant_override("margin_right", 16)
	add_child(safe)
	var center := HBoxContainer.new()
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	safe.add_child(center)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	content.add_theme_constant_override("separation", 6)
	center.add_child(content)
	var header := HBoxContainer.new()
	content.add_child(header)
	var brand := label("✦  RALLY LUDO", 16, Design.INK)
	brand_label = brand
	brand.autowrap_mode = TextServer.AUTOWRAP_OFF
	header.add_child(brand)
	status = label("Connecting…", 11, Design.MUTED)
	status.autowrap_mode = TextServer.AUTOWRAP_OFF
	status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(status)
	# Only home/lobby scroll. The board and player cards stay fixed during play.
	var scroll := ScrollContainer.new()
	scroll.name = "SetupScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var setup := VBoxContainer.new()
	setup.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	setup.add_theme_constant_override("separation", 14)
	scroll.add_child(setup)
	home = VBoxContainer.new()
	home.add_theme_constant_override("separation", 18)
	setup.add_child(home)
	home.add_child(label("Roll into the moment.", 32, Design.INK))
	home.add_child(label("Create a room or join your friends with a code.", 16, Design.MUTED))
	home_card = panel(home)
	home_card.alignment = BoxContainer.ALIGNMENT_CENTER
	home_card.add_theme_constant_override("separation", 22)
	home_card.add_child(label("Your player name", 14, Design.MUTED))
	name_input = LineEdit.new()
	name_input.placeholder_text = "Guest"
	name_input.max_length = 18
	name_input.text = str(config.get_value("player", "name", ""))
	name_input.custom_minimum_size.y = 60
	name_input.focus_mode = Control.FOCUS_ALL
	name_input.mouse_filter = Control.MOUSE_FILTER_STOP
	name_input.virtual_keyboard_enabled = true
	name_input.focus_entered.connect(func(): scroll.ensure_control_visible(name_input))
	configure_web_field(name_input)
	home_card.add_child(name_input)
	create_button = button("Create a private room", func(): request_room(false))
	create_button.custom_minimum_size.y = 60
	home_card.add_child(create_button)
	join_input = LineEdit.new()
	join_input.placeholder_text = "Friend’s room code"
	join_input.max_length = 9
	join_input.custom_minimum_size.y = 60
	join_input.focus_mode = Control.FOCUS_ALL
	join_input.mouse_filter = Control.MOUSE_FILTER_STOP
	join_input.virtual_keyboard_enabled = true
	join_input.focus_entered.connect(func(): scroll.ensure_control_visible(join_input))
	configure_web_field(join_input)
	home_card.add_child(join_input)
	join_button = secondary_button("Join with code", func(): request_room(true))
	join_button.custom_minimum_size.y = 60
	home_card.add_child(join_button)
	home.add_child(label("Guest friendly  ·  Android + web  ·  2–4 players", 12, Design.MUTED))
	lobby = VBoxContainer.new()
	lobby.add_theme_constant_override("separation", 16)
	lobby.hide()
	setup.add_child(lobby)
	lobby.add_child(label("Your table is ready", 28, Design.INK))
	var lobby_card := panel(lobby)
	lobby_card.add_child(label("PRIVATE ROOM  ·  INVITE YOUR FRIENDS", 12, Design.MUTED))
	room_label = label("", 32, Design.FOREST)
	lobby_card.add_child(room_label)
	lobby_card.add_child(secondary_button("Copy room code", func():
		DisplayServer.clipboard_set(room_code)
		notice.text = "Room code copied. Send it to your friends."
	))
	lobby_players = label("", 17, Design.INK)
	lobby_card.add_child(lobby_players)
	start_button = button("Start game", func(): send({"type":"START_GAME"}))
	lobby.add_child(start_button)
	lobby.add_child(label("The host can start when at least 2 players have joined.\nEveryone uses the same room code.", 14, Design.MUTED))
	game_view = VBoxContainer.new()
	game_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	game_view.add_theme_constant_override("separation", 0)
	game_view.alignment = BoxContainer.ALIGNMENT_CENTER
	game_view.hide()
	content.add_child(game_view)
	cards.resize(4)
	for pair in range(2):
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_BEGIN if pair == 0 else BoxContainer.ALIGNMENT_END
		row.add_theme_constant_override("separation", 8)
		game_view.add_child(row)
		player_rows.append(row)
		row.minimum_size_changed.connect(func(): _safe_area.call_deferred())
		for slot in range(2):
			if slot == 1:
				var spacer := Control.new()
				spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
				row.add_child(spacer)
			var seat := slot if pair == 0 else 3 - slot
			var card := PlayerCard.new()
			row.add_child(card)
			cards[seat] = card
			card.roll_pressed.connect(func(): send({"type":"ROLL_DICE"}))
			card.invite_pressed.connect(func():
				DisplayServer.clipboard_set(room_code)
				notice.text = "Room code copied. Share it with a friend."
			)
		if pair == 0:
			board = Board.new()
			board.reduced_motion = reduced_motion
			board_holder = MarginContainer.new()
			board_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
			# Keep the player rows close to the square board; spare height stays outside the group.
			board_holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			game_view.add_child(board_holder)
			board_holder.add_child(board)
			board.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			board.token_pressed.connect(func(id: String): send({"type":"MOVE_TOKEN", "tokenId":id}))
	landscape_view = HBoxContainer.new()
	landscape_view.add_theme_constant_override("separation",12)
	landscape_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	game_view.add_child(landscape_view)
	for side in range(2):
		var profiles := VBoxContainer.new()
		profiles.add_theme_constant_override("separation",8)
		profiles.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var spacer := Control.new()
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		profiles.add_child(spacer)
		landscape_view.add_child(profiles)
		if side == 0:
			left_profiles = profiles
		else:
			right_profiles = profiles
	landscape_view.hide()
	notice = label("", 12, Design.MUTED)
	# Turn messages must not grow/shrink the available board area.
	notice.custom_minimum_size.y = 34
	notice.max_lines_visible = 2
	notice.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	content.add_child(notice)
	build_dialogs()
	chat_bubbles = ChatBubbles.new()
	chat_bubbles.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(chat_bubbles)
	sticker_layer = Control.new()
	sticker_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sticker_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sticker_layer.z_index = 30
	add_child(sticker_layer)

func build_dialogs() -> void:
	leave_dialog = ConfirmationDialog.new()
	leave_dialog.title = "Leave game?"
	leave_dialog.dialog_text = "Do you really want to leave the game?"
	leave_dialog.ok_button_text = "Yes, leave"
	leave_dialog.cancel_button_text = "Stay"
	leave_dialog.min_size = Vector2i(280,140)
	leave_dialog.confirmed.connect(func(): send({"type":"LEAVE_GAME"}))
	add_child(leave_dialog)
	chat_dialog = AcceptDialog.new()
	chat_dialog.title = "Table chat"
	chat_dialog.min_size = Vector2i(280, 320)
	add_child(chat_dialog)
	var chat_column := VBoxContainer.new()
	chat_dialog.add_child(chat_column)
	chat_log = RichTextLabel.new()
	chat_log.bbcode_enabled = false
	chat_log.custom_minimum_size = Vector2(260,180)
	chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat_log.scroll_following = true
	chat_column.add_child(chat_log)
	chat_input = LineEdit.new()
	chat_input.placeholder_text = "Say something…"
	chat_input.max_length = 240
	chat_input.custom_minimum_size.y = 48
	chat_input.text_submitted.connect(func(_text: String): send_chat())
	chat_column.add_child(chat_input)
	chat_column.add_child(button("Send", send_chat))
	menu = AcceptDialog.new()
	menu.title = "Settings"
	menu.min_size = Vector2i(280, 260)
	add_child(menu)
	var settings := VBoxContainer.new()
	settings.add_theme_constant_override("separation",12)
	menu.add_child(settings)
	var motion := CheckButton.new()
	motion.text = "Reduce motion"
	motion.custom_minimum_size.y = 48
	motion.button_pressed = reduced_motion
	motion.toggled.connect(func(value: bool):
		reduced_motion = value
		board.reduced_motion = value
		for pawn in board.pawns.values():
			pawn.reduced_motion = value
		for card in cards:
			card.dice.reduced_motion = value
		for choice in sticker_grid.get_children():
			var artwork = choice.get_child(0)
			artwork.playing = artwork.kind in StickerArt.EMOTIONS and not value
		config.set_value("accessibility", "reduced_motion", value)
		config.save("user://preferences.cfg")
	)
	settings.add_child(motion)
	for kind in ["sound","haptics"]:
		var toggle := CheckButton.new()
		toggle.text = "Game sounds" if kind == "sound" else "Vibration (supported devices)"
		toggle.button_pressed = bool(config.get_value("feedback",kind,true))
		toggle.toggled.connect(func(value: bool):
			if kind == "sound":
				feedback.sound_enabled = value
			else:
				feedback.haptics_enabled = value
			config.set_value("feedback",kind,value)
			config.save("user://preferences.cfg")
		)
		if kind == "sound":
			var sound_row := HBoxContainer.new()
			sound_row.add_theme_constant_override("separation",8)
			toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			sound_row.add_child(toggle)
			var preview := button("Test",func(): feedback.cue("step"))
			preview.name = "PreviewPawnSound"
			preview.tooltip_text = "Preview pawn sound"
			sound_row.add_child(preview)
			settings.add_child(sound_row)
		else:
			settings.add_child(toggle)
	media_status = label("Camera and voice are not configured in this migration build.", 13, Design.MUTED)
	settings.add_child(media_status)
	settings.add_child(button("Retry server connection", func():
		if room_code.is_empty():
			network.connect_server(endpoint)
		else:
			media_status.text = "Automatic match recovery is still pending. Keep this session open."
	))
	settings.add_child(label("Godot migration preview · Server-authoritative gameplay",12,Design.MUTED))
	build_sticker_picker()
	result = AcceptDialog.new()
	result.title = "Match complete"
	result.min_size = Vector2i(280,240)
	add_child(result)
	var results_column := VBoxContainer.new()
	results_column.add_theme_constant_override("separation",16)
	var results_panel := PanelContainer.new()
	results_panel.add_theme_stylebox_override("panel",Design.surface(Design.CREAM,16))
	result.add_child(results_panel)
	results_panel.add_child(results_column)
	result_stats = label("",14,Design.INK)
	result_stats.autowrap_mode = TextServer.AUTOWRAP_OFF
	results_column.add_child(result_stats)
	restart_button = button("Restart game",func(): send({"type":"RESTART_GAME"}))
	results_column.add_child(restart_button)
	var results_footer := label("Same friends · Same room",12,Design.MUTED)
	results_footer.autowrap_mode = TextServer.AUTOWRAP_OFF
	results_column.add_child(results_footer)

func build_sticker_picker() -> void:
	sticker_picker = PopupPanel.new()
	sticker_picker.name = "EmojiPicker"
	var surface := Design.surface(Color("14263f"),16,Color("38618b"))
	surface.content_margin_left = 12
	surface.content_margin_right = 12
	surface.shadow_size = 0
	sticker_picker.add_theme_stylebox_override("panel",surface)
	add_child(sticker_picker)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",8)
	sticker_picker.add_child(column)
	var heading := HBoxContainer.new()
	heading.custom_minimum_size.y = 28
	heading.add_theme_constant_override("separation",8)
	column.add_child(heading)
	sticker_title = label("Send a sticker",14,Design.INK)
	sticker_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	sticker_title.custom_minimum_size = Vector2(160,24)
	sticker_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sticker_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sticker_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	heading.add_child(sticker_title)
	var close := Button.new()
	close.text = "×"
	close.tooltip_text = "Close sticker picker"
	close.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close.custom_minimum_size = Vector2(28,28)
	close.add_theme_font_size_override("font_size",20)
	close.add_theme_color_override("font_color",Design.INK)
	for state in ["normal","hover","pressed","focus"]:
		var style := Design.surface(Color("1d3757") if state == "normal" else Color("2d527b"),8,Color("38618b"))
		style.set_content_margin_all(0)
		style.shadow_size = 0
		close.add_theme_stylebox_override(state,style)
	close.pressed.connect(func(): sticker_picker.hide())
	heading.add_child(close)
	sticker_scroll = ScrollContainer.new()
	sticker_scroll.follow_focus = true
	sticker_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sticker_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	column.add_child(sticker_scroll)
	sticker_grid = GridContainer.new()
	sticker_grid.columns = 4
	sticker_grid.add_theme_constant_override("h_separation",6)
	sticker_grid.add_theme_constant_override("v_separation",6)
	sticker_scroll.add_child(sticker_grid)
	for sticker in StickerArt.CATALOG:
		var choice := Button.new()
		choice.text = StickerArt.caption(sticker)
		choice.tooltip_text = "Send " + sticker.to_lower()
		choice.custom_minimum_size = Vector2(56,64)
		choice.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		choice.add_theme_font_size_override("font_size",10)
		for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
			choice.add_theme_color_override(state,Design.INK)
		for state in ["normal","hover","pressed","focus"]:
			var style := Design.surface(Color("1c3555") if state == "normal" else Color("285483"),10,Color("35577c") if state == "normal" else Design.GOLD)
			style.shadow_size = 0
			style.content_margin_left = 4
			style.content_margin_right = 4
			style.content_margin_top = 48
			style.content_margin_bottom = 5
			choice.add_theme_stylebox_override(state,style)
		var artwork := StickerArt.new()
		artwork.kind = sticker
		artwork.playing = sticker in StickerArt.EMOTIONS and not reduced_motion
		artwork.position = Vector2(5,2)
		artwork.size = Vector2(46,46)
		choice.add_child(artwork)
		choice.pressed.connect(func(): send_sticker(sticker))
		sticker_grid.add_child(choice)

func position_sticker_picker() -> void:
	if not is_instance_valid(sticker_anchor) or not sticker_anchor.is_visible_in_tree():
		sticker_picker.hide()
		return
	var anchor := sticker_anchor.get_global_rect()
	var bounds := get_viewport_rect().grow(-8)
	var width := minf(280,bounds.size.x)
	var below := bounds.end.y-anchor.end.y-8
	var above := anchor.position.y-bounds.position.y-8
	# Prefer below; a short scrollable picker keeps bottom-row icons nearby.
	# Only flip above when there isn't room for the heading and one full row.
	var open_below := below >= 128 or below >= above
	var height := minf(344,below if open_below else above)
	height = maxf(100,height)
	sticker_scroll.custom_minimum_size.y = maxf(32,height-56)
	var at := Vector2(clampf(anchor.position.x,bounds.position.x,bounds.end.x-width),anchor.end.y+8 if open_below else anchor.position.y-height-8)
	at.y = clampf(at.y,bounds.position.y,bounds.end.y-height)
	var rect := Rect2(at,Vector2(width,height))
	if not sticker_picker.is_embedded():
		rect = get_viewport().get_screen_transform()*rect
	sticker_picker.size = Vector2i(rect.size)
	sticker_picker.position = Vector2i(rect.position)

func open_sticker_picker(target_player_id: String) -> void:
	if not online or target_player_id.is_empty() or target_player_id == self_id:
		return
	sticker_target = ""
	sticker_anchor = null
	for card in cards:
		if card.player_id == target_player_id:
			sticker_anchor = card.gift
			break
	for player in game.get("players",[]):
		if str(player.id) == target_player_id:
			sticker_target = target_player_id
			sticker_title.text = "Send to " + str(player.name)
			break
	if sticker_target.is_empty() or not is_instance_valid(sticker_anchor):
		return
	sticker_scroll.scroll_vertical = 0
	position_sticker_picker()
	sticker_picker.popup(Rect2i(sticker_picker.position,sticker_picker.size))

func open_leave_confirmation() -> void:
	if online and not pending and not presenting and not room_code.is_empty():
		leave_dialog.popup_centered()

func return_home() -> void:
	room_code = ""
	game = {}
	latest_version = -1
	turn_deadline_ticks = 0
	pending = false
	presenting = false
	awaiting_move_state = false
	exit_scheduled = false
	board.apply_state({},self_id)
	for dialog in [result,leave_dialog,chat_dialog,menu,sticker_picker]:
		dialog.hide()
	home.show()
	lobby.hide()
	game_view.hide()
	content.get_node("SetupScroll").show()
	brand_label.add_theme_color_override("font_color",Design.INK)
	notice.text = "You left the game. Create or join another room."
	_safe_area()

func finish_departure_match(code: String) -> void:
	await get_tree().create_timer(4.0).timeout
	if room_code == code and game.get("phase") == "finished" and online:
		# Detach on the server too, so creating another room works immediately.
		if network.send_intent({"type":"LEAVE_GAME"}):
			pending = true
			refresh_controls()

func open_table_chat() -> void:
	for card in cards:
		if card.player_id == self_id:
			card.chat.unread = false
	chat_dialog.popup_centered()

func send_sticker(sticker: String) -> void:
	if sticker_target.is_empty() or not online:
		sticker_picker.hide()
		return
	if not network.send_intent({"type":"SEND_STICKER", "targetPlayerId":sticker_target, "sticker":sticker}):
		notice.text = "Could not send sticker. Connection lost."
		return
	notice.text = "Sending " + sticker.to_lower() + "…"
	sticker_picker.hide()
	sticker_target = ""

func show_sticker(event: Dictionary) -> void:
	var recipient: Control = null
	var sender: Control = null
	var target_id := str(event.get("targetPlayerId",self_id))
	for card in cards:
		if card.player_id == target_id:
			recipient = card
		if card.player_id == str(event.get("fromPlayerId","")):
			sender = card
	if not recipient:
		return
	# Replace the previous effect for this recipient to avoid overlapping meshes.
	for previous in sticker_layer.get_children():
		if previous.get_meta("target_player_id","") == target_id:
			previous.queue_free()
	var effect := StickerEffect.new()
	effect.kind = str(event.get("sticker","PARTY"))
	effect.recipient = recipient
	effect.sender = sender
	effect.reduced_motion = reduced_motion
	effect.set_meta("target_player_id",target_id)
	effect.contact.connect(func(kind: String):
		var cue := "chat" if kind in ["ANGRY","SAD","CRY","SURPRISED","THINKING"] else "sticker_hit" if kind in ["HAMMER","BOOM","PUNCH","TOMATO","EGG"] else "sticker_cheer"
		feedback.cue(cue,target_id == self_id)
	)
	sticker_layer.add_child(effect)
	if str(event.get("fromPlayerId","")) == self_id:
		notice.text = "Sticker delivered: " + effect.kind.to_lower()

func request_room(join: bool) -> void:
	sync_web_form()
	var player_name := name_input.text.strip_edges()
	if player_name.is_empty():
		player_name = "Guest"
	config.set_value("player", "name", player_name)
	config.save("user://preferences.cfg")
	var code := join_input.text.strip_edges().to_upper()
	join_input.text = code
	if join and code.is_empty():
		notice.text = "Enter your friend’s room code first."
		return
	send({"type":"JOIN_ROOM", "code":code, "name":player_name} if join else {"type":"CREATE_ROOM", "name":player_name})

func send(intent: Dictionary) -> void:
	if pending or presenting:
		return
	if not online or not network.send_intent(intent):
		notice.text = "Cannot reach the game server."
		return
	pending = true
	refresh_controls()

func send_chat() -> void:
	var text := chat_input.text.strip_edges()
	if not text.is_empty() and online and not room_code.is_empty():
		if network.send_intent({"type":"CHAT", "text":text}):
			chat_input.clear()

func _receive(event: Dictionary) -> void:
	if str(event.get("type","")) == "STATE":
		var remaining := maxi(0,int(event.get("turnDeadline",0))-int(event.get("serverTime",0)))
		event["deadlineTicks"] = Time.get_ticks_msec()+remaining if remaining > 0 else 0
	# Social messages bypass dice/move animation waits, but keep server receipt order.
	if str(event.get("type","")) == "CHAT":
		receive_chat(event)
		return
	if str(event.get("type","")) == "STICKER":
		show_sticker(event)
		return
	# A single ordered presentation queue prevents snapshots overtaking dice/moves.
	events.append(event)
	if not processing_events:
		processing_events = true
		drain_events()

func drain_events() -> void:
	while not events.is_empty():
		var event: Dictionary = events.pop_front()
		await present_event(event)
	processing_events = false

func present_event(event: Dictionary) -> void:
	match str(event.type):
		"CONNECTED":
			if not room_code.is_empty() and not event.get("resumed",false):
				room_code = ""
				game = {}
				latest_version = -1
				content.get_node("SetupScroll").show()
				home.show()
				lobby.hide()
				game_view.hide()
				_safe_area()
				notice.text = "This room is no longer available. Please create or join a room."
			elif event.get("resumed",false):
				notice.text = "Connection restored. Resuming your game…"
			self_id = str(event.playerId)
		"LEFT_ROOM":
			return_home()
			if event.get("reason","") == "inactivity":
				notice.text = "Timer expired with no chances left. You left the game."
		"ERROR":
			pending = false
			notice.text = str(event.message)
		"ROOM_CREATED", "ROOM_JOINED":
			room_code = str(event.roomCode)
			room_label.text = room_code
			pending = false
			home.hide()
			lobby.show()
		"STATE":
			room_code = str(event.get("roomCode",room_code))
			room_label.text = room_code
			var snapshot: Dictionary = event.state
			if int(snapshot.get("version",0)) < latest_version:
				return
			if event.get("recovered", false):
				# Focus/connection checks must wait behind queued dice and moves.
				# If the move event was missed, recover its per-cell presentation.
				presenting = true
				refresh_controls()
				await board.reconcile_state(snapshot)
				presenting = false
				awaiting_move_state = false
			# Missing pawns dissolve together before applying the new table state.
			presenting = true
			refresh_controls()
			await board.animate_departures(snapshot)
			presenting = false
			latest_version = int(snapshot.get("version",0))
			game = snapshot
			turn_deadline_ticks = int(event.get("deadlineTicks",0))
			turn_duration_ms = int(event.get("turnDurationMs",30000))
			pending = false
			show_state()
			# TOKEN_MOVED is followed by this authoritative snapshot. Do not
			# re-enable input against the previous legal-pawn state in between.
			if awaiting_move_state:
				awaiting_move_state = false
				presenting = false
		"TURN_SKIPPED":
			if int(event.get("version",-1)) <= latest_version:
				return
			pending = false
			presenting = false
			awaiting_move_state = false
			notice.text = "No clash-free dice value. Turn passed."
		"DICE_ROLLED":
			presenting = true
			pending = false
			refresh_controls()
			board.highlight_player(str(event.color),int(event.value))
			notice.text = "Rolling…"
			var roller = null
			for card in cards:
				if card.player_id == str(event.playerId):
					roller = card
			if roller:
				roller.dice.reduced_motion = reduced_motion
				await roller.dice.animate_roll(int(event.value))
			else:
				await get_tree().create_timer(1.2).timeout
			notice.text = "Rolled a %d" % int(event.value)
			if roller:
				roller.status_label.text = notice.text
			notice.text += " · " + ("No legal move; next player." if event.get("skipped",false) else "Moving the only legal pawn." if event.get("automatic",false) else "Choose a highlighted pawn.")
			presenting = false
		"TOKEN_MOVED":
			var move_version := int(event.get("version", -1))
			if move_version >= 0 and move_version <= latest_version:
				return
			presenting = true
			awaiting_move_state = true
			refresh_controls()
			await board.animate_move(event)
			pending = false
			notice.text = "Move complete."
		"CHAT":
			receive_chat(event)
	refresh_controls()

func receive_chat(event: Dictionary) -> void:
	var sender := str(event.get("name","Guest"))
	chat_log.append_text(sender+": "+str(event.text)+"\n")
	chat_bubbles.reduced_motion = reduced_motion
	for card in cards:
		if card.player_id == str(event.get("playerId","")):
			chat_bubbles.show_message(card,sender,str(event.text))
			break
	if str(event.get("playerId","")) != self_id:
		feedback.cue("chat")
		if not chat_dialog.visible:
			for card in cards:
				if card.player_id == self_id:
					card.chat.unread = true

func show_state() -> void:
	var is_lobby: bool = game.get("phase") == "lobby"
	home.hide()
	lobby.visible = is_lobby
	content.get_node("SetupScroll").visible = is_lobby
	game_view.visible = not is_lobby
	_safe_area()
	game_background.visible = true
	brand_label.add_theme_color_override("font_color",Color("f3f7ff") if not is_lobby else Design.INK)
	notice.add_theme_color_override("font_color",Color("c2d6ef") if not is_lobby else Design.MUTED)
	var players: Array = game.get("players",[])
	var player_lines := PackedStringArray()
	for seat in range(4):
		var player: Dictionary = players[seat] if seat < players.size() else {}
		player_lines.append("%s · %s%s" % [str(player.get("name","Waiting for friend")), Design.COLOR_NAMES.get(player.get("color",""),"Empty seat"), " · Host" if seat == 0 else ""])
	lobby_players.text = "\n\n".join(player_lines)
	board.apply_state(game,self_id)
	if game.get("phase") == "finished":
		var order: Array = game.get("finishOrder",[game.get("winner","")])
		var lines := PackedStringArray()
		for rank in range(order.size()):
			for player in players:
				if player.id == order[rank]:
					var home_count := 0
					for token in game.get("tokens",[]):
						if token.color == player.color and int(token.position) >= BoardMath.HOME:
							home_count += 1
					lines.append("%s  %s · %d/4 home" % [["1st","2nd","3rd","4th"][rank],str(player.name),home_count])
		result_stats.text = "\n\n".join(lines)
		var last_player: bool = players.size() == 1 and not game.get("departedPlayers",[]).is_empty()
		restart_button.visible = not last_player and not players.is_empty() and players[0].id == self_id
		if last_player:
			result_stats.text = str(players[0].name) + " wins!\n\nReturning to home…"
			if not exit_scheduled:
				exit_scheduled = true
				finish_departure_match(room_code)
		if not result.visible:
			chat_dialog.hide()
			menu.hide()
			result.popup_centered()
	else:
		result.hide()

func refresh_controls() -> void:
	if not is_instance_valid(status):
		return
	status.text = connection_detail + (" · Room " + room_code if not room_code.is_empty() else "")
	status.add_theme_color_override("font_color", Color("c2d6ef") if game_view.visible else Design.MUTED if online else Design.FOREST)
	create_button.disabled = not online or pending
	join_button.disabled = not online or pending
	var players: Array = game.get("players",[])
	restart_button.disabled = not online or pending or presenting or players.size() < 2
	start_button.visible = not players.is_empty() and players[0].id == self_id
	start_button.disabled = not online or pending or players.size() < 2
	# Server deadlines include animation time. Reduced-motion clients must
	# also wait until that lead-in ends before enabling the next input.
	var phase_ready := turn_deadline_ticks == 0 or Time.get_ticks_msec() >= turn_deadline_ticks-turn_duration_ms
	var can_act := online and not pending and not presenting and phase_ready and (turn_deadline_ticks == 0 or Time.get_ticks_msec() < turn_deadline_ticks)
	board.enabled = can_act
	for pawn in board.pawns.values():
		pawn.selection_enabled = can_act
	for seat in range(4):
		# Player order controls turns; color controls the matching board corner.
		var player: Dictionary = {}
		for candidate in players:
			if candidate.get("color","") == ["coral","sun","mint","violet"][seat]:
				player = candidate
				break
		if player.is_empty():
			for departed in game.get("departedPlayers",[]):
				if departed.get("color","") == ["coral","sun","mint","violet"][seat]:
					player = departed.duplicate()
					player["departed"] = true
					break
		var rank: int = game.get("finishOrder",[]).find(player.get("id",""))
		var active: bool = rank < 0 and not player.is_empty() and player.id == game.get("currentPlayer") and game.get("phase") in ["rolling","moving"]
		var own: bool = not player.is_empty() and player.id == self_id
		cards[seat].update_player(player, active, active and own and can_act and game.get("phase") == "rolling", own)
		cards[seat].visible = not player.is_empty()
		cards[seat].leave_button.disabled = not online or pending or presenting
		cards[seat].set_lives(int(game.get("timeoutLives",{}).get(player.get("id",""),5)))
		cards[seat].set_rank(rank)
		cards[seat].set_clock(turn_deadline_ticks,turn_duration_ms,active and not presenting,own)
	_safe_area()
