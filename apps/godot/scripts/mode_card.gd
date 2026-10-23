extends Button

const Design = preload("res://scripts/design.gd")
const MenuGlyph = preload("res://scripts/menu_glyph.gd")
const SurfaceShader = preload("res://resources/menu_surface.gdshader")
var computer := false
var reduced_motion := false
var touch_tween: Tween
var play_now: Button

func add_surface(target: Control, accent: Color, top: Color, bottom: Color, radius: float, border: float) -> void:
	var art := ColorRect.new()
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.show_behind_parent = true
	var material := ShaderMaterial.new()
	material.shader = SurfaceShader
	material.set_shader_parameter("accent",accent)
	material.set_shader_parameter("top_color",top)
	material.set_shader_parameter("bottom_color",bottom)
	material.set_shader_parameter("radius",radius)
	material.set_shader_parameter("border_width",border)
	art.material = material
	target.add_child(art)
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	target.resized.connect(func(): material.set_shader_parameter("surface_size",target.size))

func set_available(available: bool) -> void:
	disabled = not available
	if is_instance_valid(play_now):
		play_now.disabled = disabled

func _ready() -> void:
	custom_minimum_size = Vector2(0,268)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var accent := Color("339eff") if computer else Color("ff4c6b")
	for state in ["normal","hover","pressed","disabled"]:
		var fill := Color(1,1,1,0.035) if state == "hover" else Color(0,0,0,0.10) if state == "pressed" else Color.TRANSPARENT
		var style := Design.surface(fill,22,Color.TRANSPARENT)
		style.shadow_size = 12
		style.shadow_offset = Vector2(0,5)
		add_theme_stylebox_override(state,style)
	add_surface(self,accent,Color("102d4e"),Color("09182e"),22,1.2)
	var focus := Design.surface(Color.TRANSPARENT,22,accent)
	focus.set_border_width_all(2)
	add_theme_stylebox_override("focus",focus)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 10
	column.offset_right = -10
	column.offset_top = 132
	column.offset_bottom = -18
	column.add_theme_constant_override("separation",7)
	add_child(column)
	for item in [["1 VS 1" if computer else "2–4 PLAYERS",11,Color("7bd7ff") if computer else Color("ff7487")],["Play with Bot" if computer else "Play with Friends",18,Color.WHITE],["Your Bot opponent" if computer else "Online · Private rooms",12,Color("b6cbe2")]]:
		var caption := Label.new()
		caption.text = item[0]
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		caption.add_theme_font_size_override("font_size",item[1])
		caption.add_theme_color_override("font_color",item[2])
		if item[1] == 18:
			var bold := FontVariation.new()
			bold.base_font = ThemeDB.fallback_font
			bold.variation_embolden = 0.65
			caption.add_theme_font_override("font",bold)
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(caption)
	play_now = Button.new()
	play_now.text = ""
	play_now.tooltip_text = "Play with Bot" if computer else "Play with Friends"
	play_now.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_child(play_now)
	play_now.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	play_now.offset_left = 14
	play_now.offset_right = -14
	play_now.offset_top = -56
	play_now.offset_bottom = -12
	for state in ["normal","hover","pressed","disabled"]:
		var fill := Color(1,1,1,0.06) if state == "hover" else Color(0,0,0,0.10) if state == "pressed" else Color.TRANSPARENT
		var style := Design.surface(fill,16,Color.TRANSPARENT)
		style.shadow_size = 0
		play_now.add_theme_stylebox_override(state,style)
	add_surface(play_now,accent,Color("193f70") if computer else Color("502739"),Color("0d2c57") if computer else Color("2b1d32"),16,0.8)
	var action_row := HBoxContainer.new()
	action_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	action_row.alignment = BoxContainer.ALIGNMENT_CENTER
	action_row.add_theme_constant_override("separation",9)
	play_now.add_child(action_row)
	action_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	action_row.offset_left = 10
	action_row.offset_right = -10
	var action_icon := MenuGlyph.new()
	action_icon.kind = "robot" if computer else "friends"
	action_icon.ink = Color("a1dfff") if computer else Color("f6c3d4")
	action_icon.custom_minimum_size = Vector2(23,23)
	action_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	action_row.add_child(action_icon)
	var action_text := Label.new()
	action_text.text = "Play Now"
	action_text.add_theme_font_size_override("font_size",15)
	action_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	action_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	action_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	action_row.add_child(action_text)
	var arrow := MenuGlyph.new()
	arrow.kind = "arrow"
	arrow.custom_minimum_size = Vector2(14,18)
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	action_row.add_child(arrow)
	var fit_captions := func():
		var narrow := size.x < 160
		column.offset_top = 118 if narrow else 132
		column.add_theme_constant_override("separation",4 if narrow else 7)
		column.get_child(0).add_theme_font_size_override("font_size",10 if narrow else 11)
		column.get_child(1).add_theme_font_size_override("font_size",14 if narrow else 18)
		column.get_child(2).add_theme_font_size_override("font_size",10 if narrow else 12)
		action_row.offset_left = 8 if narrow else 10
		action_row.offset_right = -8 if narrow else -10
		action_row.add_theme_constant_override("separation",5 if narrow else 9)
		action_icon.custom_minimum_size = Vector2(16,18) if narrow else Vector2(23,23)
		arrow.custom_minimum_size = Vector2(10,16) if narrow else Vector2(14,18)
		action_text.add_theme_font_size_override("font_size",12 if narrow else 15)
	resized.connect(fit_captions)
	fit_captions.call_deferred()
	play_now.pressed.connect(func():
		if not disabled:
			pressed.emit()
	)
	play_now.button_down.connect(func(): animate_touch(true))
	play_now.button_up.connect(func(): animate_touch(false))
	resized.connect(queue_redraw)
	resized.connect(func(): pivot_offset = size*0.5)
	button_down.connect(func(): animate_touch(true))
	button_up.connect(func(): animate_touch(false))
	visibility_changed.connect(func():
		if not is_visible_in_tree():
			reset_touch()
	)

