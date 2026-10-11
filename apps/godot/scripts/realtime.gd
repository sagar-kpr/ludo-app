extends Node

signal event_received(event: Dictionary)
signal connection_changed(online: bool, detail: String)

var socket := WebSocketPeer.new()
var previous_state := WebSocketPeer.STATE_CLOSED
var endpoint := ""
var intentional_close := false

func connect_server(url: String) -> void:
	endpoint = url
	intentional_close = false
	if socket.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		socket.close()
	socket = WebSocketPeer.new()
	previous_state = WebSocketPeer.STATE_CONNECTING
	var error := socket.connect_to_url(endpoint)
	connection_changed.emit(false, "Connecting…" if error == OK else "Cannot connect to the game server")
	if error != OK:
		previous_state = WebSocketPeer.STATE_CLOSED

func _process(_delta: float) -> void:
	socket.poll()
	var state := socket.get_ready_state()
	if state != previous_state:
		previous_state = state
		if state == WebSocketPeer.STATE_OPEN:
			connection_changed.emit(true, "Connected")
		elif state == WebSocketPeer.STATE_CLOSED:
			connection_changed.emit(false, "Disconnected — match recovery is not yet available" if not intentional_close else "Disconnected")
	while state == WebSocketPeer.STATE_OPEN and socket.get_available_packet_count() > 0:
		var parsed: Variant = JSON.parse_string(socket.get_packet().get_string_from_utf8())
		if parsed is Dictionary and parsed.get("type") is String:
			event_received.emit(parsed)

func send_intent(event: Dictionary) -> bool:
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return false
	return socket.send_text(JSON.stringify(event)) == OK

func disconnect_server() -> void:
	intentional_close = true
	socket.close()
