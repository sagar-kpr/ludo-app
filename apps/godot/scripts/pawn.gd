extends Node3D

const Design = preload("res://scripts/design.gd")
const Geometry = preload("res://scripts/geometry.gd")
var token_id := ""
var ring: MeshInstance3D
var legal_move := false
var highlight := false
var reduced_motion := false
var resting := Vector3.ZERO
var visual: Node3D
var moving := false
var selection_enabled := true
var glow_floor: MeshInstance3D
var token_color := Color.WHITE

func lacquer(color: Color) -> ShaderMaterial:
	# Portable studio lighting; glossy reflections also work in web Compatibility.
	var shader := Shader.new()
	shader.code = """
	shader_type spatial;
	render_mode unshaded;
	uniform vec4 tint : source_color;
	uniform float base_lift = 0.18;
	uniform float face_curvature = 0.0;
	varying vec3 world_normal;
	varying vec3 world_position;
	varying vec3 world_tangent;
	varying vec3 local_point;
	void vertex() {
		world_normal = normalize(mat3(MODEL_MATRIX)*NORMAL);
		world_position = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
		world_tangent = normalize(mat3(MODEL_MATRIX)*vec3(1.0,0.0,0.0));
		local_point = VERTEX;
	}
	void fragment() {
		vec3 n = normalize(world_normal+world_tangent*local_point.x*face_curvature);
		vec3 v = normalize(CAMERA_POSITION_WORLD-world_position);
		vec3 key = normalize(vec3(-0.65,1.0,0.65));
		float diffuse = max(dot(n,key),0.0);
		float highlight = pow(max(dot(n,normalize(key+v)),0.0),34.0);
		float softbox = pow(max(dot(n,normalize(vec3(-0.8,0.6,0.5)+v)),0.0),9.0);
		float rim = pow(1.0-max(dot(n,v),0.0),3.0)*max(n.y,0.0);
		ALBEDO = tint.rgb*(base_lift+(1.0-base_lift)*diffuse)+mix(tint.rgb,vec3(1.0),0.55)*(highlight*0.52+softbox*0.08+rim*0.07);
	}
	"""
	var finish := ShaderMaterial.new()
	finish.shader = shader
	finish.set_shader_parameter("tint",color)
	return finish

