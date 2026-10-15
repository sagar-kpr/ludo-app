extends Control

const TOTAL := 5
var accent := Color.WHITE:
	set(value):
		accent = value
		queue_redraw()
var remaining := TOTAL:
	set(value):
		remaining = clampi(value,0,TOTAL)
		tooltip_text = "No chances left. Play manually; the next missed timer means leaving." if remaining == 0 else "%d of 5 timeout chances left. A missed roll or move uses one." % remaining
		queue_redraw()

func _ready() -> void:
	custom_minimum_size = Vector2(0,8)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_PASS
	resized.connect(queue_redraw)
	remaining = remaining

func _draw() -> void:
	var radius := minf(3.5,size.y*0.4)
	for index in range(TOTAL):
		var center := Vector2(lerpf(radius,size.x-radius,float(index)/(TOTAL-1)),size.y*0.5)
		if index < remaining:
			draw_circle(center,radius,accent)
		else:
			draw_arc(center,radius-0.5,0,TAU,24,Color(accent,0.25),1.0,true)
