extends Node

signal event_received(event: Dictionary)
signal connection_changed(online: bool, detail: String)

var socket := WebSocketPeer.new()
var previous_state := WebSocketPeer.STATE_CLOSED
var endpoint := ""
var intentional_close := false
var retry_elapsed := 0.0
var session_token := ""
var recovery_available := false
var last_reply_ms := 0
var last_ping_ms := 0
var connecting_since_ms := 0
var awaiting_probe := false
var has_room := false
var visibility_elapsed := 0.0

func _ready() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("if (!window.__rallyResumeHook) { window.__rallyResumeHook = true; const sync = () => { if (!document.hidden) window.__rallyNeedsSync = true; }; document.addEventListener('visibilitychange', sync); window.addEventListener('focus', sync); window.addEventListener('pageshow', sync); window.addEventListener('online', sync); }",true)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		probe_connection()

func probe_connection() -> void:
	if intentional_close or endpoint.is_empty():
		return
	if socket.get_ready_state() == WebSocketPeer.STATE_CONNECTING:
		return
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		connect_server(endpoint)
	elif recovery_available and not awaiting_probe:
		awaiting_probe = true
		connection_changed.emit(false,"Checking connection…")
		last_ping_ms = Time.get_ticks_msec()
		send_intent({"type":"PING"})
		send_intent({"type":"SYNC_STATE"})

func connect_server(url: String) -> void:
	endpoint = url
	intentional_close = false
	retry_elapsed = 0.0
	if socket.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		socket.close()
	socket = WebSocketPeer.new()
	previous_state = WebSocketPeer.STATE_CONNECTING
	connecting_since_ms = Time.get_ticks_msec()
	last_reply_ms = connecting_since_ms
	awaiting_probe = false
	# Godot's native WebSocket parser requires a slash before a query on a
	# bare host. Keep existing paths/query parameters when appending recovery.
	var parts := endpoint.split("?",true,1)
	var base: String = parts[0]
	if not base.substr(base.find("://")+3).contains("/"):
		base += "/"
	var target := base+("?"+parts[1] if parts.size() > 1 else "")
	if not session_token.is_empty():
		target += ("&" if "?" in target else "?")+"session="+session_token.uri_encode()
	var error := socket.connect_to_url(target)
	connection_changed.emit(false, "Connecting…" if error == OK else "Cannot connect to the game server")
	if error != OK:
		previous_state = WebSocketPeer.STATE_CLOSED

func _process(delta: float) -> void:
	# Consume queued replies before deciding a stalled frame means a dead socket.
	socket.poll()
	var now := Time.get_ticks_msec()
	var state := socket.get_ready_state()
	if state != previous_state:
		previous_state = state
		if state == WebSocketPeer.STATE_OPEN:
			retry_elapsed = 0.0
			last_reply_ms = now
			last_ping_ms = now
			connection_changed.emit(false, "Restoring connection…")
		elif state == WebSocketPeer.STATE_CLOSED:
			connection_changed.emit(false, "Reconnecting…" if not intentional_close else "Disconnected")
	while state == WebSocketPeer.STATE_OPEN and socket.get_available_packet_count() > 0:
		var parsed: Variant = JSON.parse_string(socket.get_packet().get_string_from_utf8())
		if parsed is Dictionary and parsed.get("type") is String:
			last_reply_ms = Time.get_ticks_msec()
			if parsed.type == "CONNECTED":
				has_room = bool(parsed.get("resumed",false))
				session_token = str(parsed.get("sessionToken",""))
				recovery_available = bool(parsed.get("recoveryAvailable",false))
				if not parsed.get("resumed",false):
					connection_changed.emit(true,"Connected")
			elif parsed.type == "PONG":
				if awaiting_probe and has_room:
					# A room snapshot, rather than a pong, unlocks a resumed match.
					continue
				awaiting_probe = false
				connection_changed.emit(true,"Connected")
				continue
			elif parsed.type == "STATE" and parsed.get("recovered",false):
				has_room = true
				awaiting_probe = false
				connection_changed.emit(true,"Connected")
			elif parsed.type in ["ROOM_CREATED","ROOM_JOINED"]:
				has_room = true
			elif parsed.type == "LEFT_ROOM":
				has_room = false
				awaiting_probe = false
			event_received.emit(parsed)
	visibility_elapsed += delta
	if OS.has_feature("web") and visibility_elapsed >= 0.3:
		visibility_elapsed = 0
		if JavaScriptBridge.eval("Boolean(window.__rallyNeedsSync && (window.__rallyNeedsSync = false, true))",true):
			probe_connection()
	state = socket.get_ready_state()
	if state == WebSocketPeer.STATE_CONNECTING and now-connecting_since_ms > 12000:
		connect_server(endpoint)
		return
	if state == WebSocketPeer.STATE_OPEN and recovery_available:
		if awaiting_probe and now-last_ping_ms >= 4000:
			connect_server(endpoint)
			return
		if now-last_reply_ms > 12000:
			# Probe first: the render thread may simply have stopped sending pings.
			if not awaiting_probe:
				probe_connection()
			return
		if not awaiting_probe and now-last_ping_ms >= 5000:
			last_ping_ms = now
			send_intent({"type":"PING"})
	if state == WebSocketPeer.STATE_CLOSED and not intentional_close and not endpoint.is_empty():
		retry_elapsed += delta
		if retry_elapsed >= 2.0:
			connect_server(endpoint)

func send_intent(event: Dictionary) -> bool:
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return false
	return socket.send_text(JSON.stringify(event)) == OK

func disconnect_server() -> void:
	intentional_close = true
	socket.close()
