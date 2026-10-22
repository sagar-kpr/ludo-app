extends Button

const Design = preload("res://scripts/design.gd")
var computer := false
var reduced_motion := false
var touch_tween: Tween

func _ready() -> void:
	custom_minimum_size = Vector2(0,252)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var accent := Color("76c9ff") if computer else Color("ffc370")
	var base := Color("16385a") if computer else Color("493529")
	for state in ["normal","hover","pressed","disabled"]:
		var fill := base.lightened(0.10) if state == "hover" else base.darkened(0.12) if state == "pressed" else base
		var style := Design.surface(fill,22,accent.darkened(0.48))
		style.shadow_size = 12
		style.shadow_offset = Vector2(0,5)
		add_theme_stylebox_override(state,style)
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
	for item in [["1 VS 1" if computer else "2–4 PLAYERS",11,accent],["Play with A.I" if computer else "Play with Friends",18,Color.WHITE],["Your A.I opponent" if computer else "Online · Private rooms",12,Color("c7d6e6")]]:
		var caption := Label.new()
		caption.text = item[0]
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		caption.add_theme_font_size_override("font_size",item[1])
		caption.add_theme_color_override("font_color",item[2])
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(caption)
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
	else:
		pawn(Vector2(-39,4),Color("ff5d68"))
		pawn(Vector2(39,4),Color("36c48a"))
		draw_set_transform(Vector2(size.x/2,63),-0.14,Vector2.ONE*scale_factor)
		rounded(Rect2(-24,-27,48,48),Color("a8c1d3"),10)
		rounded(Rect2(-24,-31,48,46),Color("f4f8fb"),10,Color("ccdfeb"))
		for point in [Vector2(-12,-19),Vector2(12,-19),Vector2(0,-8),Vector2(-12,3),Vector2(12,3)]:
			draw_circle(point,3.7,Color("28425d"))
	draw_set_transform(Vector2.ZERO)
