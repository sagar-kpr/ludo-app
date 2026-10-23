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
const ModeCard = preload("res://scripts/mode_card.gd")
const AvatarCatalog = preload("res://scripts/avatar_catalog.gd")
const LoadingSpinner = preload("res://scripts/loading_spinner.gd")
const MenuGlyph = preload("res://scripts/menu_glyph.gd")
var loading_overlay: Control
var loading_label: Label
var room_loading := false
var reconnect_overlay: Control
var reconnect_title: Label
var reconnect_status: Label
var recovering_match := false
var selected_avatar := ""
var avatar_button: Button
var avatar_preview: TextureRect
var avatar_picker: PopupPanel
var avatar_grid: GridContainer
var avatar_scroll: ScrollContainer
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
var dashboard: VBoxContainer
var friends_setup: VBoxContainer
var friends_button: Button
var setup_transition: Tween
var lobby: VBoxContainer
var game_view: VBoxContainer
var status: Label
var status_badge: PanelContainer
var status_dot: Control
var avatar_edit_button: Button
var notice: Label
var name_input: LineEdit
var join_input: LineEdit
var room_label: Label
var lobby_players: Label
var create_button: Button
var computer_button: Button
var join_button: Button
var start_button: Button
var cards: Array = []
var game: Dictionary = {}
var self_id := ""
var server_instance_id := ""
var recovery_lost_dialog: AcceptDialog
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
var result_home_button: Button
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
	var form_covered := (is_instance_valid(loading_overlay) and loading_overlay.visible) or (is_instance_valid(avatar_picker) and avatar_picker.visible)
	for entry in [[name_input,"rally-name","Your player name",18],[join_input,"rally-code","Friend’s room code",9]]:
		var input: LineEdit = entry[0]
		# While a modal is open, draw the engine field behind it while its
		# browser overlay is hidden, so the background form stays complete.
		input.modulate.a = 1.0 if form_covered else 0.0
		var rect := input.get_global_rect()
		fields.append({"id":entry[1],"label":entry[2],"max":entry[3],"value":input.text,"placeholder":input.placeholder_text,"visible":input.is_visible_in_tree() and not form_covered,"opacity":dashboard.modulate.a if input == name_input else friends_setup.modulate.a,"rect":[rect.position.x,rect.position.y,rect.size.x,rect.size.y]})
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
	selected_avatar = str(config.get_value("player","avatar",""))
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
		card.dice.reduced_motion = reduced_motion
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
			if not room_code.is_empty():
				recovering_match = true
				reconnect_title.text = "Checking connection" if detail == "Checking connection…" else "Connection lost"
				for dialog in [menu,chat_dialog,leave_dialog,sticker_picker]:
					dialog.hide()
			cancel_input_previews()
			pending = false
			room_loading = false
			loading_overlay.hide()
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
	if game_view.visible and is_instance_valid(board):
		var width_limit := available.x-8.0
		var mobile_portrait := available.x < 640.0
		board.framing_width = 15.8 if mobile_portrait else board.FRAMING_WIDTH
		for card in cards:
			card.fit_width((width_limit-16.0)*0.5,available.y,mobile_portrait)
		set_game_layout(available.x >= 640.0 and available.x > available.y*1.25)
		if using_landscape:
			var profile_width := 168.0 if available.y < 680.0 else 192.0
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
	var brand := label("RALLY LUDO", 18, Design.INK)
	var brand_font := FontVariation.new()
	brand_font.base_font = ThemeDB.fallback_font
	brand_font.variation_embolden = 0.55
	brand.add_theme_font_override("font",brand_font)
	brand.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	brand_label = brand
	brand.autowrap_mode = TextServer.AUTOWRAP_OFF
	header.add_child(brand)
	var header_space := Control.new()
	header_space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(header_space)
	status_badge = PanelContainer.new()
	status_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(status_badge)
	var badge_row := HBoxContainer.new()
	badge_row.add_theme_constant_override("separation",7)
	status_badge.add_child(badge_row)
	status_dot = MenuGlyph.new()
	status_dot.kind = "dot"
	status_dot.custom_minimum_size = Vector2(10,10)
	status_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge_row.add_child(status_dot)
	status = label("Connecting…", 12, Design.MUTED)
	status.custom_minimum_size.x = 76
	status.autowrap_mode = TextServer.AUTOWRAP_OFF
	status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	badge_row.add_child(status)
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
	dashboard = VBoxContainer.new()
	dashboard.add_theme_constant_override("separation",22)
	home.add_child(dashboard)
	var breathing_room := Control.new()
	breathing_room.custom_minimum_size.y = 5
	dashboard.add_child(breathing_room)
	var greeting := label("YOUR NEXT GREAT GAME",11,Color("8bc8ef"))
	greeting.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dashboard.add_child(greeting)
	var headline := label("Choose your table",30,Design.INK)
	headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dashboard.add_child(headline)
	var intro := label("Bring your friends or take on a Bot.",15,Color("b9cde2"))
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dashboard.add_child(intro)
	var profile := panel(dashboard)
	var profile_style := Design.surface(Color("0b1930"),18,Color("344861"))
	profile_style.content_margin_top = 6
	profile_style.content_margin_bottom = 6
	profile_style.shadow_size = 8
	profile.get_parent().add_theme_stylebox_override("panel",profile_style)
	var identity_row := HBoxContainer.new()
	identity_row.add_theme_constant_override("separation",16)
	profile.add_child(identity_row)
	var avatar_column := VBoxContainer.new()
	avatar_column.add_theme_constant_override("separation",4)
	identity_row.add_child(avatar_column)
	avatar_button = secondary_button("",open_avatar_picker)
	avatar_button.tooltip_text = "Choose avatar"
	avatar_button.custom_minimum_size = Vector2(96,96)
	avatar_column.add_child(avatar_button)
	avatar_preview = TextureRect.new()
	avatar_preview.texture = AvatarCatalog.texture_for(selected_avatar)
	avatar_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	avatar_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	avatar_preview.material = AvatarCatalog.rounded_material()
	avatar_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	avatar_button.add_child(avatar_preview)
	avatar_preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	avatar_preview.offset_left = 5
	avatar_preview.offset_right = -5
	avatar_preview.offset_top = 5
	avatar_preview.offset_bottom = -5
	avatar_edit_button = Button.new()
	avatar_edit_button.tooltip_text = "Change avatar"
	avatar_edit_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	avatar_button.add_child(avatar_edit_button)
	avatar_edit_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	avatar_edit_button.offset_left = -30
	avatar_edit_button.offset_top = -30
	avatar_edit_button.offset_right = 3
	avatar_edit_button.offset_bottom = 3
	for state in ["normal","hover","pressed","focus"]:
		var edit_style := Design.surface(Color("1569ad") if state != "pressed" else Color("104c83"),18,Color("73caff"))
		edit_style.set_border_width_all(1)
		edit_style.shadow_size = 3
		edit_style.content_margin_left = 0
		edit_style.content_margin_right = 0
		edit_style.content_margin_top = 0
		edit_style.content_margin_bottom = 0
		avatar_edit_button.add_theme_stylebox_override(state,edit_style)
	var edit_icon := MenuGlyph.new()
	edit_icon.kind = "edit"
	avatar_edit_button.add_child(edit_icon)
	edit_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	edit_icon.offset_left = 5
	edit_icon.offset_top = 5
	edit_icon.offset_right = -5
	edit_icon.offset_bottom = -5
	avatar_edit_button.pressed.connect(open_avatar_picker)
	var avatar_caption := label("Change avatar",11,Color("a9d5f5"))
	avatar_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	avatar_column.add_child(avatar_caption)
	var identity_fields := VBoxContainer.new()
	identity_fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity_fields.alignment = BoxContainer.ALIGNMENT_CENTER
	identity_fields.add_theme_constant_override("separation",8)
	identity_row.add_child(identity_fields)
	identity_fields.add_child(label("Your player name",14,Design.MUTED))
	name_input = LineEdit.new()
	name_input.placeholder_text = "Guest"
	name_input.max_length = 18
	name_input.text = str(config.get_value("player", "name", ""))
	name_input.custom_minimum_size.y = 52
	name_input.focus_mode = Control.FOCUS_ALL
	name_input.mouse_filter = Control.MOUSE_FILTER_STOP
	name_input.virtual_keyboard_enabled = true
	name_input.focus_entered.connect(func(): scroll.ensure_control_visible(name_input))
	configure_web_field(name_input)
	name_input.add_theme_stylebox_override("normal",Design.surface(Color("15253f"),14,Color("344864")))
	identity_fields.add_child(name_input)
	identity_fields.add_child(label("For Friends and Bot",12,Color("b9cde2")))
	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation",14)
	dashboard.add_child(modes)
	friends_button = ModeCard.new()
	friends_button.name = "FriendsMode"
	friends_button.reduced_motion = reduced_motion
	friends_button.tooltip_text = "Play with Friends · Create or join a private online room"
	friends_button.pressed.connect(open_friends_with_feedback)
	modes.add_child(friends_button)
	computer_button = ModeCard.new()
	computer_button.name = "ComputerMode"
	computer_button.computer = true
	computer_button.reduced_motion = reduced_motion
	computer_button.tooltip_text = "Play with Bot · One-on-one against a Bot. Internet connection required."
	computer_button.pressed.connect(func(): request_room(false,true))
	modes.add_child(computer_button)
	var dashboard_footer := label("One board. Good company. Your next win.",13,Color("99b5d1"))
	dashboard_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dashboard.add_child(dashboard_footer)
	friends_setup = VBoxContainer.new()
	friends_setup.add_theme_constant_override("separation",18)
	friends_setup.hide()
	home.add_child(friends_setup)
	var back := secondary_button("‹  Back to game modes",func(): show_friends_setup(false))
	back.custom_minimum_size.y = 44
	friends_setup.add_child(back)
	friends_setup.add_child(label("Play with Friends",28,Design.INK))
	friends_setup.add_child(label("Create a private table or join with a room code.",15,Design.MUTED))
	home_card = panel(friends_setup)
	home_card.add_theme_constant_override("separation", 22)
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
	friends_setup.add_child(label("Private rooms · 2–4 players · Share your code",12,Design.MUTED))
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
	loading_overlay = Control.new()
	loading_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	loading_overlay.z_index = 100
	add_child(loading_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0.02,0.04,0.08,0.28)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	loading_overlay.add_child(dim)
	var loading_center := CenterContainer.new()
	loading_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	loading_overlay.add_child(loading_center)
	var loading_panel := PanelContainer.new()
	loading_panel.add_theme_stylebox_override("panel",Design.surface(Color(0.07,0.14,0.24,0.94),18,Color("426b91")))
	loading_center.add_child(loading_panel)
	var loading_row := HBoxContainer.new()
	loading_row.add_theme_constant_override("separation",12)
	loading_panel.add_child(loading_row)
	loading_row.add_child(LoadingSpinner.new())
	loading_label = label("Opening…",16)
	loading_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	loading_row.add_child(loading_label)
	loading_overlay.hide()
	build_reconnect_overlay()

