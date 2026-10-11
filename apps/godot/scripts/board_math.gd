extends RefCounted

# Coordinate adapter only. Rules and dice truth live in packages/game-engine.
const COLORS = ["coral", "sun", "mint", "violet"]
const OFFSETS = {"coral": 0, "sun": 13, "mint": 26, "violet": 39}
const SAFE = [0, 8, 13, 21, 26, 34, 39, 47]
const TRACK = [
	[6,1],[6,2],[6,3],[6,4],[6,5],[5,6],[4,6],[3,6],[2,6],[1,6],[0,6],[0,7],[0,8],
	[1,8],[2,8],[3,8],[4,8],[5,8],[6,9],[6,10],[6,11],[6,12],[6,13],[6,14],[7,14],[8,14],
	[8,13],[8,12],[8,11],[8,10],[8,9],[9,8],[10,8],[11,8],[12,8],[13,8],[14,8],[14,7],[14,6],
	[13,6],[12,6],[11,6],[10,6],[9,6],[8,5],[8,4],[8,3],[8,2],[8,1],[8,0],[7,0],[6,0]
]

static func coordinate(color: String, position: int, token_index: int) -> Vector2i:
	var seat: int = COLORS.find(color)
	if position == 0:
		var bases := [Vector2i(1,1), Vector2i(1,10), Vector2i(10,10), Vector2i(10,1)]
		return bases[seat] + Vector2i(1 + (2 if token_index >= 2 else 0), 1 + 2 * (token_index % 2))
	if position == 58:
		return Vector2i(7,7)
	if position <= 51:
		var square: Array = TRACK[(int(OFFSETS[color]) + position - 1) % 52]
		return Vector2i(square[0], square[1])
	var lane := position - 51
	return [Vector2i(7,lane), Vector2i(lane,7), Vector2i(7,14-lane), Vector2i(14-lane,7)][seat]

static func world(color: String, position: int, token_index: int) -> Vector3:
	var square := coordinate(color, position, token_index)
	return Vector3(square.y - 7,0.22,square.x - 7)

static func legal(token: Dictionary, dice: int) -> bool:
	# UI affordance only; the server still validates every move.
	var position := int(token.position)
	# HOME is terminal. Keep this explicit so a finished pawn cannot become
	# selectable during a stale snapshot/animation handoff.
	if position >= 58:
		return false
	return dice > 0 and (dice == 6 if position == 0 else position + dice <= 58)