func sculpted_finish(color: Color) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
	shader_type spatial;
	render_mode diffuse_burley, specular_schlick_ggx;
	uniform vec4 tint : source_color;
	void fragment() {
		ALBEDO = tint.rgb * 0.78;
		ROUGHNESS = 0.23;
		METALLIC = 0.08;
		SPECULAR = 0.65;
	}
	"""
	var finish := ShaderMaterial.new()
	finish.shader = shader
	finish.set_shader_parameter("tint",color)
	return finish

func configure(id: String, color: Color) -> void:
	token_id = id
	token_color = color
	var finish := sculpted_finish(color)
	var shadow := QuadMesh.new()
	shadow.size = Vector2(1.0,0.78)
	var shader := Shader.new()
	shader.code = """
	shader_type spatial;
	render_mode unshaded, cull_disabled, depth_draw_never;
	void fragment() {
		float radius = length((UV-vec2(0.5))*2.0);
		ALBEDO = vec3(0.01,0.025,0.04);
		ALPHA = (1.0-smoothstep(0.0,1.0,radius))*0.27;
	}
	"""
	var shadow_mat := ShaderMaterial.new()
	shadow_mat.shader = shader
	var contact := part(shadow, Vector3(0.14,0.006,0.12),shadow_mat)
	contact.name = "ContactShadow"
	contact.rotation_degrees.x = -90
	visual = Node3D.new()
	visual.name = "PinVisual"
	# Face the orthographic board camera; the pin tip remains on its real cell.
	visual.rotation.x = -atan2(30.0,5.0)
	add_child(visual)
	var outline: Array[Vector2] = [Vector2.ZERO]
	for step in range(33):
		var angle := -PI/6.0 + step*(4.0*PI/3.0)/32.0
		outline.append(Vector2(cos(angle)*0.46,1.05+sin(angle)*0.46))
	var shell := part(Geometry.beveled_pin(outline,0.38,0.07),Vector3.ZERO,lacquer(Color("52616c")))
	shell.name = "PinShell"
	shell.reparent(visual,false)
	var body := part(Geometry.beveled_pin(outline,0.32,0.06),Vector3(0,0.035,0.10),lacquer(Color("f5f7fa")))
	body.name = "PinBody"
	body.scale = Vector3(0.92,0.95,1.0)
	body.reparent(visual,false)
	var crown := SphereMesh.new()
	crown.radius = 0.29
	crown.height = 0.58
	crown.radial_segments = 32
	crown.rings = 16
	var dome := part(crown,Vector3(0,1.05,0.45),lacquer(color))
	dome.name = "PinDome"
	dome.scale.z = 0.48
	dome.reparent(visual,false)
	var badge := CylinderMesh.new()
	badge.top_radius = 0.34
	badge.bottom_radius = 0.34
	badge.height = 0.025
	badge.radial_segments = 40
	var center := part(badge,Vector3(0,1.05,0.40),lacquer(Color("293840")))
	center.name = "PinBadge"
	center.rotation.x = PI/2.0
	center.reparent(visual,false)
	# A ringed physical base anchors the pin, as in the reference.
	var base := CylinderMesh.new()
	base.top_radius = 0.47
	base.bottom_radius = 0.49
	base.height = 0.055
	base.radial_segments = 40
	part(base,Vector3(0,0.013,0),lacquer(Color("18242e"))).name = "PinBaseOutline"
	var base_face := CylinderMesh.new()
	base_face.top_radius = 0.40
	base_face.bottom_radius = 0.43
	base_face.height = 0.04
	base_face.radial_segments = 40
	part(base_face,Vector3(0,0.05,0),finish).name = "PinBase"
	var halo := TorusMesh.new()
	halo.inner_radius = 0.42
	halo.outer_radius = 0.54
	var glow := StandardMaterial3D.new()
	glow.albedo_color = color
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring = part(halo, Vector3(0, 0.01, 0), glow)
	ring.visible = false
	var aura := QuadMesh.new()
	aura.size = Vector2(1.65,1.65)
	var aura_shader := Shader.new()
	aura_shader.code = """
	shader_type spatial;
	render_mode unshaded,cull_disabled,depth_draw_never;
	uniform vec4 tint : source_color;
	void fragment() {
		float r = length((UV-vec2(0.5))*2.0);
		ALBEDO = tint.rgb;
		ALPHA = exp(-pow((r-0.60)*5.0,2.0))*0.28*(1.0-smoothstep(0.75,1.0,r));
	}
	"""
	var aura_mat := ShaderMaterial.new()
	aura_mat.shader = aura_shader
	aura_mat.set_shader_parameter("tint",color)
	glow_floor = part(aura,Vector3(0,0.008,0),aura_mat)
	glow_floor.rotation.x = -PI/2
	glow_floor.visible = false
	var area := Area3D.new()
	area.set_meta("token_id", token_id)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.98,1.60,0.55)
	collision.shape = shape
	collision.position.y = 0.75
	area.add_child(collision)
	visual.add_child(area)

func part(mesh: Mesh, at: Vector3, mat: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = mat
	instance.position = at
	add_child(instance)
	return instance

func _process(_delta: float) -> void:
	var selected := legal_move and selection_enabled and not moving
	if ring:
		ring.visible = selected
		glow_floor.visible = selected
	if visual and not moving:
		var loop := (1.0-cos(Time.get_ticks_msec()*TAU/1000.0))*0.5 if selected and not reduced_motion else 0.0
		# The tilted board camera projects this to roughly four logical pixels.
		visual.position.y = loop*0.43
		visual.scale = Vector3.ONE*(1.0+0.12*loop)

func hop_to(destination: Vector3, seconds: float, reduced_motion: bool) -> void:
	if reduced_motion:
		position = destination
		return
	var from := position
	moving = true
	visual.position.y = 0
	var tween := create_tween()
	tween.tween_method(func(progress: float):
		var eased := progress*progress*(3.0-2.0*progress)
		position = from.lerp(destination,eased) + Vector3.UP*sin(progress*PI)*0.24
		var spring := sin(progress*PI)
		visual.scale = Vector3(1.0-0.035*spring,1.0+0.06*spring,1.0)
	, 0.0, 1.0, maxf(seconds,0.22))
	await tween.finished
	position = destination
	visual.scale = Vector3.ONE
	moving = false
