extends Control

const PLACES := ["1st", "2nd", "3rd", "4th"]
const MEDALS := [Color("ffd166"), Color("d9e7f5"), Color("e9ad83"), Color("99d8ff")]
var rank := -1
var elapsed := 0.0
var reduced_motion := false
var centered := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	set_process(false)
	hide()

func configure(placement: int, reduce_motion: bool) -> void:
	if placement != rank:
		elapsed = 0.0
	rank = placement
	reduced_motion = reduce_motion
	visible = rank >= 0
	set_process(visible and not reduced_motion)
	queue_redraw()

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	elapsed = fmod(elapsed + delta, 60.0)
	queue_redraw()

func _draw() -> void:
	if rank < 0:
		return
	var ink: Color = MEDALS[mini(rank, 3)]
	var center := Vector2(size.x * (0.5 if centered else 0.76), size.y * 0.46)
	var radius := minf(size.y * 0.40, size.x * 0.23)
	var pulse := 1.0 if reduced_motion else 1.0 + sin(elapsed * 2.8) * 0.05
	draw_circle(center, radius * pulse, Color(ink, 0.07))
	for index in range(10):
		var angle := index * TAU / 10.0 + (0.0 if reduced_motion else elapsed * 0.24)
		var direction := Vector2(cos(angle), sin(angle))
		draw_line(center + direction * radius * 0.72, center + direction * radius * 0.91, Color(ink, 0.4), 1.2, true)
	# A large cup in the former dice space keeps the player's avatar visible.
	var unit := radius * pulse / 30.0
	draw_set_transform(center, 0.0, Vector2.ONE * unit)
	draw_arc(Vector2(-12, -10), 8, PI * 0.4, PI * 1.6, 18, ink, 3.0, true)
	draw_arc(Vector2(12, -10), 8, -PI * 0.6, PI * 0.6, 18, ink, 3.0, true)
	draw_colored_polygon(PackedVector2Array([Vector2(-15,-19),Vector2(15,-19),Vector2(12,0),Vector2(6,7),Vector2(-6,7),Vector2(-12,0)]), ink)
	draw_line(Vector2(-9,-15),Vector2(-7,-2),Color.WHITE * Color(1,1,1,0.45),2.0,true)
	draw_rect(Rect2(-3,6,6,10),ink.darkened(0.1))
	draw_rect(Rect2(-12,15,24,5),ink)
	draw_set_transform(Vector2.ZERO)
	var font := ThemeDB.fallback_font
	var font_size := clampi(int(radius * 0.48), 12, 19)
	var text: String = PLACES[mini(rank,3)]
	var text_width := font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
	if rank != 2:
		draw_string(font,Vector2(center.x-text_width/2.0,minf(size.y-2,center.y+radius*1.25)),text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,ink)
	# Deterministic confetti: no use of gameplay randomness, nodes or particles.
	if not reduced_motion:
		for index in range(18):
			var progress := fposmod(elapsed * (0.19 + (index % 4) * 0.025) + index * 0.137, 1.0)
			var x := fposmod(index * 0.618, 1.0) * size.x + sin(elapsed * 1.5 + index) * 4
			var y := progress * (size.y + 12) - 6
			var color: Color = [ink,Color("88d5f6"),Color("f8a5bd")][index % 3]
			draw_line(Vector2(x,y),Vector2(x+2,y+3),Color(color,0.7),2.0,true)
