extends SceneTree

const MediaSession = preload("res://scripts/media_session.gd")
const PlayerCard = preload("res://scripts/player_card.gd")
const METHODS = ["connect_room","disconnect_room","set_local_media","set_participant_muted","set_video_layout","request_media_permissions"]
var checks := 0
var failures := 0

# Mimics JNI's separate method registry: Object.has_method() cannot see these
# methods even though the native plugin supports them.
class JavaPlugin extends RefCounted:
	signal media_status(state: String, message: String)
	var methods: Array = []
	func has_java_method(method_name: String) -> bool:
		return methods.has(method_name)

class OrdinaryPlugin extends RefCounted:
	func set_video_layout(_value: String) -> void:
		pass

class ControllablePlugin extends RefCounted:
	signal media_status(state: String, message: String)
	var local_calls: Array = []
	var mute_calls: Array = []
	func connect_room(_url: String, _token: String) -> void: pass
	func disconnect_room() -> void: pass
	func set_local_media(camera: bool, microphone: bool) -> void:
		local_calls.append([camera,microphone])
	func set_participant_muted(player_id: String, muted: bool) -> void:
		mute_calls.append([player_id,muted])
	func set_video_layout(_value: String) -> void: pass
	func request_media_permissions() -> void: pass

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var plugin := JavaPlugin.new()
	plugin.methods = METHODS.duplicate()
	for method_name in METHODS:
		check(not plugin.has_method(method_name),"Fixture reproduces JNI's separate method registry")
		check(MediaSession.native_has_method(plugin,method_name),"Java plugin method detected: " + method_name)
	check(not MediaSession.native_has_method(plugin,"missing"),"Unknown native methods stay unavailable")
	var ordinary := OrdinaryPlugin.new()
	check(MediaSession.native_has_method(ordinary,"set_video_layout"),"Ordinary object method fallback works")
	check(not MediaSession.native_has_method(ordinary,"missing"),"Fallback rejects unknown methods")
	Engine.register_singleton("RallyMedia",plugin)
	var session := MediaSession.new()
	root.add_child(session)
	check(session._resolve_native(),"JNI singleton is accepted with all required Java methods")
	check(plugin.media_status.get_connections().size() == 1,"Status signal is connected exactly once")
	check(session._resolve_native(),"Repeated discovery succeeds")
	check(plugin.media_status.get_connections().size() == 1,"Repeated discovery does not duplicate signal handlers")
	session.room_code = "TEST"
	plugin.media_status.emit("connected","Connected")
	check(session.connected,"Native connection status reaches the session")
	session.room_code = "" # No native method calls in this registry-only fixture.
	session.native = null
	session.free()
	Engine.unregister_singleton("RallyMedia")
	# The Java registry is authoritative, even if Object itself has a method.
	check(not MediaSession.native_has_method(plugin,"get_class"),"Object methods cannot mask a missing Java API")
	var controls := ControllablePlugin.new()
	Engine.register_singleton("RallyMedia",controls)
	var call := MediaSession.new()
	root.add_child(call)
	call.room_code = "TEST"
	call.identity = "self"
	call.connected = true
	check(not call.controls_open,"Extra controls start hidden for receive-only participants")
	call.toggle()
	check(controls.local_calls.back() == [true,true],"First camera tap starts both devices")
	check(not call.controls_open,"Extra controls wait for actual capture to start")
	call.toggle()
	check(controls.local_calls.back() == [false,false] and not call.wanted,"Second startup tap cancels pending capture")
	call.toggle()
	check(controls.local_calls.back() == [true,true],"A cancelled startup can be retried")
	controls.media_status.emit("publishing_enabled","On")
	check(call.controls_open and call.camera_enabled and call.microphone_enabled,"Successful call reveals independent controls")
	call.toggle_microphone()
	check(controls.local_calls.back() == [true,false],"Muting own microphone preserves camera")
	controls.media_status.emit("microphone_disabled","Off")
	check(call.camera_enabled and not call.microphone_enabled,"Microphone status never hides camera")
	call.toggle()
	check(controls.local_calls.back() == [false,false],"Hiding camera preserves the muted microphone")
	controls.media_status.emit("publishing_disabled","Off")
	check(call.controls_open,"Controls stay available when both devices are off")
	call.toggle_microphone()
	check(controls.local_calls.back() == [false,true],"Microphone can restart in audio-only mode")
	controls.media_status.emit("microphone_enabled","On")
	check(call.microphone_enabled and not call.camera_enabled,"Audio-only publication keeps the avatar")
	call.toggle()
	check(controls.local_calls.back() == [true,true],"Camera can be restored during audio-only mode")
	controls.media_status.emit("camera_error","Denied")
	check(not call.wanted_camera and call.wanted_microphone,"Camera failure preserves requested microphone")
	check(call.publishing and call.microphone_enabled,"Camera failure does not stop an active microphone")
	var count := controls.local_calls.size()
	call.set_player_muted("other",true)
	check(call.is_player_muted("other") and controls.mute_calls.back() == ["other",true],"Per-player mute reaches native playback")
	check(controls.local_calls.size() == count,"Muting another player never changes local capture")
	call.set_player_muted("other",false)
	check(not call.is_player_muted("other") and controls.mute_calls.back() == ["other",false],"Per-player unmute restores playback")
	call.set_player_muted("self",true)
	check(not call.is_player_muted("self"),"Receiver mute cannot mute own outgoing microphone")
	call.set_player_muted("other",true)
	call.set_player_muted("third",true)
	check(call.is_player_muted("other") and call.is_player_muted("third"),"A listener can mute two speakers independently")
	call.set_player_muted("other",false)
	check(not call.is_player_muted("other") and call.is_player_muted("third"),"Unmuting one speaker preserves the other speaker's mute")
	call.stop()
	check(not call.controls_open and call.muted_players.is_empty(),"Leaving resets controls and local mute preferences")
	check(not call.camera_enabled and not call.microphone_enabled,"Leaving resets both publication indicators")
	call.free()
	Engine.unregister_singleton("RallyMedia")
	# Check every receiver/publisher combination in 2-, 3- and 4-player rooms.
	# Local capture is independent from who can be muted on this receiver.
	var view := MediaSession.new()
	view.room_code = "PERSPECTIVES"
	var cards: Array = []
	for index in range(4):
		var card := PlayerCard.new()
		root.add_child(card)
		cards.append(card)
	for count_players in [2,3,4]:
		for mask in range(1 << count_players):
			var senders: Array = []
			for index in range(count_players):
				if mask & (1 << index): senders.append(str(index))
			for receiver in range(count_players):
				view.identity = str(receiver)
				view._on_status("remote_audio_state",JSON.stringify(senders))
				for own_call in [false,true]:
					for target in range(count_players):
						var own := target == receiver
						var has_audio: bool = senders.has(str(target)) and not own
						var card = cards[target]
						card.call_controls_open = own_call
						card.remote_audio_available = view.has_player_audio(str(target))
						card.update_player({"id":str(target),"name":"Player " + str(target),"color":"coral"},false,false,own)
						check(card.speaker_button.visible == has_audio,"Speaker visibility follows sender audio for every viewer, not their own call")
						check(card.microphone_button.visible == (own and own_call),"Microphone control remains private to a started local call")
	view.identity = "receiver"
	view.muted_players["sender"] = true
	view._on_status("remote_audio_state",'["sender"]')
	check(view.has_player_audio("sender") and view.is_player_muted("sender"),"A locally muted sender keeps an unmute control")
	view._on_status("remote_audio_state",'[]')
	check(not view.has_player_audio("sender") and view.is_player_muted("sender"),"Stopping sender audio hides control without losing listener mute choice")
	view._on_status("remote_audio_state",'["sender"]')
	check(view.has_player_audio("sender") and view.is_player_muted("sender"),"Republishing audio restores the same muted control")
	view._on_status("disconnected","Disconnected")
	check(view.remote_audio_players.is_empty(),"Media disconnect removes stale speaker controls")
	for card in cards: card.free()
	view.free()
	print("Native media API: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