func build_reconnect_overlay() -> void:
	reconnect_overlay = Control.new()
	reconnect_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	reconnect_overlay.z_index = 110
	reconnect_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(reconnect_overlay)
	var shade := ColorRect.new()
	shade.color = Color(0.02,0.04,0.08,0.22)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	reconnect_overlay.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_STOP
	reconnect_overlay.add_child(center)
	var surface := PanelContainer.new()
	surface.custom_minimum_size.x = 260
	var style := Design.surface(Color(0.06,0.14,0.24,0.84),16,Color("426b91"))
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	surface.add_theme_stylebox_override("panel",style)
	center.add_child(surface)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",8)
	surface.add_child(column)
	var wifi := MenuGlyph.new()
	wifi.kind = "wifi"
	wifi.ink = Color("8bd7ff")
	wifi.custom_minimum_size = Vector2(32,32)
	wifi.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(wifi)
	reconnect_title = label("Connection lost",18)
	reconnect_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(reconnect_title)
	var progress := HBoxContainer.new()
	progress.alignment = BoxContainer.ALIGNMENT_CENTER
	progress.add_theme_constant_override("separation",8)
	column.add_child(progress)
	progress.add_child(LoadingSpinner.new())
	reconnect_status = label("Reconnecting…",14,Color("a9d5f5"))
	reconnect_status.autowrap_mode = TextServer.AUTOWRAP_OFF
	progress.add_child(reconnect_status)
	var hint := label("Your game will resume when\nthe connection returns.",12,Design.MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(hint)
	reconnect_overlay.hide()

func build_dialogs() -> void:
	recovery_lost_dialog = AcceptDialog.new()
	recovery_lost_dialog.title = "Match connection lost"
	recovery_lost_dialog.min_size = Vector2i(300,160)
	recovery_lost_dialog.get_ok_button().text = "Back to dashboard"
	add_child(recovery_lost_dialog)
	avatar_picker = PopupPanel.new()
	avatar_picker.theme = theme
	var avatar_surface := Design.surface(Color("14263f"),20,Color("426b91"))
	avatar_surface.shadow_size = 0
	avatar_surface.shadow_offset = Vector2.ZERO
	avatar_picker.add_theme_stylebox_override("panel",avatar_surface)
	avatar_picker.min_size = Vector2i(280,240)
	add_child(avatar_picker)
	avatar_picker.popup_hide.connect(func(): sync_web_form.call_deferred())
	var avatar_column := VBoxContainer.new()
	avatar_column.add_theme_constant_override("separation",12)
	avatar_picker.add_child(avatar_column)
	var avatar_heading := HBoxContainer.new()
	avatar_column.add_child(avatar_heading)
	var avatar_title := label("Choose your avatar",20)
	avatar_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	avatar_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	avatar_heading.add_child(avatar_title)
	var avatar_close := secondary_button("Close",func(): avatar_picker.hide())
	avatar_close.custom_minimum_size = Vector2(54,36)
	avatar_heading.add_child(avatar_close)
	var avatar_hint := label("Pick your player portrait.",14,Design.MUTED)
	avatar_hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	avatar_column.add_child(avatar_hint)
	avatar_scroll = ScrollContainer.new()
	avatar_scroll.custom_minimum_size = Vector2(260,210)
	avatar_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	avatar_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	avatar_column.add_child(avatar_scroll)
	avatar_grid = GridContainer.new()
	avatar_grid.columns = 3
	avatar_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	avatar_grid.add_theme_constant_override("h_separation",10)
	avatar_grid.add_theme_constant_override("v_separation",10)
	avatar_scroll.add_child(avatar_grid)
	avatar_column.add_child(secondary_button("Use default avatar",func(): select_avatar("")))
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
		for mode in [friends_button,computer_button]:
			mode.reduced_motion = value
			if value:
				mode.reset_touch()
		if value:
			if setup_transition and setup_transition.is_valid():
				setup_transition.kill()
			dashboard.modulate = Color.WHITE
			friends_setup.modulate = Color.WHITE
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
	result_home_button = secondary_button("Back to home",func(): send({"type":"LEAVE_GAME"}))
	result_home_button.hide()
	results_column.add_child(result_home_button)
	var results_footer := label("Play again · Same room",12,Design.MUTED)
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
	recovering_match = false
	reconnect_overlay.hide()
	cancel_input_previews()
	room_loading = false
	loading_overlay.hide()
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
	show_friends_setup(false)
	lobby.hide()
	game_view.hide()
	content.get_node("SetupScroll").show()
	brand_label.add_theme_color_override("font_color",Design.INK)
	notice.text = "Choose a mode to play again."
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

func open_friends_with_feedback() -> void:
	loading_label.text = "Opening Friends…"
	loading_overlay.show()
	await get_tree().process_frame
	show_friends_setup(true)
	if not reduced_motion and setup_transition and setup_transition.is_valid():
		await setup_transition.finished
	if not room_loading:
		loading_overlay.hide()

func finish_room_loading() -> void:
	await get_tree().process_frame
	room_loading = false
	loading_overlay.hide()

func open_avatar_picker() -> void:
	# Save the latest browser text before hiding its DOM overlay behind the popup.
	sync_web_form()
	avatar_scroll.custom_minimum_size.y = clampf(get_viewport_rect().size.y-210,80,210)
	for child in avatar_grid.get_children():
		avatar_grid.remove_child(child)
		child.queue_free()
	for id in AvatarCatalog.names():
		var choice := button("",func(): select_avatar(id))
		choice.custom_minimum_size = Vector2(76,84)
		choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		choice.icon = AvatarCatalog.texture_for(id)
		choice.expand_icon = true
		choice.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		choice.add_theme_constant_override("icon_max_width",72)
		choice.tooltip_text = id.get_basename().replace("_"," ").capitalize()
		var portrait := TextureRect.new()
		portrait.texture = choice.icon
		choice.icon = null
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.material = AvatarCatalog.rounded_material()
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		choice.add_child(portrait)
		portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		portrait.offset_left = 6
		portrait.offset_top = 6
		portrait.offset_right = -6
		portrait.offset_bottom = -6
		if id == AvatarCatalog.resolve_id(selected_avatar):
			choice.add_theme_stylebox_override("normal",Design.surface(Color("1f466b"),14,Design.GOLD))
		avatar_grid.add_child(choice)
	var picker_size := Vector2i(mini(360,int(get_viewport_rect().size.x)-24),mini(420,int(get_viewport_rect().size.y)-40))
	avatar_picker.popup(Rect2i((Vector2i(get_viewport_rect().size)-picker_size)/2,picker_size))
	avatar_picker.size = picker_size
	avatar_picker.position = (Vector2i(get_viewport_rect().size)-picker_size)/2
	sync_web_form()

func select_avatar(id: String) -> void:
	selected_avatar = id
	config.set_value("player","avatar",id)
	config.save("user://preferences.cfg")
	avatar_preview.texture = AvatarCatalog.texture_for(id)
	avatar_button.tooltip_text = "Choose avatar" if id.is_empty() else "Change avatar"
	avatar_picker.hide()

func show_friends_setup(show_friends: bool) -> void:
	sync_web_form()
	if setup_transition and setup_transition.is_valid():
		setup_transition.kill()
	dashboard.modulate = Color.WHITE
	friends_setup.modulate = Color.WHITE
	dashboard.visible = not show_friends
	friends_setup.visible = show_friends
	if not reduced_motion:
		var target := friends_setup if show_friends else dashboard
		target.modulate.a = 0.25
		setup_transition = create_tween()
		setup_transition.tween_property(target,"modulate:a",1.0,0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	notice.text = ""
	content.get_node("SetupScroll").scroll_vertical = 0
	sync_web_form.call_deferred()

func request_room(join: bool, computer: bool = false) -> void:
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
	if computer:
		send({"type":"CREATE_COMPUTER_GAME", "name":player_name,"avatarId":AvatarCatalog.resolve_id(selected_avatar)})
	else:
		send({"type":"JOIN_ROOM", "code":code, "name":player_name,"avatarId":AvatarCatalog.resolve_id(selected_avatar)} if join else {"type":"CREATE_ROOM", "name":player_name,"avatarId":AvatarCatalog.resolve_id(selected_avatar)})

func send(intent: Dictionary) -> void:
	if pending or presenting:
		return
	if not online or not network.send_intent(intent):
		notice.text = "Cannot reach the game server."
		return
	pending = true
	if intent.get("type","") == "MOVE_TOKEN":
		board.begin_move_preview(str(intent.get("tokenId","")),int(game.get("dice",0)))
	if intent.get("type","") == "ROLL_DICE":
		for card in cards:
			if card.player_id == self_id:
				card.dice.begin_roll_preview()
	if intent.get("type","") in ["CREATE_ROOM","JOIN_ROOM","CREATE_COMPUTER_GAME"]:
		room_loading = true
		loading_label.text = "Starting Bot…" if intent.type == "CREATE_COMPUTER_GAME" else "Opening room…"
		loading_overlay.show()
	refresh_controls()

func cancel_input_previews() -> void:
	board.cancel_move_preview()
	for card in cards:
		card.dice.cancel_roll_preview()

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
			var next_instance := str(event.get("serverInstanceId",""))
			var server_changed := not server_instance_id.is_empty() and not next_instance.is_empty() and next_instance != server_instance_id
			server_instance_id = next_instance
			if not room_code.is_empty() and not event.get("resumed",false):
				push_warning("Match recovery unavailable; server instance changed: %s" % server_changed)
				return_home()
				notice.text = "The connection dropped and this match could not be restored."
				recovery_lost_dialog.dialog_text = "The game server restarted or changed.\nThis match could not be restored.\n\nPlease start a new game." if server_changed else "Your connection was lost and the server\ncould not recover this match.\n\nPlease start a new game."
				recovery_lost_dialog.popup_centered()
			elif event.get("resumed",false):
				notice.text = "Connection restored. Resuming your game…"
			self_id = str(event.playerId)
		"LEFT_ROOM":
			return_home()
			if event.get("reason","") == "inactivity":
				notice.text = "Timer expired with no chances left. You left the game."
		"ERROR":
			cancel_input_previews()
			pending = false
			room_loading = false
			loading_overlay.hide()
			notice.text = str(event.message)
		"ROOM_CREATED", "ROOM_JOINED":
			room_code = str(event.roomCode)
			room_label.text = room_code
			pending = false
			home.hide()
			lobby.show()
		"STATE":
			cancel_input_previews()
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
			if online and event.get("recovered",false):
				recovering_match = false
			show_state()
			if room_loading:
				finish_room_loading()
			# TOKEN_MOVED is followed by this authoritative snapshot. Do not
			# re-enable input against the previous legal-pawn state in between.
			if awaiting_move_state:
				awaiting_move_state = false
				presenting = false
		"TURN_SKIPPED":
			cancel_input_previews()
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
				await get_tree().create_timer(0.6).timeout
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
		result_home_button.visible = players.any(func(player: Dictionary): return bool(player.get("isComputer",false)))
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
	if is_instance_valid(reconnect_overlay):
		reconnect_overlay.visible = recovering_match and not room_code.is_empty()
		reconnect_status.text = "Restoring your game…" if online else "Reconnecting…"
	status.text = "Connected" if online else "Connecting…"
	status.tooltip_text = connection_detail + (" · Room " + room_code if not room_code.is_empty() else "")
	status.add_theme_color_override("font_color",Color("e3f1fb") if online else Color("e1c79a"))
	status_dot.ink = Color("27dc93") if online else Color("f2b953")
	status_dot.queue_redraw()
	var badge_style := Design.surface(Color("082a37") if online else Color("292b36"),18,Color("135e58") if online else Color("64513a"))
	badge_style.shadow_size = 0
	badge_style.content_margin_left = 11
	badge_style.content_margin_right = 11
	badge_style.content_margin_top = 6
	badge_style.content_margin_bottom = 6
	status_badge.add_theme_stylebox_override("panel",badge_style)
	create_button.disabled = not online or pending
	computer_button.set_available(online and not pending)
	friends_button.set_available(not pending)
	join_button.disabled = not online or pending
	var players: Array = game.get("players",[])
	var computer_match := false
	for player in players:
		if player.get("isComputer",false):
			computer_match = true
	restart_button.disabled = not online or pending or presenting or players.size() < 2
	result_home_button.disabled = not online or pending or presenting
	start_button.visible = not players.is_empty() and players[0].id == self_id
	start_button.disabled = not online or pending or players.size() < 2
	# Server deadlines include animation time. Reduced-motion clients must
	# also wait until that lead-in ends before enabling the next input.
	var phase_ready := turn_deadline_ticks == 0 or Time.get_ticks_msec() >= turn_deadline_ticks-turn_duration_ms
	var can_act := online and not recovering_match and not pending and not presenting and phase_ready and (turn_deadline_ticks == 0 or Time.get_ticks_msec() < turn_deadline_ticks)
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
		if computer_match:
			cards[seat].chat.hide()
		cards[seat].visible = not player.is_empty()
		cards[seat].leave_button.disabled = not online or pending or presenting
		cards[seat].set_lives(int(game.get("timeoutLives",{}).get(player.get("id",""),5)))
		cards[seat].set_rank(rank)
		cards[seat].set_clock(turn_deadline_ticks,turn_duration_ms,active and not presenting,own)
	_safe_area()
