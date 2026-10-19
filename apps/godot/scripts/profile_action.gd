extends Button

# Code-drawn icons remain crisp and don't depend on emoji-font support on web.
const Design = preload("res://scripts/design.gd")
var kind := "chat"
var unread := false:
	set(value):
		unread = value
		queue_redraw()

func _ready() -> void:
	custom_minimum_size = Vector2(32,24)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal","hover","pressed","disabled"]:
		var fill := Color("193d70")
		if state == "hover":
			fill = fill.lightened(0.12)
		elif state == "pressed":
			fill = fill.darkened(0.15)
		var style := Design.surface(fill,10,Color("386ba8"))
		style.shadow_size = 0
		style.content_margin_left = 0
		style.content_margin_right = 0
		style.content_margin_top = 0
		style.content_margin_bottom = 0
		add_theme_stylebox_override(state,style)
	var focus := Design.surface(Color(0,0,0,0),10,Color.WHITE)
	focus.shadow_size = 0
	add_theme_stylebox_override("focus",focus)

func _draw() -> void:
	var ink := Color("f4f8ff")
	if disabled:
		ink.a = 0.45
	draw_set_transform(size*0.5,0,Vector2.ONE*0.85)
	match kind:
		"chat":
			draw_polyline(PackedVector2Array([Vector2(-6,-5),Vector2(6,-5),Vector2(6,3),Vector2(-2,3),Vector2(-6,6),Vector2(-6,-5)]),ink,1.5,true)
		"camera":
			draw_rect(Rect2(-7,-4,9,8),ink,false,1.5)
			draw_polyline(PackedVector2Array([Vector2(2,-2),Vector2(7,-4),Vector2(7,4),Vector2(2,2)]),ink,1.5,true)
		"leave":
			draw_polyline(PackedVector2Array([Vector2(-1,-6),Vector2(-7,-6),Vector2(-7,6),Vector2(-1,6)]),ink,1.5,true)
			draw_line(Vector2(-3,0),Vector2(7,0),ink,1.5,true)
			draw_polyline(PackedVector2Array([Vector2(3,-4),Vector2(7,0),Vector2(3,4)]),ink,1.5,true)
		"emoji":
			draw_arc(Vector2.ZERO,6,0,TAU,32,ink,1.5,true)
			draw_circle(Vector2(-2,-2),0.8,ink)
			draw_circle(Vector2(2,-2),0.8,ink)
			draw_arc(Vector2(0,0),3,0.2,PI-0.2,16,ink,1.3,true)
	if unread and kind == "chat":
		draw_circle(Vector2(7,-5),3.5,Color("ff4059"))
	draw_set_transform(Vector2.ZERO)