func reset_touch() -> void:
	if touch_tween and touch_tween.is_valid():
		touch_tween.kill()
	scale = Vector2.ONE

func animate_touch(pressed: bool) -> void:
	if touch_tween and touch_tween.is_valid():
		touch_tween.kill()
	if reduced_motion:
		scale = Vector2.ONE
		return
	touch_tween = create_tween()
	if pressed:
		touch_tween.tween_property(self,"scale",Vector2.ONE*0.965,0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	else:
		touch_tween.tween_property(self,"scale",Vector2.ONE,0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func rounded(rect: Rect2, color: Color, radius: int, outline: Color = Color.TRANSPARENT) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.set_border_width_all(1)
	style.border_color = outline
	draw_style_box(style,rect)

func pawn(center: Vector2, color: Color) -> void:
	shadow_oval(center+Vector2(0,28),Vector2(17,6),Color(0,0,0,0.22))
	rounded(Rect2(center+Vector2(-12,0),Vector2(24,27)),color.darkened(0.13),8,color.lightened(0.18))
	draw_circle(center-Vector2(0,5),14,color)
	draw_arc(center-Vector2(0,5),10,3.5,5.1,12,color.lightened(0.40),2,true)

func shadow_oval(center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for index in range(40):
		var angle := TAU*index/40.0
		points.append(center+Vector2(cos(angle)*radius.x,sin(angle)*radius.y))
	draw_colored_polygon(points,color)

func _draw() -> void:
	var scale_factor := minf(1.0,(size.x-24.0)/148.0)
	draw_set_transform(Vector2(size.x/2,71),0,Vector2.ONE*scale_factor)
	draw_circle(Vector2.ZERO,51,Color(0.56,0.75,0.95,0.07))
	if computer:
		shadow_oval(Vector2(0,43),Vector2(37,7),Color(0,0,0,0.20))
		draw_line(Vector2(0,-34),Vector2(0,-48),Color("bed8eb"),4,true)
		draw_circle(Vector2(0,-49),6,Color("ffc370"))
		rounded(Rect2(-43,-9,12,26),Color("69b7e8"),5)
		rounded(Rect2(31,-9,12,26),Color("69b7e8"),5)
		rounded(Rect2(-34,-32,68,67),Color("dbeaf5"),17,Color("8aaabd"))
		rounded(Rect2(-26,-22,52,34),Color("153350"),10)
		draw_circle(Vector2(-12,-5),5,Color("75dbff"))
		draw_circle(Vector2(12,-5),5,Color("75dbff"))
		draw_line(Vector2(-10,23),Vector2(10,23),Color("567891"),3,true)
		for side in [-1,1]:
			draw_line(Vector2(side*48,-16),Vector2(side*55,-22),Color("41b7f3"),2,true)
			draw_line(Vector2(side*49,8),Vector2(side*57,12),Color("41b7f3"),2,true)
	else:
		pawn(Vector2(-39,4),Color("ff5d68"))
		pawn(Vector2(39,4),Color("36c48a"))
		for side in [-1,1]:
			var color := Color("ff5d68") if side == -1 else Color("36c48a")
			draw_line(Vector2(side*48,-25),Vector2(side*53,-32),color,2,true)
			draw_line(Vector2(side*51,-14),Vector2(side*57,-16),color,2,true)
		draw_set_transform(Vector2(size.x/2,63),-0.14,Vector2.ONE*scale_factor)
		rounded(Rect2(-24,-27,48,48),Color("a8c1d3"),10)
		rounded(Rect2(-24,-31,48,46),Color("f4f8fb"),10,Color("ccdfeb"))
		for point in [Vector2(-12,-19),Vector2(12,-19),Vector2(0,-8),Vector2(-12,3),Vector2(12,3)]:
			draw_circle(point,3.7,Color("28425d"))
	draw_set_transform(Vector2.ZERO)
