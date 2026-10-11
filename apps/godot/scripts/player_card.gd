extends VBoxContainer

signal roll_pressed
signal invite_pressed
signal gift_pressed(target_player_id: String)
signal chat_pressed
signal camera_pressed
const Design = preload("res://scripts/design.gd")
const Dice = preload("res://scripts/dice.gd")
const Avatar = preload("res://scripts/avatar.gd")
const ProfileAction = preload("res://scripts/profile_action.gd")
var panel: PanelContainer
var actions: HBoxContainer
var chat
var camera_button
var name_label: Label
var status_label: Label
var avatar
var roll: Button
var dice
var player_id := ""
var invite: Button
var gift: Button
var turn_deadline_ticks := 0
var turn_duration_ms := 60000
var turn_active := false
var turn_own := false
var clock_accumulator := 0.0

func set_clock(deadline: int, duration: int, active: bool, own: bool) -> void:
	turn_deadline_ticks = deadline
	turn_duration_ms = maxi(1,duration)
	turn_active = active
	turn_own = own
	update_clock()

func _process(delta: float) -> void:
	clock_accumulator += delta
	if clock_accumulator >= 0.05:
		clock_accumulator = 0
		update_clock()

func update_clock() -> void:
	if not avatar:
		return
	var previous_fraction: float = avatar.timer_fraction
	avatar.timer_fraction = -1
	if turn_active and turn_deadline_ticks > 0:
		var remaining := maxi(0,turn_deadline_ticks-Time.get_ticks_msec())
		avatar.timer_fraction = clampf(float(remaining)/turn_duration_ms,0,1)
		var seconds := int(ceil(remaining/1000.0))
		status_label.text = "%d:%02d" % [seconds/60,seconds%60]
	if previous_fraction != avatar.timer_fraction:
		avatar.queue_redraw()

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0,148)
	add_theme_constant_override("separation",5)
	panel = PanelContainer.new()
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",2)
	panel.add_child(column)
	# Name above the media row leaves a genuinely usable camera square rather
	# than squeezing the portrait between the name and the large dice.
	name_label = Label.new()
	name_label.text = "Empty seat"
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_font_size_override("font_size",14)
	name_label.add_theme_color_override("font_color",Design.INK)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation",4)
	column.add_child(heading)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(name_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	column.add_child(row)
	avatar = Avatar.new()
	row.add_child(avatar)
	avatar.custom_minimum_size = Vector2(80,80)
	avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	# The expanding spacer replaces the gap between avatar and dice.
	row.add_theme_constant_override("separation",4)
	status_label = Label.new()
	status_label.custom_minimum_size.x = 50
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status_label.add_theme_font_size_override("font_size",11)
	status_label.add_theme_color_override("font_color",Design.MUTED)
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	heading.add_child(status_label)
	actions = HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_BEGIN
	actions.custom_minimum_size.y = 28
	actions.add_theme_constant_override("separation",6)
	add_child(actions)
	chat = ProfileAction.new()
	chat.kind = "chat"
	chat.tooltip_text = "Open table chat"
	chat.pressed.connect(func(): chat_pressed.emit())
	actions.add_child(chat)
	camera_button = ProfileAction.new()
	camera_button.kind = "camera"
	camera_button.tooltip_text = "Camera and voice settings"
	camera_button.pressed.connect(func(): camera_pressed.emit())
	actions.add_child(camera_button)
	gift = ProfileAction.new()
	gift.kind = "emoji"
	gift.tooltip_text = "Send an emoji or animated sticker"
	gift.pressed.connect(func(): gift_pressed.emit(player_id))
	actions.add_child(gift)
	roll = Button.new()
	roll.custom_minimum_size = Vector2(72,72)
	roll.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	roll.tooltip_text = "Roll your dice"
	roll.pressed.connect(func(): roll_pressed.emit())
	row.add_child(roll)
	dice = Dice.new()
	roll.add_child(dice)
	dice.custom_minimum_size = Vector2(72,72)
	dice.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	roll.hide()
	invite = Button.new()
	invite.text = "+"
	invite.tooltip_text = "Copy this room's invite code"
	invite.custom_minimum_size = Vector2(32,36)
	invite.add_theme_font_size_override("font_size",23)
	var invite_style := Design.game_surface(Color("4175af"))
	invite_style.content_margin_left = 4
	invite_style.content_margin_right = 4
	invite.add_theme_stylebox_override("normal",invite_style)
	invite.pressed.connect(func(): invite_pressed.emit())
	row.add_child(invite)

func update_player(player: Dictionary, active: bool, can_roll: bool, own: bool) -> void:
	player_id = str(player.get("id", ""))
	turn_own = own
	name_label.text = str(player.get("name","Open seat"))
	var accent: Color = Design.COLORS.get(player.get("color",""),Color("789484"))
	avatar.configure(accent,str(player.get("name","")).hash(),not player.is_empty())
	status_label.text = "You" if own else "" if not player.is_empty() else "Waiting"
	status_label.add_theme_color_override("font_color",Color("0064e9") if active else Color("b7cee8") if player.is_empty() else Design.MUTED)
	name_label.add_theme_color_override("font_color",Color.WHITE if player.is_empty() else Design.INK)
	var style := Design.game_surface(Color("4783c2")) if player.is_empty() else Design.surface(Color("f5f6fc"),14,accent)
	style.set_border_width_all(2 if not player.is_empty() else 1)
	if active:
		style.shadow_color = Color(accent.r,accent.g,accent.b,0.55)
		style.shadow_size = 8
		style.shadow_offset = Vector2.ZERO
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	panel.add_theme_stylebox_override("panel",style)
	roll.visible = active
	invite.visible = player.is_empty()
	chat.visible = own and not player.is_empty()
	camera_button.visible = chat.visible
	gift.visible = not player.is_empty() and not own
	gift.disabled = player_id.is_empty() or own
	roll.disabled = not can_roll
	if not player.is_empty():
		roll.add_theme_stylebox_override("normal", Design.surface(Color.WHITE,10,accent))
		roll.add_theme_stylebox_override("disabled", Design.surface(Color.WHITE,10,Design.DIVIDER))
