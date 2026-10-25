extends VBoxContainer

const Design = preload("res://scripts/design.gd")
const Avatar = preload("res://scripts/avatar.gd")
const AvatarCatalog = preload("res://scripts/avatar_catalog.gd")
const Celebration = preload("res://scripts/win_celebration.gd")
const HOME := preload("res://scripts/board_math.gd").HOME
var entrance: Tween

func populate(state: Dictionary) -> void:
	if entrance:
		entrance.kill()
	modulate = Color.WHITE
	for child in get_children():
		remove_child(child)
		child.queue_free()
	add_theme_constant_override("separation", 6)
	var players: Array = state.get("players", [])
	var order: Array = state.get("finishOrder", [])
	for rank in range(order.size()):
		for player in players:
			if str(player.get("id", "")) != str(order[rank]):
				continue
			var tint: Color = Celebration.MEDALS[mini(rank,3)]
			var card := PanelContainer.new()
			var surface := Design.surface(Color("192b42") if rank == 0 else Color("112238"), 12, Color(tint,0.4 if rank == 0 else 0.16))
			surface.shadow_size = 0
			surface.content_margin_left = 8
			surface.content_margin_right = 8
			surface.content_margin_top = 7
			surface.content_margin_bottom = 7
			card.add_theme_stylebox_override("panel", surface)
			add_child(card)
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 9)
			card.add_child(row)
			var place := Label.new()
			place.text = Celebration.PLACES[mini(rank,3)]
			place.custom_minimum_size.x = 30
			place.add_theme_font_size_override("font_size", 17)
			place.add_theme_color_override("font_color", tint)
			row.add_child(place)
			var avatar := Avatar.new()
			row.add_child(avatar)
			avatar.custom_minimum_size = Vector2(40,40)
			avatar.configure(Design.COLORS.get(player.get("color",""),Design.FOREST),str(player.get("name","")).hash(),true)
			avatar.computer = bool(player.get("isComputer",false))
			avatar.set_portrait(null if avatar.computer else AvatarCatalog.texture_for(str(player.get("avatarId",""))))
			var details := VBoxContainer.new()
			details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			details.alignment = BoxContainer.ALIGNMENT_CENTER
			details.add_theme_constant_override("separation", 2)
			row.add_child(details)
			var player_name := Label.new()
			player_name.text = "Bot" if avatar.computer else str(player.get("name","Player"))
			player_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			player_name.add_theme_font_size_override("font_size",14)
			details.add_child(player_name)
			var home_count := 0
			for token in state.get("tokens",[]):
				if token.get("color") == player.get("color") and int(token.get("position",0)) >= HOME:
					home_count += 1
			var info := Label.new()
			info.text = ("Winner · " if rank == 0 else "") + "%d/4 pawns home" % home_count
			info.add_theme_font_size_override("font_size",11)
			info.add_theme_color_override("font_color",tint if rank == 0 else Design.MUTED)
			details.add_child(info)

func reveal(reduced_motion: bool) -> void:
	if entrance:
		entrance.kill()
	modulate.a = 1.0 if reduced_motion else 0.0
	if reduced_motion:
		return
	entrance = create_tween()
	entrance.tween_property(self,"modulate:a",1.0,0.28).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	for index in range(get_child_count()):
		var row := get_child(index) as Control
		row.modulate.a = 0.0
		entrance.parallel().tween_property(row,"modulate:a",1.0,0.25).set_delay(index*0.07)
