extends RefCounted

# Pure display adapter. Server colors, player IDs and path positions never change.
const BoardMath = preload("res://scripts/board_math.gd")
const Design = preload("res://scripts/design.gd")
var turns := 0
var local_seat := 3
var preferred_seat := 3

static func for_player(players: Array, player_id: String, preferred_color: String):
	var view = load("res://scripts/board_perspective.gd").new()
	for player in players:
		if str(player.get("id", "")) == player_id:
			var seat: int = BoardMath.COLORS.find(str(player.get("color", "")))
			var preferred: int = BoardMath.COLORS.find(preferred_color)
			if seat >= 0 and preferred >= 0:
				view.local_seat = seat
				view.preferred_seat = preferred
				view.turns = posmod(3 - seat, 4)
			break
	return view

func signature() -> String:
	return "%d:%d:%d" % [turns, local_seat, preferred_seat]

func visual_seat(logical_color: String) -> int:
	return posmod(BoardMath.COLORS.find(logical_color) + turns, 4)

func logical_seat(visual_corner: int) -> int:
	return posmod(visual_corner - turns, 4)

func display_key(logical_color: String) -> String:
	return BoardMath.COLORS[posmod(BoardMath.COLORS.find(logical_color) - local_seat + preferred_seat, 4)]

func display_color(logical_color: String) -> Color:
	return Design.COLORS.get(display_key(logical_color), Design.FOREST)

func palette() -> Dictionary:
	var result := {}
	for color in BoardMath.COLORS:
		result[color] = display_color(color)
	return result

func cell(logical: Vector2i) -> Vector2i:
	var result := logical
	for step in range(turns):
		result = Vector2i(result.y, 14 - result.x)
	return result

func world(logical: Vector3) -> Vector3:
	var result := logical
	for step in range(turns):
		result = Vector3(-result.z, result.y, result.x)
	return result
