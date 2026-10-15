extends Control

const Design = preload("res://scripts/design.gd")
var entries: Dictionary = {}
var reduced_motion := false
var lifetime := 4.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func show_message(card: Control, sender: String, message: String) -> void:
	var id: String = card.player_id
	if entries.has(id):
		entries[id].tween.kill()
		entries[id].panel.queue_free()
	var bubble := PanelContainer.new()
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := Design.surface(Color("10243d"),12,card.avatar.accent.lightened(0.55))
	style.content_margin_left = 9
	style.content_margin_right = 9
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	bubble.add_theme_stylebox_override("panel",style)
	add_child(bubble)
	var text := Label.new()
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.max_lines_visible = 2
	text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_theme_font_size_override("font_size",12)
	text.add_theme_color_override("font_color",Color.WHITE)
	text.text = sender+": "+message.left(160)
	bubble.add_child(text)
	var tween := create_tween()
	entries[id] = {"panel":bubble,"card":card,"tween":tween}
	position_bubble(entries[id])
	if not reduced_motion:
		bubble.modulate.a = 0
		tween.tween_property(bubble,"modulate:a",1.0,0.16)
	tween.tween_interval(lifetime)
	if not reduced_motion:
		tween.tween_property(bubble,"modulate:a",0.0,0.25)
	tween.tween_callback(func():
		if entries.has(id) and entries[id].panel == bubble:
			entries.erase(id)
		bubble.queue_free()
	)

func position_bubble(entry: Dictionary) -> void:
	var card: Control = entry.card
	var panel: Control = entry.panel
	# Face captions away from the table: above top cards, below bottom cards.
	# Fall back below top-edge cards and clamp to the browser/safe viewport.
	var width := minf(card.panel.size.x, 200.0)
	panel.size = Vector2(maxf(80, width), 0)
	var at: Vector2 = card.panel.global_position - global_position
	at.y -= panel.size.y + 6
	if at.y < 4 or card.global_position.y-global_position.y > size.y * 0.5:
		at.y = card.global_position.y - global_position.y + card.size.y + 4
	at.x = clampf(at.x, 4, maxf(4, size.x-panel.size.x-4))
	at.y = clampf(at.y, 4, maxf(4, size.y-panel.size.y-4))
	panel.position = at
	panel.visible = card.is_visible_in_tree()

func _process(_delta: float) -> void:
	for entry in entries.values():
		position_bubble(entry)

func _exit_tree() -> void:
	for entry in entries.values():
		entry.tween.kill()
	entries.clear()
