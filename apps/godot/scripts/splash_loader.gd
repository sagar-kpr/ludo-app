extends Control

const NEXT_SCENE = "res://scenes/main.tscn"

@onready var title_label: Label = $Center/VBox/Title
@onready var subtitle_label: Label = $Center/VBox/SubTitle
@onready var progress_bar: ProgressBar = $Center/VBox/ProgressBar

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	title_label.text = "RALLY"
	subtitle_label.text = "Loading your table..."
	progress_bar.min_value = 0.0
	progress_bar.max_value = 100.0
	progress_bar.value = 0.0
	_start_loading()

func _start_loading() -> void:
	var tween := create_tween()
	tween.tween_property(progress_bar, "value", 100.0, 1.2)
	tween.finished.connect(_goto_main)

func _goto_main() -> void:
	get_tree().change_scene_to_file(NEXT_SCENE)
