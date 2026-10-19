extends Control

# Static 2D artwork, cached once in a 1024-square viewport. The 32px gutter
# leaves room for the Theme's soft frame shadow without moving board cells.
const Tokens = preload("res://resources/theme_tokens.tres")
const BoardMath = preload("res://scripts/board_math.gd")
const RESOLUTION := 1024
const CELL := 64.0
const ORIGIN := Vector2(32, 32)
const CORNERS := [Vector2(0, 0), Vector2(9, 0), Vector2(9, 9), Vector2(0, 9)]
var yard_gradients: Array[GradientTexture2D] = []
var colors: Dictionary = Tokens.player_colors()
var cell_gradients: Dictionary = {}
var yard_trims: Array[StyleBoxFlat] = []

func _ready() -> void:
	theme = Tokens
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(RESOLUTION, RESOLUTION)
	for key in BoardMath.COLORS:
		var color: Color = colors[key]
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.40, 1.0])
		var shade: Color = color.darkened(Tokens.yard_shade)
		gradient.colors = PackedColorArray([color.lightened(Tokens.yard_highlight), color, shade])
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.width = 128
		texture.height = 128
		texture.fill_from = Vector2.ZERO
		texture.fill_to = Vector2(0.35, 1.0)
		yard_gradients.append(texture)
		var trim := StyleBoxFlat.new()
		trim.bg_color = Color(color.darkened(0.20),0.10)
		trim.border_color = Color(Color.WHITE,0.24)
		trim.set_border_width_all(2)
		trim.set_corner_radius_all(20)
		yard_trims.append(trim)
	# Restrained gradients read as matte card stock, with one shared light direction.
	for color in [Tokens.cell_white, Tokens.red, Tokens.green, Tokens.blue, Tokens.yellow]:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
		var shade: Color = color.darkened(0.07 if color != Tokens.cell_white else 0.035)
		gradient.colors = PackedColorArray([color.lightened(0.055), color, shade])
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.width = 64
		texture.height = 64
		texture.fill_from = Vector2.ZERO
		texture.fill_to = Vector2(0.35,1.0)
		cell_gradients[color] = texture
	queue_redraw()

func _draw() -> void:
	if yard_gradients.size() != 4:
		return
	var board_rect := Rect2(ORIGIN, Vector2.ONE * CELL * 15)
	var frame := get_theme_stylebox("frame", "Board") as StyleBoxFlat
	draw_style_box(frame, board_rect)
	for seat in range(4):
		_draw_yard(seat, frame)
	_draw_track()
	_draw_lane_marks()
	_draw_center()
	# All arrows point INTO the appropriate home lane.
	_draw_arrow(_cell_center(7, 0), Vector2.RIGHT, colors.coral)
	_draw_arrow(_cell_center(0, 7), Vector2.DOWN, colors.sun)
	_draw_arrow(_cell_center(7, 14), Vector2.LEFT, colors.mint)
	_draw_arrow(_cell_center(14, 7), Vector2.UP, colors.violet)
	draw_style_box(get_theme_stylebox("rim", "Board"), board_rect)

func _draw_yard(seat: int, frame: StyleBoxFlat) -> void:
	var rect := Rect2(ORIGIN + CORNERS[seat] * CELL, Vector2.ONE * CELL * 6)
	# Round only the yard's exterior corner; shared track boundaries stay square.
	var points := PackedVector2Array()
	var uvs := PackedVector2Array()
	var vertices := [rect.position, rect.position + Vector2(rect.size.x, 0), rect.end, rect.position + Vector2(0, rect.size.y)]
	for corner in range(4):
		var radius := float(frame.get_corner_radius(corner)) if corner == seat else 0.0
		if radius <= 0.0:
			points.append(vertices[corner])
		else:
			var offsets := [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]
			var center: Vector2 = vertices[corner] + offsets[corner] * radius
			for step in range(9):
				var angle := PI + corner * PI / 2 + step * PI / 16
				points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	for point in points:
		uvs.append((point - rect.position) / rect.size)
	draw_polygon(points, PackedColorArray([Color.WHITE]), uvs, yard_gradients[seat])
	var floor_rect := Rect2(rect.position + Vector2.ONE * CELL, Vector2.ONE * CELL * 4)
	draw_style_box(yard_trims[seat],floor_rect.grow(10))
	draw_style_box(get_theme_stylebox("yard_floor", "Board"), floor_rect)
	draw_style_box(get_theme_stylebox("yard_inset", "Board"), floor_rect.grow(-2))
	# Recessed matte docks retain the exact existing pawn anchors.
	for index in range(4):
		var dock := BoardMath.world(BoardMath.COLORS[seat], 0, index)
		var point := ORIGIN + Vector2(dock.x + 7.5, dock.z + 7.5) * CELL
		var color: Color = colors[BoardMath.COLORS[seat]]
		var radius := CELL*0.44
		draw_circle(point,radius+2.0,Color(color.darkened(0.3),0.22),true,-1,true)
		draw_circle(point,radius,color,true,-1,true)
		draw_arc(point,radius-1.0,PI,TAU,40,Color(0.10,0.15,0.20,0.13),1.5,true)
		draw_arc(point,radius-1.0,0,PI,40,Color(1,1,1,0.22),1.5,true)

func cell_color(row: int, col: int) -> Color:
	var color: Color = Tokens.cell_white
	if row == 7 and col >= 1 and col <= 5:
		color = colors.coral
	elif col == 7 and row >= 1 and row <= 5:
		color = colors.sun
	elif row == 7 and col >= 9 and col <= 13:
		color = colors.mint
	elif col == 7 and row >= 9 and row <= 13:
		color = colors.violet
	for seat in range(4):
		if [row, col] == BoardMath.TRACK[seat * 13]:
			color = colors[BoardMath.COLORS[seat]]
	return color

