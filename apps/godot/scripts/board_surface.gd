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

func _ready() -> void:
	theme = Tokens
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(RESOLUTION, RESOLUTION)
	for key in BoardMath.COLORS:
		var color: Color = colors[key]
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.40, 1.0])
		var shade: Color = Color("e8ac08") if color == Tokens.yellow else color.darkened(Tokens.yard_shade)
		gradient.colors = PackedColorArray([color.lightened(Tokens.yard_highlight), color, shade])
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.width = 128
		texture.height = 128
		texture.fill_from = Vector2.ZERO
		texture.fill_to = Vector2(0.35, 1.0)
		yard_gradients.append(texture)
	# Small cached textures give every tile a lit face without per-frame work.
	for color in [Tokens.cell_white, Tokens.red, Tokens.green, Tokens.blue, Tokens.yellow]:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
		var shade: Color = Color("e8ac08") if color == Tokens.yellow else color.darkened(0.18 if color != Tokens.cell_white else 0.06)
		gradient.colors = PackedColorArray([color.lightened(0.16), color, shade])
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
	draw_style_box(get_theme_stylebox("yard_floor", "Board"), floor_rect)
	# StyleBoxFlat has no inner shadow: a translucent inset border fakes it.
	draw_style_box(get_theme_stylebox("yard_inset", "Board"), floor_rect.grow(-2))
	# Keep existing dock markers until the token/slot section is approved.
	for index in range(4):
		var dock := BoardMath.world(BoardMath.COLORS[seat], 0, index)
		var point := ORIGIN + Vector2(dock.x + 7.5, dock.z + 7.5) * CELL
		draw_circle(point, CELL * 0.44, colors[BoardMath.COLORS[seat]])

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
				var rect := Rect2(ORIGIN + Vector2(col, row) * CELL, Vector2.ONE * CELL)
				var color := cell_color(row, col)
				draw_texture_rect(cell_gradients[color],rect,false)
				# Inset highlights and a lower lip read as a shallow raised tile.
				var inset := rect.grow(-2.0)
				draw_line(inset.position,inset.position+Vector2(inset.size.x,0),Color(1,1,1,0.42),2.0,true)
				draw_line(inset.position,inset.position+Vector2(0,inset.size.y),Color(1,1,1,0.23),2.0,true)
				draw_line(inset.position+Vector2(0,inset.size.y),inset.end,Color(0.02,0.04,0.10,0.22),3.0,true)
	for row in range(15):
		for col in range(15):
			if not _is_track(row, col):
				continue
			var rect := Rect2(ORIGIN + Vector2(col, row) * CELL, Vector2.ONE * CELL)
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

func _cell_center(row: int, col: int) -> Vector2:
	return ORIGIN + Vector2(col + 0.5, row + 0.5) * CELL

func _draw_star(at: Vector2, ink: Color) -> void:
	var points := PackedVector2Array()
	for index in range(10):
		var angle := index * TAU / 10 - PI / 2
		var radius := CELL * (0.36 if index % 2 == 0 else 0.17)
		points.append(at + Vector2(cos(angle), sin(angle)) * radius)
	points.append(points[0])
	draw_polyline(points, ink, Tokens.symbol_width, true)

func _draw_arrow(at: Vector2, direction: Vector2, color: Color) -> void:
	# A darker print keeps even the yellow arrow legible on white.
	var ink := color.darkened(0.24)
	var side := Vector2(-direction.y, direction.x)
	var tip := at + direction * CELL * 0.29
	draw_line(at - direction * CELL * 0.29, tip, ink, Tokens.symbol_width + 1, true)
	draw_polyline(PackedVector2Array([at + side * CELL * 0.18, tip, at - side * CELL * 0.18]), ink, Tokens.symbol_width + 1, true)

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
		draw_line(center, corner, Color(Tokens.grid_ink, 0.65), Tokens.grid_width, true)
