extends SubViewportContainer

var kind := "HAMMER"
var model: Node3D
var parts: Dictionary = {}
var elapsed := 0.0
var playing := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stretch = true
	var view := SubViewport.new()
	view.size = Vector2i(128,128)
	view.transparent_bg = true
	view.own_world_3d = true
	view.msaa_3d = Viewport.MSAA_2X
	add_child(view)
	var world := Node3D.new()
	view.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("b9c8ed")
	environment.environment.ambient_light_energy = 0.65
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-30,-35,0)
	light.light_energy = 1.6
	world.add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.9
	camera.position = Vector3(0,1,7)
	world.add_child(camera)
	camera.look_at(Vector3.ZERO)
	model = Node3D.new()
	model.rotation_degrees.y = -18
	world.add_child(model)
	build_model()

func part(parent: Node3D, at: Vector3, dimensions: Vector3, color: Color, rounded: bool = true, metal: float = 0.0) -> MeshInstance3D:
	var mesh: Mesh
	if rounded:
		var sphere := SphereMesh.new()
		sphere.radius = 0.5
		sphere.height = 1.0
		mesh = sphere
	else:
		var cube := BoxMesh.new()
		cube.size = Vector3.ONE
		mesh = cube
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = at
	node.scale = dimensions
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metal
	mat.roughness = 0.25
	node.material_override = mat
	parent.add_child(node)
	return node

func heart(at: Vector3, factor: float) -> Node3D:
	var node := Node3D.new()
	node.position = at
	node.scale = Vector3.ONE*factor
	model.add_child(node)
	var pink := Color("ff3e78")
	part(node,Vector3(-0.25,0.2,0),Vector3.ONE*0.8,pink)
	part(node,Vector3(0.25,0.2,0),Vector3.ONE*0.8,pink)
	part(node,Vector3(0,-0.15,0),Vector3(0.65,0.65,0.45),pink,false).rotation.z = PI/4
	return node

