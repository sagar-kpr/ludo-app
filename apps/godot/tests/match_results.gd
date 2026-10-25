extends SceneTree

const MainScene = preload("res://scenes/main.tscn")
var failures := 0
var checks := 0

class RecordingNetwork extends Node:
	var requests: Array[Dictionary] = []
	func send_intent(intent: Dictionary) -> bool:
		requests.append(intent)
		return true

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func run() -> void:
	var state := {"players":[],"tokens":[],"phase":"finished","currentPlayer":"0","finishOrder":["0","1","2","3"],"winner":"0","dice":null,"version":10}
	for index in range(4):
		var color: String = ["coral","mint","sun","violet"][index]
		state.players.append({"id":str(index),"name":"Player " + str(index),"color":color})
		for pawn in range(4):
			state.tokens.append({"id":"%d-%d" % [index,pawn],"color":color,"position":57})
	var clients: Array = []
	for index in range(2):
		var client = MainScene.instantiate()
		root.add_child(client)
		client.network.disconnect_server()
		client.network.set_process(false)
		var recorder := RecordingNetwork.new()
		client.add_child(recorder)
		client.network = recorder
		client.self_id = str(index)
		client.online = true
		client.pending = false
		client.presenting = false
		client.room_code = "TEST-ROOM"
		client.game = state.duplicate(true)
		client.show_state()
		client.refresh_controls()
		clients.append(client)
		check(client.result.title.is_empty() and client.result.borderless,"Results have no title bar")
		check(client.result.get_ok_button().text == "OK" and not client.result.dialog_hide_on_ok,"Every player has the same OK action and waits for leave confirmation")
		check(client.result_list.get_child_count() == 4,"Every player sees four ranked avatars")
		check(client.result_celebration.visible and client.result_celebration.is_processing(),"Popup has a looping celebration")
		check(not client.cards[1].status_label.text.contains("3rd"),"Third-place profile has no third-place text")
		check(not client.board.rank_labels["2"].text.contains("3rd"),"Third-place board box has no third-place text")
		if index == 0:
			client.result.hide() # Test clients share a root; real devices do not.
	var host = clients[0]
	var guest = clients[1]
	host.result.confirmed.emit()
	host.result.confirmed.emit()
	check(host.network.requests.size() == 1 and host.network.requests[0].type == "LEAVE_GAME","Host OK sends exactly one leave and never restarts the room")
	await host.present_event({"type":"LEFT_ROOM"})
	check(host.home.visible and host.room_code.is_empty(),"Only the acknowledging player returns to the dashboard")
	check(guest.result.visible and guest.network.requests.is_empty(),"Another player's OK does not dismiss this player's results")
	guest.game.players.remove_at(0)
	guest.game.finishOrder = ["1","2","3"]
	guest.show_state()
	check(guest.result_list.get_child_count() == 4 and guest.result_state.finishOrder[0] == "0","Final standings remain unchanged when another player leaves")
	await create_timer(4.2).timeout
	check(guest.result.visible and not guest.home.visible,"Results remain until this player presses OK")
	guest.result.confirmed.emit()
	check(guest.network.requests.size() == 1 and guest.network.requests[0].type == "LEAVE_GAME","Guest OK uses the same leave action")
	await guest.present_event({"type":"LEFT_ROOM"})
	check(guest.home.visible and guest.result_state.is_empty(),"Guest OK returns home and clears the old results")
	check(not guest.result_celebration.is_processing(),"Closing results stops popup animation")
	for client in clients:
		client.queue_free()
	await process_frame
	print("Match results: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
