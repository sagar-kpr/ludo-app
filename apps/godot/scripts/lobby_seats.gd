extends VBoxContainer

const Design = preload("res://scripts/design.gd")
const Avatar = preload("res://scripts/avatar.gd")
const AvatarCatalog = preload("res://scripts/avatar_catalog.gd")

var seats: Array[Dictionary] = []

func _ready() -> void:
	add_theme_constant_override("separation", 18)
	var host_row := HBoxContainer.new()
	host_row.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(host_row)
	_make_seat(host_row, true)
	var guests := HBoxContainer.new()
	guests.alignment = BoxContainer.ALIGNMENT_CENTER
	guests.add_theme_constant_override("separation", 10)
	add_child(guests)
	for index in range(3):
		_make_seat(guests, false)
	resized.connect(_fit_portraits)
	_fit_portraits()

func _make_seat(parent: HBoxContainer, host: bool) -> void:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_theme_constant_override("separation", 6)
	parent.add_child(column)
	var role := _caption("HOST" if host else "OPEN SEAT", 9, Design.MUTED)
	column.add_child(role)
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(card)
	var content := Control.new()
	card.add_child(content)
	var avatar := Avatar.new()
	content.add_child(avatar)
	avatar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var player_name := _caption("Waiting…", 12, Design.INK)
	column.add_child(player_name)
	seats.append({"column":column, "card":card, "avatar":avatar, "role":role, "name":player_name})

func _caption(text: String, font_size: int, color: Color) -> Label:
	var caption := Label.new()
	caption.text = text
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	caption.custom_minimum_size.x = 1
	caption.add_theme_font_size_override("font_size", font_size)
	caption.add_theme_color_override("font_color", color)
	return caption

func _fit_portraits() -> void:
	var card_width := floorf(clampf((size.x - 20.0) / 3.0, 68.0, 144.0))
	for seat in seats:
		seat.column.custom_minimum_size.x = card_width
		seat.card.custom_minimum_size = Vector2.ONE * card_width
		seat.avatar.custom_minimum_size = Vector2.ONE * (card_width - 4.0)

func apply_players(players: Array, self_id: String, palette: Dictionary = {}) -> void:
	for index in range(seats.size()):
		var seat: Dictionary = seats[index]
		var player: Dictionary = players[index] if index < players.size() else {}
		var occupied := not player.is_empty()
		var accent: Color = palette.get(player.get("color", ""), Design.COLORS.get(player.get("color", ""), Color("526984")))
		var style := Design.surface(Color("11233b") if occupied else Color("0d1b2e"), 14, accent.darkened(0.3) if occupied else Color("30435c"))
		style.set_border_width_all(1)
		style.content_margin_left = 2
		style.content_margin_right = 2
		style.content_margin_top = 2
		style.content_margin_bottom = 2
		style.shadow_size = 3
		seat.card.add_theme_stylebox_override("panel", style)
		seat.avatar.configure(accent, str(player.get("name", "")).hash(), occupied)
		seat.avatar.set_portrait(AvatarCatalog.texture_for(str(player.get("avatarId", ""))) if occupied else null)
		seat.name.text = str(player.get("name", "Waiting…"))
		seat.name.tooltip_text = str(player.get("name", "Waiting for a friend"))
		seat.role.text = "HOST · YOU" if index == 0 and str(player.get("id", "")) == self_id else ("HOST" if index == 0 else ("YOU" if occupied and str(player.get("id", "")) == self_id else ("JOINED" if occupied else "OPEN SEAT")))
