extends SubViewportContainer

signal roll_contact(settled: bool, strength: float)
const CONTACT_TIMES = [0.0,0.06,0.13,0.22,0.34,0.49,0.68,0.87]

var die: Node3D
var viewport: SubViewport
var camera: Camera3D
var settled_value := 1
var rolling := false
var reduced_motion := false
const PawnFinish = preload("res://scripts/pawn.gd")
const FACE_ROTATIONS = {
	1: Vector3(0,0,0), 2: Vector3(PI/2,0,0), 3: Vector3(0,0,PI/2),
	4: Vector3(0,0,-PI/2), 5: Vector3(-PI/2,0,0), 6: Vector3(PI,0,0)
}
const PIPS = {
	1: [Vector2(0,0)],
	2: [Vector2(-1,-1),Vector2(1,1)],
	3: [Vector2(-1,-1),Vector2(0,0),Vector2(1,1)],
	4: [Vector2(-1,-1),Vector2(1,-1),Vector2(-1,1),Vector2(1,1)],
	5: [Vector2(-1,-1),Vector2(1,-1),Vector2(0,0),Vector2(-1,1),Vector2(1,1)],
	6: [Vector2(-1,-1),Vector2(1,-1),Vector2(-1,0),Vector2(1,0),Vector2(-1,1),Vector2(1,1)]
}

func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(72,72)
	viewport = SubViewport.new()
	viewport.size = Vector2i(128,128)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	var root := Node3D.new()
	viewport.add_child(root)
	die = Node3D.new()
	root.add_child(die)
	var body := rounded_cube()
	var finish_helper := PawnFinish.new()
	var white := finish_helper.lacquer(Color.WHITE)
	white.set_shader_parameter("base_lift",0.40)
	finish_helper.free()
	add_mesh(body, Vector3.ZERO, white, die)
	var black := StandardMaterial3D.new()
	black.albedo_color = Color("101a2c")
	black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for face in range(1,7):
		var face_root := Node3D.new()
		face_root.rotation = -FACE_ROTATIONS[face]
		die.add_child(face_root)
		for pip in PIPS[face]:
			var inset := CylinderMesh.new()
			inset.top_radius = 0.071
			inset.bottom_radius = 0.071
			inset.height = 0.006
			inset.radial_segments = 24
			add_mesh(inset, Vector3(pip.x*0.25,0.502,pip.y*0.25), black, face_root)
	# Ground shadow makes the cube's height visible inside its button.
	var shadow := CylinderMesh.new()
	shadow.top_radius = 0.60
	shadow.bottom_radius = 0.60
	shadow.height = 0.008
	var shadow_mat := StandardMaterial3D.new()
	shadow_mat.albedo_color = Color(0.03,0.07,0.14,0.15)
	shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	add_mesh(shadow,Vector3(0,-0.54,0),shadow_mat,root)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.9
	camera.position = Vector3(2,4,2.6)
	root.add_child(camera)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55,-25,0)
	light.light_energy = 1.5
	root.add_child(light)
	show_face(1)

func rounded_cube() -> ImmediateMesh:
	# Rounded edges are geometry, so lighting works on both native and WebGL.
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := [
		[Vector3.UP,Vector3.RIGHT,Vector3.FORWARD],
		[Vector3.DOWN,Vector3.RIGHT,Vector3.BACK],
		[Vector3.RIGHT,Vector3.BACK,Vector3.UP],
		[Vector3.LEFT,Vector3.FORWARD,Vector3.UP],
		[Vector3.FORWARD,Vector3.RIGHT,Vector3.UP],
		[Vector3.BACK,Vector3.LEFT,Vector3.UP]
	]
	for face in faces:
		var order := [0,2,1,0,3,2] if face[1].cross(face[2]).dot(face[0]) > 0 else [0,1,2,0,2,3]
		for row in range(8):
			for col in range(8):
				var corners := [Vector2(col,row),Vector2(col+1,row),Vector2(col+1,row+1),Vector2(col,row+1)]
				for index in order:
					var grid: Vector2 = corners[index] / 8.0 - Vector2.ONE*0.5
					var raw: Vector3 = face[0]*0.5 + face[1]*grid.x + face[2]*grid.y
					var inner := raw.clamp(Vector3.ONE*-0.39,Vector3.ONE*0.39)
					var normal := (raw-inner).normalized()
					mesh.surface_set_normal(normal)
					mesh.surface_add_vertex(inner+normal*0.11)
	mesh.surface_end()
	return mesh

func add_mesh(mesh: Mesh, position_at: Vector3, material: Material, parent: Node3D) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = position_at
	instance.material_override = material
	parent.add_child(instance)

func show_face(value: int) -> void:
	if die and FACE_ROTATIONS.has(value):
		settled_value = value
		camera.size = 1.75
		die.rotation = FACE_ROTATIONS[value]
		die.position = Vector3.ZERO
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func animate_roll(value: int) -> void:
	rolling = true
	camera.size = 2.1
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var contacts := {"next":0}
	if not reduced_motion:
		var from := die.rotation
		var target: Vector3 = FACE_ROTATIONS.get(value, Vector3.ZERO)
		var tween := create_tween()
		tween.tween_method(func(progress: float):
			while contacts.next < CONTACT_TIMES.size() and progress >= CONTACT_TIMES[contacts.next]:
				roll_contact.emit(false,1.0-progress*0.65)
				contacts.next += 1
			var ease := 1.0 - pow(1.0 - progress, 3)
			die.rotation = from.lerp(target + Vector3(TAU*2,TAU*2,TAU), ease)
			die.position.y = sin(progress*PI) * 0.2
		, 0.0, 1.0, 1.2)
		await tween.finished
	else:
		# Reduced motion keeps the same sound rhythm without spinning the die.
		var previous := 0.0
		for progress in CONTACT_TIMES:
			if progress > previous:
				await get_tree().create_timer((progress-previous)*1.2).timeout
			roll_contact.emit(false,1.0-progress*0.65)
			previous = progress
		await get_tree().create_timer((1.0-previous)*1.2).timeout
	show_face(value)
	roll_contact.emit(true,0.75)
	rolling = false
