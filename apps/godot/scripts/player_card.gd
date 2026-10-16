extends VBoxContainer

signal roll_pressed
signal invite_pressed
signal gift_pressed(target_player_id: String)
signal chat_pressed
signal leave_pressed
signal camera_pressed
const Design = preload("res://scripts/design.gd")
const Dice = preload("res://scripts/dice.gd")
const Avatar = preload("res://scripts/avatar.gd")
const ProfileAction = preload("res://scripts/profile_action.gd")
const TimeoutLives = preload("res://scripts/timeout_lives.gd")
const ProfileFrame = preload("res://scripts/profile_frame.gd")
var panel
var actions: HBoxContainer
var chat
var leave_button
var departed := false
var camera_button
var name_label: Label
var status_label: Label
var avatar
var lives
var roll: Button
var dice
var player_id := ""
var invite: Button
var gift: Button
var turn_deadline_ticks := 0
var turn_duration_ms := 30000
var turn_active := false
var turn_own := false
var finish_rank := -1
var clock_accumulator := 0.0
var touch_tween: Tween
var media_row: HBoxContainer
var dice_slot: HBoxContainer

func animate_dice_touch(pressed: bool) -> void:
	if touch_tween:
		touch_tween.kill()
	if dice.reduced_motion:
		roll.scale = Vector2.ONE
		return
	touch_tween = create_tween()
	touch_tween.tween_property(roll,"scale",Vector2.ONE*0.95 if pressed else Vector2.ONE,0.09 if pressed else 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

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
	avatar.timer_fraction = -1
	panel.timer_fraction = -1
	if departed:
		status_label.text = "Left game"
		return
	if finish_rank >= 0:
		status_label.text = ["Winner · 1st", "2nd", "3rd", "4th"][mini(finish_rank, 3)]
		status_label.add_theme_color_override("font_color", Color("f9d342"))
		return
	if turn_active and turn_deadline_ticks > 0:
		# Deadlines include the animation lock before this phase begins.
		# Never show that lead-in as extra selection time (for example 0:31).
		var remaining := clampi(turn_deadline_ticks-Time.get_ticks_msec(),0,turn_duration_ms)
		panel.timer_fraction = clampf(float(remaining)/turn_duration_ms,0,1)
		var seconds := int(ceil(remaining/1000.0))
		status_label.text = "%d:%02d" % [seconds/60,seconds%60]

func set_rank(rank: int) -> void:
	finish_rank = rank
	status_label.custom_minimum_size.x = 66 if departed else 76 if rank == 0 else 50
	if rank >= 0:
		turn_active = false
		roll.hide()
		roll.disabled = true
	update_clock()

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	custom_minimum_size = Vector2(180,112)
	add_theme_constant_override("separation",4)
	panel = ProfileFrame.new()
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",5)
	panel.add_child(column)
	# Name above the media row leaves a genuinely usable camera square rather
	# than squeezing the portrait between the name and the large dice.
	name_label = Label.new()
	name_label.text = "Empty seat"
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_font_size_override("font_size",14)
	name_label.add_theme_color_override("font_color",Design.INK)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation",8)
	column.add_child(heading)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(name_label)
	media_row = HBoxContainer.new()
	var row := media_row
	row.custom_minimum_size.y = 72
	row.add_theme_constant_override("separation", 14)
	column.add_child(row)
	var portrait_column := VBoxContainer.new()
	portrait_column.add_theme_constant_override("separation",6)
	portrait_column.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	row.add_child(portrait_column)
	avatar = Avatar.new()
	portrait_column.add_child(avatar)
	avatar.custom_minimum_size = Vector2(72,72)
	avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lives = TimeoutLives.new()
	portrait_column.add_child(lives)
	status_label = Label.new()
	status_label.custom_minimum_size.x = 50
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status_label.add_theme_font_size_override("font_size",12)
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
	leave_button = ProfileAction.new()
	leave_button.kind = "leave"
	leave_button.tooltip_text = "Leave game"
	leave_button.pressed.connect(func(): leave_pressed.emit())
	actions.add_child(leave_button)
	gift = ProfileAction.new()
	gift.kind = "emoji"
	gift.tooltip_text = "Send an emoji or animated sticker"
	gift.pressed.connect(func(): gift_pressed.emit(player_id))
	actions.add_child(gift)
	roll = Button.new()
	roll.custom_minimum_size = Vector2(56,56)
	roll.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	roll.tooltip_text = "Roll your dice"
	roll.pressed.connect(func(): roll_pressed.emit())
	roll.resized.connect(func(): roll.pivot_offset = roll.size*0.5)
	roll.button_down.connect(func(): animate_dice_touch(true))
	roll.button_up.connect(func(): animate_dice_touch(false))
	# Preserve the dice space even when another player's dice is visible.
	dice_slot = HBoxContainer.new()
	dice_slot.alignment = BoxContainer.ALIGNMENT_END
	dice_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dice_slot.custom_minimum_size = Vector2(56,72)
	dice_slot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(dice_slot)
	dice_slot.add_child(roll)
	dice = Dice.new()
	roll.add_child(dice)
	dice.custom_minimum_size = Vector2(56,56)
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

func fit_width(available_width: float) -> void:
	custom_minimum_size.x = minf(180.0,available_width)
	var compact := available_width < 164.0
	var portrait_size := 64.0 if compact else 72.0
	var dice_size := 48.0 if compact else 56.0
	avatar.custom_minimum_size = Vector2.ONE*portrait_size
	roll.custom_minimum_size = Vector2.ONE*dice_size
	dice.custom_minimum_size = Vector2.ONE*dice_size
	dice_slot.custom_minimum_size = Vector2(dice_size,portrait_size)
	media_row.custom_minimum_size.y = portrait_size
	media_row.add_theme_constant_override("separation",12 if compact else 14)

func update_player(player: Dictionary, active: bool, can_roll: bool, own: bool) -> void:
	departed = bool(player.get("departed",false))
	player_id = str(player.get("id", ""))
	turn_own = own
	name_label.text = str(player.get("name","Open seat"))
	var accent: Color = Design.COLORS.get(player.get("color",""),Color("789484"))
	avatar.configure(accent,str(player.get("name","")).hash(),not player.is_empty())
	panel.timer_color = accent
	lives.accent = accent
	lives.visible = not player.is_empty()
	var style := Design.surface(Color("14263f"),16)
	style.set_border_width_all(1)
	style.border_color = Color(accent,0.20) if active and not departed else Color("2a4059")
	style.shadow_color = Color(accent,0.08) if active and not departed else Color(0.015,0.025,0.06,0.25)
	style.shadow_size = 5 if active and not departed else 3
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 13
	panel.add_theme_stylebox_override("panel",style)
	status_label.text = "You" if own else "" if not player.is_empty() else "Waiting"
	status_label.add_theme_color_override("font_color",accent.lightened(0.35) if active else Color("b7cee8"))
	name_label.add_theme_color_override("font_color",Color.WHITE if player.is_empty() else Design.INK)
	roll.visible = active and not departed
	invite.visible = player.is_empty()
	chat.visible = own and not player.is_empty() and not departed
	camera_button.visible = chat.visible
	leave_button.visible = chat.visible
	gift.visible = not player.is_empty() and not own and not departed
	gift.disabled = player_id.is_empty() or own
	roll.disabled = not can_roll
	if not player.is_empty():
		for state in ["normal", "disabled", "hover", "pressed"]:
			roll.add_theme_stylebox_override(state, StyleBoxEmpty.new())

func set_lives(remaining: int) -> void:
	lives.remaining = 0 if departed else remaining
