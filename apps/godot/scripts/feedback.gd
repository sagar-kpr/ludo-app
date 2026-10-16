extends Node

signal haptic_pulse(duration_ms: int)

var sound_enabled := true
var haptics_enabled := true
var samples: Dictionary = {}
var voices: Array[AudioStreamPlayer] = []
var next_voice := 0
var last_cue := ""
var capture_pulse: Tween

func _ready() -> void:
	# Original, cached PCM cues; no downloads, third-party assets or audio on frame loop.
	for kind in ["dice","dice_settle","step","capture","chat","sticker_hit","sticker_cheer"]:
		samples[kind] = synthesize(kind)
	for index in range(4):
		var player := AudioStreamPlayer.new()
		player.volume_db = -13.0
		add_child(player)
		voices.append(player)

func synthesize(kind: String) -> AudioStreamWAV:
	var duration := 0.075 if kind == "dice" else 0.11 if kind == "dice_settle" else 0.30 if kind == "capture" else 0.16 if kind == "chat" else 0.11 if kind == "step" else 0.075
	var rate := 22050
	var data := PackedByteArray()
	data.resize(int(duration*rate)*2)
	for index in range(data.size()/2):
		var t := float(index)/rate
		var envelope := minf(t/0.003,1.0)*pow(maxf(0,1.0-t/duration),2.0)
		var pitch := 660.0 if kind == "chat" else 330.0 if kind == "step" else 520.0-t*850 if kind == "capture" else 190.0 if kind == "dice_settle" else 230.0
		var wave := sin(TAU*pitch*t)*0.65 + sin(TAU*pitch*1.51*t)*0.18
		if kind == "step":
			# A gently damped wooden tap: fixed pitches, rounded attack and
			# a short tail keep repeated steps soft and free of a squeaky slide.
			wave = sin(TAU*280.0*t)*0.70*exp(-t*24.0) + sin(TAU*620.0*t)*0.13*exp(-t*60.0)
		elif kind == "sticker_hit":
			wave = sin(TAU*(95-t*220)*t)*exp(-t*30)+sin(t*11003)*exp(-t*90)*0.4
		elif kind == "sticker_cheer":
			wave = sin(TAU*880*t)*0.5+sin(TAU*1320*t)*0.3
		if kind == "dice":
			wave = (sin(t*17003.0)*0.3+sin(t*3011.0)*0.4)*exp(-t*55.0)
		var value := int(clampf(wave*envelope,-1,1)*23000.0)
		data.encode_s16(index*2,value)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = data
	return stream

func cue(kind: String, local_haptic: bool = false, strength: float = 1.0) -> void:
	last_cue = kind
	if sound_enabled and samples.has(kind):
		var voice := voices[next_voice]
		next_voice = (next_voice+1)%voices.size()
		voice.stream = samples[kind]
		voice.volume_db = (-17.0 if kind == "step" else -16.0 if kind == "chat" else -10.0 if kind == "capture" else -12.0) + linear_to_db(clampf(strength,0.1,1.0))
		voice.pitch_scale = 0.90+strength*0.10 if kind == "dice" else 1.0
		voice.play()
	if haptics_enabled and local_haptic:
		pulse(40 if kind == "sticker_hit" else 55 if kind == "capture" else 8 if kind == "step" else 16 if kind == "dice_settle" else 7)
		if kind == "capture":
			if capture_pulse and capture_pulse.is_valid():
				capture_pulse.kill()
			capture_pulse = create_tween()
			capture_pulse.tween_interval(0.09)
			capture_pulse.tween_callback(func(): pulse(30))

func pulse(duration_ms: int) -> void:
	if not haptics_enabled:
		return
	haptic_pulse.emit(duration_ms)
	if OS.get_name() in ["Android","iOS","Web"]:
		Input.vibrate_handheld(duration_ms)

func _exit_tree() -> void:
	if capture_pulse and capture_pulse.is_valid():
		capture_pulse.kill()
	for voice in voices:
		voice.stop()
		voice.stream = null
	samples.clear()
