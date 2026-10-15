extends RefCounted

# Coordinate adapter only. Rules and dice truth live in packages/game-engine.
const COLORS = ["coral", "sun", "mint", "violet"]
const OFFSETS = {"coral": 0, "sun": 13, "mint": 26, "violet": 39}
const SAFE = [0, 8, 13, 21, 26, 34, 39, 47]
const HOME = 57
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
	if position >= HOME:
		return [Vector2i(7,6), Vector2i(6,7), Vector2i(7,8), Vector2i(8,7)][seat]
	if position <= 51:
		var square: Array = TRACK[(int(OFFSETS[color]) + position - 1) % 52]
		return Vector2i(square[0], square[1])
	var lane := position - 51
	return [Vector2i(7,lane), Vector2i(lane,7), Vector2i(7,14-lane), Vector2i(14-lane,7)][seat]

static func world(color: String, position: int, token_index: int) -> Vector3:
	if position == 0:
		var centers := [Vector2(-4.5,-4.5),Vector2(4.5,-4.5),Vector2(4.5,4.5),Vector2(-4.5,4.5)]
		var center: Vector2 = centers[COLORS.find(color)]
		return Vector3(center.x+(-1.0 if token_index % 2 == 0 else 1.0),0.22,center.y+(-1.0 if token_index < 2 else 1.0))
	var square := coordinate(color, position, token_index)
	if position >= HOME:
		# Four finished pins fit within their own colored center triangle.
		return Vector3(square.y - 7 + (-0.23 if token_index % 2 == 0 else 0.23), 0.22, square.x - 7 + (-0.20 if token_index < 2 else 0.20))
	return Vector3(square.y - 7,0.22,square.x - 7)

static func legal(token: Dictionary, dice: int, tokens: Array = []) -> bool:
	# UI affordance only; mirror authoritative movement and destination checks.
	var position := int(token.position)
	if dice < 1 or dice > 6 or position >= HOME or (position == 0 and dice != 6):
		return false
	var destination := 1 if position == 0 else position + dice
	if destination > HOME:
		return false
	if destination == HOME:
		return true
	if tokens.is_empty():
		return true
	if destination <= 51 and (int(OFFSETS[token.color]) + destination - 1) % 52 in SAFE:
		return true
	for other in tokens:
		if other.id != token.id and other.color == token.color and int(other.position) == destination:
			return false
	return true
