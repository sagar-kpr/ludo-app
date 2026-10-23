extends Control

const AvatarCatalog = preload("res://scripts/avatar_catalog.gd")

var accent := Color("4e7fc4")
var variant := 0
var occupied := false
var computer := false
var timer_fraction := -1.0
var reaction := ""
var reaction_time := 0.0
var portrait: TextureRect

# A photo or camera-frame texture can replace the illustrated avatar in-place.
func set_portrait(texture: Texture2D) -> void:
	if portrait.texture == texture:
		return
	portrait.texture = texture
	portrait.visible = texture != null
	queue_redraw()

func react(action: String) -> void:
	reaction = action
	reaction_time = 0.0

func _process(delta: float) -> void:
	if not reaction.is_empty():
		reaction_time += delta
		if reaction_time >= 0.45:
			reaction = ""
		queue_redraw()

func _ready() -> void:
	custom_minimum_size = Vector2(48,48)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	portrait = TextureRect.new()
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.material = AvatarCatalog.rounded_material()
	add_child(portrait)
	portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	portrait.offset_left = 3
	portrait.offset_top = 3
	portrait.offset_right = -3
	portrait.offset_bottom = -3
	portrait.hide()

func configure(color: Color, seed_value: int, joined: bool) -> void:
	accent = color
	variant = absi(seed_value)%3
	occupied = joined
	queue_redraw()

func _draw() -> void:
	var background := StyleBoxFlat.new()
	background.bg_color = Color("162c46").lerp(accent,0.20)
	background.set_corner_radius_all(12)
	background.set_border_width_all(0)
	background.shadow_color = Color(0,0,0,0.25)
	background.shadow_size = 3
	background.shadow_offset = Vector2(0,2)
	draw_style_box(background,Rect2(Vector2.ZERO,size))
	if portrait != null and portrait.texture != null:
		return
	var scale_factor := minf(size.x,size.y)/48.0
	var offset := Vector2.ZERO
	var tilt := 0.0
	if reaction == "hit":
		offset.x = sin(reaction_time*65)*4*(1-reaction_time/0.45)
		tilt = sin(reaction_time*35)*0.18
	elif reaction == "happy":
		offset.y = -sin(reaction_time/0.45*PI)*4
	draw_set_transform(Vector2(size.x/2,size.y/2)+offset,tilt,Vector2.ONE*scale_factor)
	if computer:
		draw_line(Vector2(0,-12),Vector2(0,-19),Color("bed8eb"),2,true)
		draw_circle(Vector2(0,-19),2.5,Color("ffc370"))
		var face := StyleBoxFlat.new()
		face.bg_color = Color("dbeaf5")
		face.set_corner_radius_all(7)
		draw_style_box(face,Rect2(-16,-13,32,31))
		face.bg_color = Color("153350")
		face.set_corner_radius_all(5)
		draw_style_box(face,Rect2(-12,-9,24,16))
		draw_circle(Vector2(-6,-1),2.4,Color("75dbff"))
		draw_circle(Vector2(6,-1),2.4,Color("75dbff"))
		draw_line(Vector2(-5,12),Vector2(5,12),Color("567891"),2,true)
	elif not occupied:
		draw_circle(Vector2(0,-5),7,accent.lightened(0.3))
		draw_circle(Vector2(0,17),13,accent.lightened(0.3))
	else:
		var skin: Color = [Color("f2bf9e"),Color("c68c68"),Color("e0ad85")][variant]
		var hair: Color = [Color("332838"),Color("282433"),Color("613b2a")][variant]
		draw_circle(Vector2(0,16),16,accent.lightened(0.25))
		draw_rect(Rect2(-5,4,10,9),skin.darkened(0.15))
		draw_circle(Vector2(0,-5),13,hair)
		draw_circle(Vector2(-10,-3),3,skin)
		draw_circle(Vector2(10,-3),3,skin)
		draw_circle(Vector2(0,-3),10,skin)
		draw_colored_polygon(PackedVector2Array([Vector2(-11,-7),Vector2(-8,-16),Vector2(1,-18),Vector2(12,-12),Vector2(8,-5),Vector2(4,-11),Vector2(-4,-7)]),hair)
		draw_circle(Vector2(-4,-3),1.3,Color("282433"))
		draw_circle(Vector2(4,-3),1.3,Color("282433"))
		draw_arc(Vector2(0,0),4,0.25,PI-0.25,10,Color("a5584d"),1.2,true)
	draw_set_transform(Vector2.ZERO)

func _draw_frame() -> void:
	var bounds := Rect2(Vector2(1.5,1.5),size-Vector2(3,3))
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color.TRANSPARENT
	frame.border_color = accent.lightened(0.45)
	frame.set_border_width_all(2)
	frame.set_corner_radius_all(12)
	draw_style_box(frame,bounds)
	if timer_fraction >= 0:
		var start := Vector2(size.x*0.5,bounds.position.y)
		var points := PackedVector2Array([start,Vector2(bounds.end.x,bounds.position.y),bounds.end,Vector2(bounds.position.x,bounds.end.y),bounds.position,start])
		draw_polyline(points,Color(1,0.82,0.30,0.20),2.0,true)
		var remaining := 2.0*(bounds.size.x+bounds.size.y)*clampf(timer_fraction,0,1)
		for i in range(points.size()-1):
			var length := points[i].distance_to(points[i+1])
			if remaining <= 0:
				break
			draw_line(points[i],points[i].lerp(points[i+1],minf(1,remaining/length)),Color("ffd34d"),2.0,true)
			remaining -= length
