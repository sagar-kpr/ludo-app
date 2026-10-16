extends PanelContainer

var timer_color := Color.WHITE

var timer_fraction := -1.0:
	set(value):
		timer_fraction = value
		queue_redraw()

func _draw() -> void:
	if timer_fraction < 0:
		return
	# Rounded timer path inside the one profile frame.
	var inset := 4.0
	var radius := 10.0
	var points := PackedVector2Array()
	var centers := [Vector2(size.x-inset-radius,inset+radius), Vector2(size.x-inset-radius,size.y-inset-radius), Vector2(inset+radius,size.y-inset-radius), Vector2(inset+radius,inset+radius)]
	for corner in range(4):
		for step in range(13):
			var angle := -PI/2.0 + corner*PI/2.0 + step*PI/24.0
			points.append(centers[corner]+Vector2(cos(angle),sin(angle))*radius)
	points.append(points[0])
	var length := 0.0
	for index in range(points.size()-1):
		length += points[index].distance_to(points[index+1])
	draw_polyline(points,Color(timer_color,0.10),1.0,true)
	var ink := Color(timer_color.lightened(0.12),0.55)
	var remaining := length*clampf(timer_fraction,0,1)
	for index in range(points.size()-1):
		var segment := points[index].distance_to(points[index+1])
		if remaining <= 0:
			break
		draw_line(points[index],points[index].lerp(points[index+1],minf(1,remaining/maxf(segment,0.001))),ink,1.0,true)
		remaining -= segment
