extends SceneTree

const Board = preload("res://scripts/board.gd")
const BoardMath = preload("res://scripts/board_math.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func run() -> void:
	var board := Board.new()
	root.add_child(board)
	board.size = Vector2(420,420)
	await process_frame
	for color in BoardMath.COLORS:
		var state := {"players": [{"id": "a", "color": color}], "currentPlayer": "a", "phase": "moving", "tokens": []}
		for index in range(4):
			state.tokens.append({"id": "a-%d" % index, "color": color, "position": BoardMath.HOME})
		for distance in range(1,7):
			state.tokens[0].position = BoardMath.HOME-distance
			for dice in range(1,7):
				state.dice = dice
				var fits := dice <= distance
				check(BoardMath.legal(state.tokens[0], dice) == fits, "UI legality requires an exact finish without overshoot")
				for viewer in ["a", "b"]:
					board.apply_state(state, viewer)
					var pawn = board.pawns["a-0"]
					pawn._process(0)
					check(pawn.legal_move == (fits and viewer == "a"), "Only the owner can tap a fitting move")
					check(pawn.highlight == fits, "Both screens hide overshoot highlights")
					if not fits:
						check(not pawn.ring.visible, "Overshooting pawn has no misleading movement ring")
					check(not board.pawns["a-1"].legal_move and not board.pawns["a-1"].highlight, "Completed pawns remain inactive")
		state.tokens[0].position = 0
		for dice in range(1,7):
			check(BoardMath.legal(state.tokens[0],dice) == (dice == 6), "Exact finish change preserves six-only base entry")
	# The rolling cue must use the actual face, not light every unfinished pin.
	for color in BoardMath.COLORS:
		var state := {"players":[{"id":"a","color":color}],"currentPlayer":"a","phase":"rolling","dice":null,"tokens":[]}
		for index in range(4):
			state.tokens.append({"id":"a-%d" % index,"color":color,"position":BoardMath.HOME-3 if index == 0 else BoardMath.HOME})
		board.apply_state(state,"a")
		check(not board.pawns["a-0"].highlight,"No pawn selection highlight before rolling")
		board.highlight_player(color,5)
		board.pawns["a-0"]._process(0)
		check(not board.pawns["a-0"].highlight and not board.pawns["a-0"].ring.visible,"Needs three, rolled five: no animation highlight")
		board.highlight_player(color,3)
		check(board.pawns["a-0"].highlight,"Exact roll can cue the finishing pawn")
		for position in range(1,BoardMath.HOME):
			for dice in range(1,7):
				var destination := position+dice
				if destination > BoardMath.HOME:
					continue
				state.phase = "moving"
				state.dice = dice
				state.tokens[0].position = position
				state.tokens[1].position = destination
				var star: bool = destination <= 51 and (int(BoardMath.OFFSETS[color])+destination-1)%52 in BoardMath.SAFE
				var allowed: bool = destination == BoardMath.HOME or star
				check(BoardMath.legal(state.tokens[0],dice,state.tokens) == allowed,"Friendly occupancy is permitted only on stars or finish docks")
				board.apply_state(state,"a")
				check(board.pawns["a-0"].highlight == allowed and board.pawns["a-0"].legal_move == allowed,"Highlight and input agree with occupied destination rules")
				board.highlight_player(color,dice)
				check(board.pawns["a-0"].highlight == allowed,"Dice animation also filters occupied destinations")
	board.queue_free()
	await process_frame
	print("Finish rules: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
