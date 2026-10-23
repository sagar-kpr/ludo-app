extends Control

var kind := "friends"
var ink := Color.WHITE

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func soft_box(rect: Rect2, radius: int, color: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	draw_style_box(style,rect)

func _draw() -> void:
	var factor := minf(size.x,size.y)/32.0
	draw_set_transform(size*0.5,0,Vector2.ONE*factor)
	match kind:
		"friends":
			for x in [-9,9]:
				draw_circle(Vector2(x,-6),3.5,Color(ink,0.8))
				soft_box(Rect2(x-4,1,8,9),4,Color(ink,0.8))
			draw_circle(Vector2(0,-6),4.5,ink)
			soft_box(Rect2(-6,1,12,12),5,ink)
		"robot":
			draw_line(Vector2(0,-9),Vector2(0,-14),ink,2,true)
			draw_circle(Vector2(0,-14),2,ink)
			soft_box(Rect2(-11,-9,22,22),6,ink)
			soft_box(Rect2(-14,-3,4,10),2,ink)
			soft_box(Rect2(10,-3,4,10),2,ink)
			soft_box(Rect2(-8,-5,16,11),3,Color("174472"))
			draw_circle(Vector2(-4,0),1.8,ink)
			draw_circle(Vector2(4,0),1.8,ink)
			draw_line(Vector2(-4,9),Vector2(4,9),Color("174472"),2,true)
		"arrow":
			draw_polyline(PackedVector2Array([Vector2(-4,-8),Vector2(4,0),Vector2(-4,8)]),ink,2.4,true)
		"edit":
			draw_colored_polygon(PackedVector2Array([Vector2(-8,5),Vector2(3,-6),Vector2(8,-1),Vector2(-3,10),Vector2(-10,12)]),ink)
			draw_line(Vector2(5,-8),Vector2(10,-3),ink,3,true)
		"dot":
			draw_circle(Vector2.ZERO,13,ink)
		"wifi":
			for radius in [9,16,23]:
				draw_arc(Vector2(0,11),radius,PI+0.65,TAU-0.65,32,ink,2.0,true)
			draw_circle(Vector2(0,10),2.4,ink)
			draw_line(Vector2(-12,-13),Vector2(12,13),Color("ff8192"),2.2,true)
	draw_set_transform(Vector2.ZERO)
