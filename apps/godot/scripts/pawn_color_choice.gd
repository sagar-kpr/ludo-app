extends Button

const Pawn = preload("res://scripts/pawn.gd")
const Design = preload("res://scripts/design.gd")
const KEYS := ["coral","sun","violet","mint"]
const TILE := Vector2i(152,176)
var color_key := "coral"
var selected := false:
	set(value):
		selected = value
		queue_redraw()
var preview: SubViewport

# One static atlas per dashboard, shared by all four choices. No live preview
# loops, separate worlds per button or external pawn images are needed.
static func make_atlas(parent: Node) -> SubViewport:
	var atlas := SubViewport.new()
	atlas.name = "PawnColorPreviewAtlas"
	atlas.size = Vector2i(TILE.x*4,TILE.y)
	atlas.own_world_3d = true
	atlas.transparent_bg = true
	atlas.gui_disable_input = true
	atlas.msaa_3d = Viewport.MSAA_2X
	atlas.render_target_update_mode = SubViewport.UPDATE_ONCE
	parent.add_child(atlas)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.3
	atlas.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48,-38,0)
	light.light_energy = 0.8
	atlas.add_child(light)
	for index in range(4):
		var pawn := Pawn.new()
		atlas.add_child(pawn)
		pawn.configure("color-preview",Design.COLORS[KEYS[index]])
		pawn.position.x = (index-1.5)*2.0
		pawn.set_process(false)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 8.0
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	var center := Vector3(0,0.17,-0.64)
	camera.position = center + Vector3(0,30,5)
	atlas.add_child(camera)
	camera.look_at(center)
	camera.current = true
	return atlas

func _ready() -> void:
	custom_minimum_size = Vector2(38,44)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "Choose " + str(Design.COLOR_NAMES[color_key]) + " pawns on your screen"
	for state in ["normal","hover","pressed","focus"]:
		add_theme_stylebox_override(state,StyleBoxEmpty.new())
	resized.connect(queue_redraw)
	queue_redraw()

func _draw() -> void:
	if not is_instance_valid(preview):
		return
	var source := Rect2(Vector2(KEYS.find(color_key)*TILE.x,0),Vector2(TILE))
	draw_texture_rect_region(preview.get_texture(),Rect2(Vector2.ZERO,size-Vector2(0,4)),source)
	if selected or has_focus():
		draw_line(Vector2(size.x*0.24,size.y-2),Vector2(size.x*0.76,size.y-2),Design.GOLD,2.0,true)
