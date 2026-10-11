extends Control

const Art = preload("res://scripts/sticker_art.gd")
signal contact(kind: String)
var kind := "HAMMER"
var recipient: Control
var sender: Control
var reduced_motion := false
var art
var time := 0.0
var strikes := 0
var burst := 0.0
var destination := Vector2.ZERO
var style_name := ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	art = Art.new()
	art.kind = kind
	add_child(art)
	style_name = kind.to_lower()

func _process(delta: float) -> void:
	if not is_instance_valid(recipient) or not recipient.is_visible_in_tree():
		queue_free()
		return
	time += delta
	# Recompute anchors and size every frame, including window resize mid-flight.
	var extent := clampf(recipient.size.x*0.48,64,104)
	size = Vector2.ONE*extent
	art.size = size
	art.pivot_offset = size*0.5
	var bounds := get_viewport_rect().size
	var avatar_center: Vector2 = recipient.avatar.global_position+recipient.avatar.size*0.5
	var target: Vector2 = avatar_center-get_parent().global_position
	destination = target-size*0.5
	if kind == "HAMMER":
		destination += Vector2(extent*0.28,-extent*0.22)
	elif kind == "CROWN":
		destination.y -= extent*0.38
	destination.x = clampf(destination.x,2,maxf(2,bounds.x-extent-2))
	destination.y = clampf(destination.y,2,maxf(2,bounds.y-extent-2))
	if time < 0.65 and not reduced_motion:
		var start := destination
		if is_instance_valid(sender):
			start = sender.avatar.global_position+sender.avatar.size*0.5-get_parent().global_position-size*0.5
		var progress := clampf(time/0.65,0,1)
		position = start.lerp(destination,smoothstep(0,1,progress))+Vector2(0,-sin(progress*PI)*minf(55,bounds.y*0.07))
		art.scale = Vector2.ONE*(0.5+progress*0.5)
	else:
		position = destination
		art.scale = Vector2.ONE
		art.playing = not reduced_motion
		var local_time := maxf(0,time-0.65)
		if not reduced_motion:
			animate_action(local_time)
	burst = maxf(0,burst-delta*3)
	# Allow for squashing and expanding child art without crossing the window.
	var padding := extent*0.16+2
	position.x = clampf(position.x,padding,maxf(padding,bounds.x-extent-padding))
	position.y = clampf(position.y,padding,maxf(padding,bounds.y-extent-padding))
	modulate.a = clampf((3.8-time)/0.35,0,1)
	queue_redraw()
	if time >= 3.8:
		queue_free()

func hit() -> void:
	burst = 1
	contact.emit(kind)
	if kind in ["HAMMER","BOOM","PUNCH","TOMATO","EGG"]:
		recipient.avatar.react("hit")
	else:
		recipient.avatar.react("happy")

func animate_action(t: float) -> void:
	match kind:
		"PUNCH":
			var phase := fmod(t,0.65)
			art.position.x = 20*(1-clampf(phase/0.12,0,1))
			art.scale = Vector2.ONE*(1+sin(clampf(phase/0.3,0,1)*PI)*0.18)
			if phase > 0.12 and strikes <= int(t/0.65) and strikes < 3:
				strikes += 1
				hit()
		"TOMATO", "EGG":
			if strikes == 0:
				strikes = 1
				hit()
			art.scale = Vector2(1.3,0.6)
		"KISS":
			art.scale = Vector2.ONE*(1+sin(t*6)*0.1)
			art.position.y = -t*5
		"HAMMER":
			# Handle pivot winds back slowly, snaps the head down, then rebounds.
			var cycle := fmod(t,0.72)
			var count := int(t/0.72)
			if count < 3 and art.model:
				var swing := lerpf(-1.0,1.15,clampf((cycle-0.32)/0.10,0,1)) if cycle < 0.46 else lerpf(1.15,-1.0,clampf((cycle-0.46)/0.26,0,1))
				art.parts.hammer.rotation.z = swing
				if cycle >= 0.42 and strikes <= count:
					strikes = count+1
					hit()
		"BOOM":
			art.scale = Vector2.ONE*(0.8+sin(minf(t/0.35,1)*PI)*0.5)
			if strikes == 0:
				strikes = 1
				hit()
		"CLAP":
			var count := int(t/0.4)
			if count < 4 and strikes <= count:
				strikes = count+1
				hit()
		"CROWN":
			art.position.y = -18*(1-clampf(t/0.5,0,1))
			if t >= 0.5 and strikes == 0:
				strikes = 1
				hit()
		"GIFT":
			if t > 0.35 and strikes == 0:
				strikes = 1
				hit()
		"LOVE":
			art.position.y = -t*6
		"FIRE":
			art.position.y = sin(t*12)*2
		"LAUGH":
			art.position.y = -absf(sin(t*9))*8
		"PARTY", "TROPHY", "COOL", "CLOWN":
			if strikes == 0:
				strikes = 1
				hit()

func _draw() -> void:
	if burst <= 0:
		return
	for i in range(10):
		var angle := i*TAU/10
		var center := size*0.5
		var radius := size.x*(0.24+(1-burst)*0.25)
		draw_line(center+Vector2.from_angle(angle)*radius,center+Vector2.from_angle(angle)*(radius+9),Color(1,0.82,0.2,burst),3,true)
	if kind in ["TOMATO","EGG"]:
		for i in range(7):
			var angle := i*TAU/7
			draw_circle(size*0.5+Vector2.from_angle(angle)*size.x*0.3,5,Color(1,0.22,0.16,burst) if kind == "TOMATO" else Color(1,0.8,0.15,burst))