func build_model() -> void:
	var gold := Color("ffca32")
	match kind:
		"PUNCH":
			part(model,Vector3(0,0.2,0),Vector3(1.4,1.2,1),Color("ed334f"))
			part(model,Vector3(0.55,-0.1,0.3),Vector3(0.5,0.65,0.6),Color("ff6170"))
			part(model,Vector3(0,-0.65,0),Vector3(0.75,0.6,0.8),Color("d92749"),false)
			part(model,Vector3(0,-0.7,0.44),Vector3(0.7,0.15,0.07),Color.WHITE,false)
		"KISS":
			for side in [-1,1]:
				part(model,Vector3(side*0.25,0.15,0),Vector3(0.8,0.5,0.5),Color("fa376a"))
			part(model,Vector3(0,-0.2,0),Vector3(1.25,0.45,0.45),Color("ff517b"))
			part(model,Vector3(0,0,0.26),Vector3(0.85,0.06,0.04),Color("7d193e"),false)
		"TOMATO":
			part(model,Vector3.ZERO,Vector3(1.4,1.25,1.4),Color("f23e39"))
			for i in range(5):
				var leaf := part(model,Vector3(0,0.61,0),Vector3(0.8,0.08,0.22),Color("35b64d"),false)
				leaf.rotation.y = i*TAU/5
		"EGG":
			part(model,Vector3.ZERO,Vector3(1,1.5,1),Color("fff3dd"))
		"HAMMER":
			var pivot := Node3D.new()
			pivot.position.y = -0.65
			model.add_child(pivot)
			parts.hammer = pivot
			part(pivot,Vector3(0,0.65,0),Vector3(0.22,1.45,0.26),Color("bd672c"),false)
			part(pivot,Vector3(0,1.45,0),Vector3(1.35,0.48,0.65),Color("b9d1e5"),false,0.65)
			part(pivot,Vector3(-0.57,1.45,0),Vector3(0.16,0.57,0.73),Color("7894ae"),false,0.65)
		"LOVE":
			parts.heart = heart(Vector3.ZERO,1)
			for i in range(3):
				parts["heart%d" % i] = heart(Vector3((i-1)*0.65,0.9,-0.3),0.25)
		"GIFT":
			part(model,Vector3(0,-0.3,0),Vector3(1.2,0.9,1),Color("ce367b"),false)
			part(model,Vector3(0,-0.3,0.52),Vector3(0.16,0.9,0.05),gold,false)
			var lid := Node3D.new()
			lid.position.y = 0.22
			model.add_child(lid)
			parts.lid = lid
			part(lid,Vector3.ZERO,Vector3(1.35,0.2,1.12),Color("ff6397"),false)
			for x in [-0.23,0.23]:
				part(lid,Vector3(x,0.23,0),Vector3(0.5,0.3,0.25),gold)
		"CROWN", "TROPHY":
			if kind == "TROPHY":
				part(model,Vector3(0,-0.7,0),Vector3(1,0.16,0.7),gold,false,0.5)
				part(model,Vector3(0,-0.3,0),Vector3(0.18,0.8,0.18),gold,false,0.5)
				part(model,Vector3(0,0.3,0),Vector3(1.2,1,1),gold,true,0.5)
				for x in [-0.65,0.65]:
					part(model,Vector3(x,0.35,0),Vector3(0.3,0.65,0.3),gold,true,0.5)
			else:
				part(model,Vector3(0,-0.3,0),Vector3(1.5,0.35,0.65),gold,false,0.5)
				for i in range(5):
					var spike := CylinderMesh.new()
					spike.top_radius = 0
					spike.bottom_radius = 0.23
					spike.height = 0.8
					var node := part(model,Vector3((i-2)*0.3,0.2,0.2),Vector3.ONE,gold,true,0.5)
					node.mesh = spike
					part(model,Vector3((i-2)*0.3,-0.25,0.55),Vector3.ONE*0.15,Color("f14162"))
		"FIRE":
			for i in range(7):
				parts["flame%d" % i] = part(model,Vector3((i-3)*0.19,-0.2,0),Vector3(0.5,1.2,0.4),Color("ff6825") if i%2 else gold)
		"BOOM", "PARTY":
			for i in range(16):
				var angle := i*TAU/16
				parts["spark%d" % i] = part(model,Vector3(cos(angle),sin(angle),0)*0.7,Vector3(0.18,0.3,0.15),[gold,Color("ff427e"),Color("57d8e7")][i%3],false)
			if kind == "PARTY":
				var cone := CylinderMesh.new()
				cone.top_radius = 0.5
				cone.bottom_radius = 0
				cone.height = 1.2
				var node := part(model,Vector3(0,-0.5,0.3),Vector3.ONE,Color("9667ff"))
				node.mesh = cone
				node.rotation.z = -0.5
			else:
				part(model,Vector3.ZERO,Vector3.ONE,Color("ff7d22"))
		"CLAP":
			for side in [-1,1]:
				var hand := Node3D.new()
				hand.position.x = side*0.45
				model.add_child(hand)
				parts["hand%d" % side] = hand
				part(hand,Vector3.ZERO,Vector3(0.6,0.8,0.4),Color("ffc49a"))
				for i in range(4):
					part(hand,Vector3((i-1.5)*0.15,0.4,0),Vector3(0.16,0.55,0.16),Color("ffc49a"))
		_:
			part(model,Vector3.ZERO,Vector3.ONE*1.7,gold)
			for x in [-0.29,0.29]:
				if kind == "COOL":
					part(model,Vector3(x,0.18,0.76),Vector3(0.48,0.26,0.12),Color("132b49"),false)
				else:
					part(model,Vector3(x,0.22,0.73),Vector3.ONE*0.36,Color.WHITE)
					part(model,Vector3(x,0.22,0.88),Vector3.ONE*0.16,Color("18304b"))
			part(model,Vector3(0,-0.28,0.77),Vector3(0.6,0.6 if kind == "LAUGH" else 0.25,0.2),Color("511d36"))
			if kind == "LAUGH":
				part(model,Vector3(0,-0.12,0.9),Vector3(0.4,0.1,0.05),Color.WHITE,false)
			if kind == "CLOWN":
				part(model,Vector3(0,0,0.9),Vector3.ONE*0.4,Color("ff384b"))
				for x in [-0.8,0.8]:
					part(model,Vector3(x,0.2,0),Vector3.ONE*0.65,Color("ec3c62"))

func _process(delta: float) -> void:
	if not playing or not model:
		return
	elapsed += delta
	match kind:
		"KISS":
			model.scale.x = 1+sin(elapsed*8)*0.12
		"FIRE":
			for i in range(7):
				parts["flame%d" % i].scale.y = 1+sin(elapsed*17+i)*0.35
		"LOVE":
			parts.heart.scale = Vector3.ONE*(1+sin(elapsed*7)*0.1)
			for i in range(3):
				parts["heart%d" % i].position.y = fmod(elapsed*0.8+i*0.4,1.8)-0.4
		"GIFT":
			parts.lid.position.y = 0.22+clampf(sin(elapsed*2.8),0,1)*0.8
			parts.lid.rotation.z = sin(elapsed*2.8)*0.18
		"CLAP":
			for side in [-1,1]:
				parts["hand%d" % side].position.x = side*(0.22+absf(sin(elapsed*8))*0.5)
		"BOOM", "PARTY":
			for i in range(16):
				var angle := i*TAU/16
				parts["spark%d" % i].position = Vector3(cos(angle),sin(angle),sin(elapsed+i)*0.25)*(0.5+fmod(elapsed+i*0.07,1.0))
				parts["spark%d" % i].rotation.z = elapsed*(i%3+1)
		"LAUGH":
			model.scale.y = 1+sin(elapsed*15)*0.09
		"COOL":
			model.rotation.y = sin(elapsed*3)*0.35
		"CLOWN":
			model.rotation.z = sin(elapsed*8)*0.18
		"TROPHY":
			model.rotation.y = sin(elapsed*2)*0.5
