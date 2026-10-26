extends Node

signal credentials_requested
signal status_changed(message: String)
signal user_error(message: String)

var room_code := ""
var identity := ""
var connected := false
var wanted := false
var publishing := false
var camera_enabled := false
var microphone_enabled := false
var wanted_camera := false
var wanted_microphone := false
var muted_players: Dictionary = {}
var remote_audio_players: Dictionary = {}
var connecting := false
var controls_open := false
var requesting := false
var request_started := 0
var native
var web_ready := false
var elapsed := 0.0
var last_error := ""
var native_probe_elapsed := 0.0
var waiting_for_native := false
var native_status_connected := false
var native_missing_logged := false
var native_discovered_logged := false
var native_api_error_logged := false

func _ready() -> void:
	_resolve_native()
	if OS.has_feature("web"):
		JavaScriptBridge.eval(FileAccess.get_file_as_string("res://web/media.js"),true)
		web_ready = true

static func native_has_method(candidate: Object, method_name: String) -> bool:
	# Android plugin methods live in JNISingleton's Java method map, not
	# Object's method list. Keep ordinary Objects usable for desktop tests.
	if candidate.has_method("has_java_method"):
		return candidate.has_java_method(method_name)
	return candidate.has_method(method_name)

func _resolve_native() -> bool:
	if web_ready or not Engine.has_singleton("RallyMedia"):
		if OS.has_feature("android") and not native_missing_logged:
			push_warning("RallyMedia Android singleton is not available yet; discovery will retry.")
			native_missing_logged = true
		native = null
		return false
	var candidate = Engine.get_singleton("RallyMedia")
	if not is_instance_valid(candidate):
		return false
	var required_methods := ["connect_room", "disconnect_room", "set_local_media", "set_participant_muted", "set_video_layout", "request_media_permissions"]
	var missing_methods: Array[String] = []
	for method_name in required_methods:
		if not native_has_method(candidate,method_name):
			missing_methods.append(method_name)
	if not candidate.has_signal("media_status"):
		missing_methods.append("signal media_status")
	native = candidate
	if not missing_methods.is_empty():
		if not native_api_error_logged:
			push_error("RallyMedia was discovered but its Android API is incomplete: %s" % ", ".join(missing_methods))
			native_api_error_logged = true
		return false
	if not native_status_connected:
		candidate.connect("media_status",_on_status)
		native_status_connected = true
	if not native_discovered_logged:
		print("RallyMedia Android singleton discovered; required methods and media_status signal are available.")
		native_discovered_logged = true
	return true

func join(code: String, player_id: String) -> void:
	if room_code == code:
		return
	stop()
	room_code = code
	identity = player_id
	request_credentials()

func request_credentials() -> void:
	if requesting or connecting or room_code.is_empty():
		return
	if not web_ready and not _resolve_native():
		waiting_for_native = OS.has_feature("android") and not Engine.has_singleton("RallyMedia")
		_on_status("error","Camera and voice are available in the web game or the Android app with RallyMedia installed.")
		return
	waiting_for_native = false
	requesting = true
	request_started = Time.get_ticks_msec()
	status_changed.emit("Connecting voice…")
	credentials_requested.emit()

func receive(event: Dictionary) -> void:
	if room_code.is_empty() or str(event.get("roomCode","")) != room_code:
		return
	requesting = false
	if event.type == "MEDIA_ERROR":
		_on_status("error",str(event.get("message","Voice could not connect.")))
		return
	if str(event.get("identity","")) != identity:
		return
	connecting = true
	if web_ready:
		JavaScriptBridge.eval("window.__rallyMedia.connect("+JSON.stringify(event)+"); null",true)
	elif is_instance_valid(native):
		native.connect_room(str(event.url),str(event.token))

func toggle() -> void:
	if not controls_open:
		set_local_media(not wanted,not wanted)
	else:
		set_local_media(not wanted_camera,wanted_microphone)

func toggle_microphone() -> void:
	set_local_media(wanted_camera,not wanted_microphone)

func set_local_media(camera: bool, microphone: bool) -> void:
	wanted_camera = camera
	wanted_microphone = microphone
	wanted = camera or microphone
	if not connected:
		if wanted:
			request_credentials()
	else:
		apply_local_media()

func apply_publishing(enabled: bool) -> void:
	# Compatibility for callers that want to switch both devices together.
	set_local_media(enabled,enabled)

