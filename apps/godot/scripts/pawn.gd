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
var cell_shadow: MeshInstance3D
var token_color := Color.WHITE

func lacquer(color: Color) -> ShaderMaterial:
	# Soft enamel shading keeps coloured faces bright while showing their curve.
	var shader := Shader.new()
	shader.code = """
	shader_type spatial;
	render_mode unshaded;
	uniform vec4 tint : source_color;
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
		float highlight = pow(max(dot(n,normalize(key+v)),0.0),34.0);
		float softbox = pow(max(dot(n,normalize(vec3(-0.8,0.6,0.5)+v)),0.0),9.0);
		float rim = pow(1.0-max(dot(n,v),0.0),3.0)*max(n.y,0.0);
		float shine = clamp(highlight*0.24+softbox*0.08+rim*0.07,0.0,0.35);
		float light = 0.80+0.20*max(dot(n,key),0.0);
		ALBEDO = mix(tint.rgb*light,vec3(1.0),shine);
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
	# A feathered patch marks the occupied cell without adding a physical foot.
	var shadow_mesh := QuadMesh.new()
	shadow_mesh.size = Vector2(0.82,0.82)
	var shadow_shader := Shader.new()
	shadow_shader.code = """
	shader_type spatial;
	render_mode unshaded,cull_disabled,depth_draw_never;
	uniform vec4 tint : source_color;
	void fragment() {
		float r = length((UV-vec2(0.5))*2.0);
		ALBEDO = tint.rgb;
		ALPHA = (1.0-smoothstep(0.15,1.0,r))*0.42;
	}
	"""
	var shadow_material := ShaderMaterial.new()
	shadow_material.shader = shadow_shader
	shadow_material.set_shader_parameter("tint",color.lightened(0.25))
	cell_shadow = part(shadow_mesh,Vector3(0,0.005,0),shadow_material)
	cell_shadow.name = "CellShadow"
	cell_shadow.rotation.x = -PI/2
	visual = Node3D.new()
	visual.name = "PinVisual"
	# Face the orthographic board camera; the pin tip remains on its real cell.
	visual.rotation.x = -atan2(30.0,5.0)
	add_child(visual)
	var outline: Array[Vector2] = [Vector2.ZERO]
	for step in range(33):
		var angle := -PI/6.0 + step*(4.0*PI/3.0)/32.0
		outline.append(Vector2(cos(angle)*0.43,0.98+sin(angle)*0.43))
	var shell := part(Geometry.beveled_pin(outline,0.38,0.055),Vector3.ZERO,lacquer(Color("87958e")))
	shell.name = "PinShell"
	shell.reparent(visual,false)
	var body := part(Geometry.beveled_pin(outline,0.32,0.06),Vector3(0,0.035,0.10),lacquer(Color("f5f7fa")))
	body.name = "PinBody"
	body.scale = Vector3(0.92,0.95,1.0)
	body.reparent(visual,false)
	var crown := SphereMesh.new()
	crown.radius = 0.265
	crown.height = 0.53
	crown.radial_segments = 32
	crown.rings = 16
	var dome := part(crown,Vector3(0,0.98,0.45),lacquer(color))
	dome.name = "PinDome"
	dome.scale.z = 0.48
	dome.reparent(visual,false)
	var badge := CylinderMesh.new()
	badge.top_radius = 0.32
	badge.bottom_radius = 0.32
	badge.height = 0.025
	badge.radial_segments = 40
	var center := part(badge,Vector3(0,0.98,0.40),lacquer(Color("f5f7f2")))
	center.name = "PinBadge"
	center.rotation.x = PI/2.0
	center.reparent(visual,false)
	var halo := QuadMesh.new()
	halo.size = Vector2(1.2,1.2)
	var ring_shader := Shader.new()
	ring_shader.code = """
	shader_type spatial;
	render_mode unshaded,cull_disabled,depth_draw_never;
	uniform vec4 tint : source_color;
	uniform bool animate = true;
	void fragment() {
		vec2 point = (UV-vec2(0.5))*2.0;
		float r = length(point);
		float band = smoothstep(0.68,0.74,r)*(1.0-smoothstep(0.82,0.88,r));
		float angle = atan(point.y,point.x)-(animate ? TIME*3.0 : 0.0);
		float sweep = pow(0.5+0.5*cos(angle),3.0);
		ALBEDO = tint.rgb;
		ALPHA = band*(0.18+0.70*sweep);
	}
	"""
	var glow := ShaderMaterial.new()
	glow.shader = ring_shader
	glow.set_shader_parameter("tint",color.lightened(0.30))
	ring = part(halo, Vector3(0, 0.01, 0), glow)
	ring.rotation.x = -PI/2
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
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.position = at
	add_child(instance)
	return instance

func _process(_delta: float) -> void:
	if cell_shadow:
		# The pawn hops above the table, while its shadow stays on the table.
		var floor_position := cell_shadow.global_position
		floor_position.y = 0.225
		cell_shadow.global_position = floor_position
	var selected := legal_move and selection_enabled and not moving
	if ring:
		ring.visible = (highlight or selected) and not moving
		ring.material_override.set_shader_parameter("animate",not reduced_motion)
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
	visual.position = Vector3.ZERO
	var tween := create_tween()
	tween.tween_method(func(progress: float):
		var travel := clampf((progress-0.10)/0.76,0.0,1.0)
		var eased := travel*travel*(3.0-2.0*travel)
		var spring := sin(travel*PI)
		position = from.lerp(destination,eased)+Vector3.UP*spring*0.084
		# The board camera is almost overhead: lift the pin along its upright
		# screen-facing axis too, so the hop is visibly several pixels tall.
		visual.position = visual.basis.y*spring*0.114
		var takeoff := sin(clampf(progress/0.10,0.0,1.0)*PI)*0.0225
		var landing := sin(clampf((progress-0.86)/0.14,0.0,1.0)*PI)*0.033
		visual.scale = Vector3(1.0-0.0165*spring+takeoff+landing,1.0+0.036*spring-takeoff-landing,1.0-0.0165*spring+takeoff+landing)
	, 0.0, 1.0, maxf(seconds,0.08))
	await tween.finished
	position = destination
	visual.position = Vector3.ZERO
	visual.scale = Vector3.ONE
	moving = false