func _is_track(row: int, col: int) -> bool:
	return (row in range(6, 9) or col in range(6, 9)) and not (row in range(6, 9) and col in range(6, 9))

func _draw_track() -> void:
	# Paint every fill before any grid edge. Adjacent fills otherwise cover
	# half of the antialiased stroke, especially visible on the green lane.
	for row in range(15):
		for col in range(15):
			if _is_track(row, col):
				var rect := _cell_rect(row,col)
				var color := cell_color(row, col)
				draw_texture_rect(cell_gradients[color],rect,false)
				# All bevels sit inside their cell; no offset or accumulated rounding.
				var inset := rect.grow(-1.75)
				draw_line(inset.position,inset.position+Vector2(inset.size.x,0),Color(1,1,1,0.40),1.25,true)
				draw_line(inset.position,inset.position+Vector2(0,inset.size.y),Color(1,1,1,0.22),1.25,true)
				draw_line(inset.position+Vector2(0,inset.size.y),inset.end,Color(0.02,0.04,0.10,0.10),1.5,true)
	for row in range(15):
		for col in range(15):
			if not _is_track(row, col):
				continue
			var rect := _cell_rect(row,col)
			var color := cell_color(row, col)
			# Draw shared edges once for even, thin lines at mobile sizes.
			draw_line(rect.position, rect.position + Vector2(CELL, 0), Tokens.grid_ink, Tokens.grid_width, true)
			draw_line(rect.position, rect.position + Vector2(0, CELL), Tokens.grid_ink, Tokens.grid_width, true)
			if not _is_track(row + 1, col) or row == 14:
				draw_line(rect.position + Vector2(0, CELL), rect.end, Tokens.grid_ink, Tokens.grid_width, true)
			if not _is_track(row, col + 1) or col == 14:
				draw_line(rect.position + Vector2(CELL, 0), rect.end, Tokens.grid_ink, Tokens.grid_width, true)
			if BoardMath.TRACK.find([row, col]) in BoardMath.SAFE:
				_draw_star(rect.get_center(), Tokens.safe_ink if color == Tokens.cell_white else Tokens.safe_on_color)

func _cell_rect(row: int, col: int) -> Rect2:
	return Rect2(ORIGIN+Vector2(col,row)*CELL,Vector2.ONE*CELL)

func _cell_center(row: int, col: int) -> Vector2:
	return _cell_rect(row,col).get_center()

func _draw_lane_marks() -> void:
	var directions := [Vector2.RIGHT,Vector2.DOWN,Vector2.LEFT,Vector2.UP]
	for step in [2,4]:
		var cells := [Vector2i(7,step),Vector2i(step,7),Vector2i(7,14-step),Vector2i(14-step,7)]
		for seat in range(4):
			var at := _cell_center(cells[seat].x,cells[seat].y)
			var direction: Vector2 = directions[seat]
			var side := Vector2(-direction.y,direction.x)
			var points := PackedVector2Array([at-direction*6+side*6,at+direction*3,at-direction*6-side*6])
			draw_polyline(points,Color(1,1,1,0.42),2.0,true)

func _draw_star(at: Vector2, ink: Color) -> void:
	var points := PackedVector2Array()
	for index in range(10):
		var angle := index * TAU / 10 - PI / 2
		var radius := CELL * (0.36 if index % 2 == 0 else 0.165)
		points.append(at + Vector2(cos(angle), sin(angle)) * radius)
	draw_colored_polygon(points,Color(ink,0.08))
	points.append(points[0])
	draw_polyline(points, ink, Tokens.symbol_width, true)

func _draw_arrow(at: Vector2, direction: Vector2, color: Color) -> void:
	# A darker print keeps even the yellow arrow legible on white.
	var ink := color.lerp(Color("263b50"),0.42)
	var side := Vector2(-direction.y, direction.x)
	var points := PackedVector2Array([
		at-direction*17-side*2,at+direction*2-side*2,
		at+direction*2-side*10,at+direction*18,
		at+direction*2+side*10,at+direction*2+side*2,at-direction*17+side*2
	])
	draw_colored_polygon(points,ink)
	points.append(points[0])
	draw_polyline(points,ink,1.0,true)

func _draw_center() -> void:
	var center := _cell_center(7, 7)
	var extent := Vector2.ONE * CELL * 1.5
	var corners := [center - extent, center + Vector2(extent.x, -extent.y), center + extent, center + Vector2(-extent.x, extent.y)]
	# Left red, top green, right yellow, bottom blue, as in the existing board.
	for seat in range(4):
		var a: Vector2 = corners[(seat + 3) % 4]
		var b: Vector2 = corners[seat]
		var color: Color = colors[BoardMath.COLORS[seat]]
		draw_polygon(PackedVector2Array([a, b, center]), PackedColorArray([color.darkened(Tokens.center_shade), color, color.lightened(Tokens.center_highlight)]))
	for corner in corners:
		draw_line(center,corner,Color(Color("354655"),0.40),Tokens.grid_width,true)
	var border := PackedVector2Array(corners)
	border.append(border[0])
	draw_polyline(border,Tokens.grid_ink,Tokens.grid_width,true)
	# A tiny ivory join finishes the four inlaid panels without creating a cell.
	var join := PackedVector2Array([center+Vector2(0,-7),center+Vector2(7,0),center+Vector2(0,7),center+Vector2(-7,0)])
	draw_colored_polygon(join,Tokens.cell_white)
