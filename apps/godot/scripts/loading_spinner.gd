extends Control

var angle := 0.0

func _ready() -> void:
	custom_minimum_size = Vector2(24,24)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visibility_changed.connect(func(): set_process(is_visible_in_tree()))
	set_process(is_visible_in_tree())

func _process(delta: float) -> void:
	angle = fmod(angle+delta*TAU,TAU)
	queue_redraw()

func _draw() -> void:
	var center := size*0.5
	draw_arc(center,9,0,TAU,32,Color(0.65,0.85,1,0.18),2,true)
	draw_arc(center,9,angle,angle+TAU*0.70,28,Color("8bd7ff"),2.5,true)
