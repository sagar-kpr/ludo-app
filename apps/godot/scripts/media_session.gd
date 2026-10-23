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

func _ready() -> void:
	if Engine.has_singleton("RallyMedia"):
		native = Engine.get_singleton("RallyMedia")
		native.connect("media_status",_on_status)
	if OS.has_feature("web"):
		JavaScriptBridge.eval(FileAccess.get_file_as_string("res://web/media.js"),true)
		web_ready = true

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
	if not web_ready and not is_instance_valid(native):
		_on_status("error","Camera and voice are available in the web game or the Android app with RallyMedia installed.")
		return
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
	elif is_instance_valid(native) and native.has_method("set_publishing_enabled"):
		native.set_publishing_enabled(enabled)
	elif enabled:
		_on_status("error","Please install the updated Android media plugin to enable calls.")

func stop() -> void:
	room_code = ""
	identity = ""
	connected = false
	wanted = false
	publishing = false
	requesting = false
	last_error = ""
	if web_ready:
		JavaScriptBridge.eval("window.__rallyMedia.disconnect(); window.__rallyMedia.poll(); null",true)
	elif is_instance_valid(native):
		native.disconnect_room()

func _on_status(state: String, message: String) -> void:
	if room_code.is_empty():
		return
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