func apply_local_media() -> void:
	if web_ready:
		JavaScriptBridge.eval("window.__rallyMedia.setLocalMedia("+JSON.stringify(wanted_camera)+","+JSON.stringify(wanted_microphone)+"); null",true)
	elif _resolve_native():
		native.set_local_media(wanted_camera,wanted_microphone)
	elif wanted:
		_on_status("error","RallyMedia is unavailable or incomplete. Check the Android plugin diagnostics and install the latest APK.")

func is_player_muted(player_id: String) -> bool:
	return bool(muted_players.get(player_id,false))

func has_player_audio(player_id: String) -> bool:
	return bool(remote_audio_players.get(player_id,false))

func set_player_muted(player_id: String, muted: bool) -> void:
	if player_id.is_empty() or player_id == identity or room_code.is_empty():
		return
	if muted:
		muted_players[player_id] = true
	else:
		muted_players.erase(player_id)
	if web_ready:
		JavaScriptBridge.eval("window.__rallyMedia.setParticipantMuted("+JSON.stringify(player_id)+","+JSON.stringify(muted)+"); null",true)
	elif _resolve_native():
		native.set_participant_muted(player_id,muted)

func stop() -> void:
	room_code = ""
	identity = ""
	connected = false
	wanted = false
	publishing = false
	wanted_camera = false
	wanted_microphone = false
	camera_enabled = false
	microphone_enabled = false
	muted_players.clear()
	remote_audio_players.clear()
	connecting = false
	controls_open = false
	requesting = false
	waiting_for_native = false
	last_error = ""
	if web_ready:
		JavaScriptBridge.eval("window.__rallyMedia.disconnect(); window.__rallyMedia.poll(); null",true)
	elif is_instance_valid(native):
		native.disconnect_room()

func _on_status(state: String, message: String) -> void:
	if room_code.is_empty():
		return
	if state == "remote_audio_state":
		var players: Variant = JSON.parse_string(message)
		if players is Array:
			remote_audio_players.clear()
			for player_id in players:
				if player_id is String and player_id != identity:
					remote_audio_players[player_id] = true
		return
	if state in ["error", "permissions_denied", "permission_required"]:
		push_warning("RallyMedia status %s: %s" % [state, message])
	match state:
		"connected", "reconnected":
			connected = true
			connecting = false
			last_error = ""
			if wanted:
				apply_local_media()
			for player_id in muted_players:
				set_player_muted(player_id,true)
		"publishing_enabled":
			camera_enabled = true
			microphone_enabled = true
		"publishing_disabled":
			camera_enabled = false
			microphone_enabled = false
		"camera_enabled", "camera_disabled":
			camera_enabled = state == "camera_enabled"
		"microphone_enabled", "microphone_disabled":
			microphone_enabled = state == "microphone_enabled"
		"camera_error", "microphone_error":
			if state == "camera_error":
				wanted_camera = false
				camera_enabled = false
			else:
				wanted_microphone = false
				microphone_enabled = false
			last_error = message
			user_error.emit(message)
		"error", "permissions_denied":
			requesting = false
			connecting = false
			last_error = message
			if wanted:
				user_error.emit(message)
			wanted = false
			wanted_camera = false
			wanted_microphone = false
			camera_enabled = false
			microphone_enabled = false
		"disconnected":
			remote_audio_players.clear()
			connected = false
			connecting = false
			wanted_camera = false
			wanted_microphone = false
			camera_enabled = false
			microphone_enabled = false
	wanted = wanted_camera or wanted_microphone
	publishing = camera_enabled or microphone_enabled
	if publishing:
		controls_open = true
	status_changed.emit(message)

func update_layout(data: Dictionary) -> void:
	if web_ready:
		JavaScriptBridge.eval("window.__rallyMedia.layout("+JSON.stringify(data)+"); null",true)
	elif is_instance_valid(native) and native_has_method(native,"set_video_layout"):
		native.set_video_layout(JSON.stringify(data))

func _process(delta: float) -> void:
	if not web_ready and OS.has_feature("android"):
		native_probe_elapsed += delta
		if native_probe_elapsed >= 0.5:
			native_probe_elapsed = 0.0
			if _resolve_native() and waiting_for_native and not room_code.is_empty():
				waiting_for_native = false
				request_credentials()
	if requesting and Time.get_ticks_msec()-request_started > 10000:
		_on_status("error","Voice could not connect. Check your connection and try again.")
	elapsed += delta
	if not web_ready or elapsed < 0.1:
		return
	elapsed = 0
	var values: Variant = JSON.parse_string(str(JavaScriptBridge.eval("window.__rallyMedia.poll()",true)))
	if values is Array:
		for event in values:
			_on_status(str(event.get("state","")),str(event.get("message","")))

func _exit_tree() -> void:
	stop()
