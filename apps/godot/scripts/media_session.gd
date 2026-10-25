extends Node

signal credentials_requested
signal status_changed(message: String)
signal user_error(message: String)

var room_code := ""
var identity := ""
var connected := false
var wanted := false
var publishing := false
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
	var required_methods := ["connect_room", "disconnect_room", "set_publishing_enabled", "set_video_layout", "request_media_permissions"]
	var missing_methods: Array[String] = []
	for method_name in required_methods:
		if not candidate.has_method(method_name):
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
	if requesting or room_code.is_empty():
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
	if web_ready:
		JavaScriptBridge.eval("window.__rallyMedia.connect("+JSON.stringify(event)+"); null",true)
	elif is_instance_valid(native):
		native.connect_room(str(event.url),str(event.token))

func toggle() -> void:
	wanted = not wanted
	if not wanted:
		apply_publishing(false)
		return
	if not connected:
		request_credentials()
	else:
		apply_publishing(true)

func apply_publishing(enabled: bool) -> void:
	if web_ready:
		JavaScriptBridge.eval("window.__rallyMedia.setPublishing("+JSON.stringify(enabled)+"); null",true)
	elif _resolve_native():
		native.set_publishing_enabled(enabled)
	elif enabled:
		_on_status("error","RallyMedia is unavailable or incomplete. Check the Android plugin diagnostics and install the latest APK.")

func stop() -> void:
	room_code = ""
	identity = ""
	connected = false
	wanted = false
	publishing = false
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
	if state in ["error", "permissions_denied", "permission_required"]:
		push_warning("RallyMedia status %s: %s" % [state, message])
	match state:
		"connected", "reconnected":
			connected = true
			last_error = ""
			if wanted and not publishing:
				apply_publishing(true)
		"publishing_enabled":
			publishing = true
		"publishing_disabled":
			publishing = false
		"error", "permissions_denied":
			requesting = false
			last_error = message
			if wanted:
				user_error.emit(message)
			wanted = false
			publishing = false
		"disconnected":
			connected = false
			wanted = false
			publishing = false
	status_changed.emit(message)

func update_layout(data: Dictionary) -> void:
	if web_ready:
		JavaScriptBridge.eval("window.__rallyMedia.layout("+JSON.stringify(data)+"); null",true)
	elif is_instance_valid(native) and native.has_method("set_video_layout"):
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
