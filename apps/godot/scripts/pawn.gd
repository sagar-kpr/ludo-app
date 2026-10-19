extends Node3D

signal glide_passed(point_index: int)

const Design = preload("res://scripts/design.gd")
const Geometry = preload("res://scripts/geometry.gd")
const YARD_BOB := 0.16
const YARD_PULSE := 0.03
var token_id := ""
var ring: MeshInstance3D
var legal_move := false
var highlight := false
var reduced_motion := false
var resting := Vector3.ZERO
var visual: Node3D
var base_visual: Node3D
var moving := false
var sliding := false
var selection_enabled := true
var glow_floor: MeshInstance3D
var cell_shadow: MeshInstance3D
var token_color := Color.WHITE
var completed := false
var in_yard := false
var departing := false
var finish_badge: Control

func lacquer(color: Color) -> ShaderMaterial:
	# Satin enamel uses one soft light and finish for every player color.
	var shader := Shader.new()
	shader.code = """
	shader_type spatial;
	render_mode unshaded;
	uniform vec4 tint : source_color;
	uniform float exit_amount = 0.0;
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
		float highlight = pow(max(dot(n,normalize(key+v)),0.0),18.0);
		float softbox = pow(max(dot(n,normalize(vec3(-0.8,0.6,0.5)+v)),0.0),7.0);
		float rim = pow(1.0-max(dot(n,v),0.0),3.0)*max(n.y,0.0);
		float shine = clamp(highlight*0.12+softbox*0.06+rim*0.04,0.0,0.20);
		float light = 0.72+0.28*max(dot(n,key),0.0);
		ALBEDO = mix(mix(tint.rgb*light,vec3(1.0),shine),vec3(0.12,0.15,0.20),exit_amount);
		if (exit_amount > fract(sin(dot(FRAGCOORD.xy,vec2(12.9898,78.233)))*43758.5453)) discard;
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
	uniform float exit_amount = 0.0;
	void fragment() {
		ALBEDO = mix(tint.rgb * 0.78,vec3(0.12,0.15,0.20),exit_amount);
		if (exit_amount > fract(sin(dot(FRAGCOORD.xy,vec2(12.9898,78.233)))*43758.5453)) discard;
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
	var shadow_material := StandardMaterial3D.new()
	shadow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	shadow_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	shadow_material.render_priority = 2
	shadow_material.albedo_texture = Design.pawn_shadow_texture()
	shadow_material.albedo_color = Color(color, Design.TOKENS.pawn_shadow_opacity)
	cell_shadow = part(shadow_mesh,Vector3(0,0.005,0),shadow_material)
	cell_shadow.name = "CellShadow"
	cell_shadow.rotation.x = -PI/2
	# A permanent silver hoop replaces the solid foot; its center stays open.
	base_visual = Node3D.new()
	base_visual.name = "SilverBase"
	add_child(base_visual)
	var foot := TorusMesh.new()
	foot.inner_radius = 0.34
	foot.outer_radius = 0.46
	foot.rings = 48
	foot.ring_segments = 12
	var silver_shader := Shader.new()
	silver_shader.code = """
	shader_type spatial;
	render_mode diffuse_burley, specular_schlick_ggx;
	uniform float exit_amount = 0.0;
	void fragment() {
		if (exit_amount > fract(sin(dot(FRAGCOORD.xy,vec2(12.9898,78.233)))*43758.5453)) discard;
		ALBEDO = vec3(0.72,0.78,0.86);
		METALLIC = 0.82;
		ROUGHNESS = 0.22;
		SPECULAR = 0.75;
		EMISSION = vec3(0.12,0.14,0.18);
	}
	"""
	var silver := ShaderMaterial.new()
	silver.shader = silver_shader
	var foot_mesh := part(foot,Vector3(0,0.065,0),silver)
	foot_mesh.reparent(base_visual,false)
	visual = Node3D.new()
	visual.name = "PinVisual"
	# Face the orthographic board camera; the pin tip remains on its real cell.
	visual.rotation.x = -atan2(30.0,5.0)
	add_child(visual)
	var outline: Array[Vector2] = [Vector2.ZERO]
	for step in range(33):
		var angle := -PI/6.0 + step*(4.0*PI/3.0)/32.0
		outline.append(Vector2(cos(angle)*0.52,1.04+sin(angle)*0.52))
	var shell := part(Geometry.beveled_pin(outline,0.38,0.055),Vector3.ZERO,lacquer(Color("596169")))
	shell.name = "PinShell"
	shell.reparent(visual,false)
	var body := part(Geometry.beveled_pin(outline,0.32,0.06),Vector3(0,0.035,0.10),lacquer(Color("f5f7fa")))
	body.name = "PinBody"
	body.material_override.set_shader_parameter("face_curvature",0.85)
	body.scale = Vector3(0.92,0.95,1.0)
	body.reparent(visual,false)
	var crown := SphereMesh.new()
	crown.radius = 0.35
	crown.height = 0.70
	crown.radial_segments = 32
	crown.rings = 16
	var dome := part(crown,Vector3(0,1.04,0.45),lacquer(color))
	dome.name = "PinDome"
	dome.scale.z = 0.48
	dome.reparent(visual,false)
	var badge := CylinderMesh.new()
	badge.top_radius = 0.39
	badge.bottom_radius = 0.39
	badge.height = 0.025
	badge.radial_segments = 40
	var center := part(badge,Vector3(0,1.04,0.40),lacquer(Color("46515b")))
	center.name = "PinBadge"
	center.rotation.x = PI/2.0
	center.reparent(visual,false)
	# A real metal hoop rests around the tip. Colored studs make its rotation
	# readable even when the reflective torus itself is circularly symmetric.
	var hoop := TorusMesh.new()
	hoop.inner_radius = 0.36
	hoop.outer_radius = 0.47
	hoop.rings = 48
	hoop.ring_segments = 12
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color("e6d5ad")
	metal.metallic = 0.78
	metal.roughness = 0.24
	metal.emission_enabled = true
	metal.emission = Color("b7a27c")
	metal.emission_energy_multiplier = 0.22
	ring = part(hoop, Vector3(0, 0.065, 0), metal)
	ring.name = "SelectionRing"
	var inlay := StandardMaterial3D.new()
	inlay.albedo_color = color
	inlay.metallic = 0.45
	inlay.roughness = 0.22
	inlay.emission_enabled = true
	inlay.emission = color
	inlay.emission_energy_multiplier = 0.30
	var stud := SphereMesh.new()
	stud.radius = 0.065
	stud.height = 0.075
	stud.radial_segments = 12
	stud.rings = 6
	for index in range(3):
		var angle := TAU*index/3.0
		var accent := part(stud,Vector3(cos(angle)*0.415,0.035,sin(angle)*0.415),inlay)
		accent.reparent(ring,false)
	ring.visible = false
	var aura := QuadMesh.new()
	aura.size = Vector2(1.65,1.65)
	var aura_shader := Shader.new()
	aura_shader.code = """
	shader_type spatial;
	render_mode unshaded,cull_disabled,depth_draw_never;
	uniform vec4 tint : source_color;
	uniform float exit_amount = 0.0;
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
	shape.size = Vector3(1.16,1.72,0.55)
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

func set_completed(value: bool) -> void:
	completed = value
	if is_instance_valid(finish_badge):
		finish_badge.visible = value
	if value:
		legal_move = false
		highlight = false
		ring.hide()
		glow_floor.hide()
		visual.position = Vector3.ZERO
		visual.scale = Vector3.ONE

func _exit_tree() -> void:
	if is_instance_valid(finish_badge):
		finish_badge.queue_free()

func _process(delta: float) -> void:
	if departing:
		return
	place_shadow()
	var selected := legal_move and selection_enabled and not moving and not completed
	if ring:
		ring.visible = selected
		if ring.visible and not reduced_motion:
			ring.rotation.y = fposmod(ring.rotation.y + delta*2.4,TAU)
		glow_floor.visible = selected
	if visual and not moving:
		var loop := (1.0-cos(Time.get_ticks_msec()*TAU/1000.0))*0.5 if selected and not reduced_motion else 0.0
		# Home rows have less vertical clearance; keep their selection motion restrained.
		visual.position.y = loop*(YARD_BOB if in_yard else 0.43)
		visual.scale = Vector3.ONE*(1.0+(YARD_PULSE if in_yard else 0.12)*loop)

func place_shadow() -> void:
	if cell_shadow:
		# The stamp stays on the departed cell during a hop, then transfers to
		# the landing cell. Idle stamps never fade, even in reduced motion.
		var floor_position := resting if moving and not sliding else global_position
		floor_position.y = 0.226
		cell_shadow.global_position = floor_position

func hop_to(destination: Vector3, seconds: float, reduced_motion: bool) -> void:
	if reduced_motion:
		position = destination
		place_shadow()
		return
	var from := position
	resting = global_position
	moving = true
	ring.hide()
	glow_floor.hide()
	place_shadow()
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
	place_shadow()

func glide_path(points: Array[Vector3], durations: Array[float], instant: bool) -> void:
	if points.is_empty():
		return
	visual.position = Vector3.ZERO
	visual.scale = Vector3.ONE
	ring.hide()
	glow_floor.hide()
	if instant:
		position = points.back()
		place_shadow()
		glide_passed.emit(points.size()-1)
		return
	moving = true
	sliding = true
	var tween := create_tween()
	for index in range(points.size()):
		# One uninterrupted linear path: no spring, squash or pause per cell.
		var departure := position if index == 0 else points[index-1]
		tween.tween_method(func(at: Vector3):
			position = at
			place_shadow()
		,departure,points[index],durations[index]).set_trans(Tween.TRANS_LINEAR)
		tween.tween_callback(func(): glide_passed.emit(index))
	await tween.finished
	sliding = false
	moving = false
	place_shadow()

func vanish() -> void:
	departing = true
	legal_move = false
	highlight = false
	ring.hide()
	glow_floor.hide()
	if is_instance_valid(finish_badge):
		finish_badge.hide()
	var tween := create_tween()
	tween.tween_method(func(amount: float):
		for mesh in visual.get_children()+base_visual.get_children():
			if mesh is MeshInstance3D:
				if mesh.material_override is ShaderMaterial:
					mesh.material_override.set_shader_parameter("exit_amount",amount)
				elif mesh.material_override is StandardMaterial3D:
					mesh.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					mesh.material_override.albedo_color.a = 1.0-amount
		visual.position.y = amount*0.3
		cell_shadow.material_override.albedo_color.a = (1.0-amount)*Design.TOKENS.pawn_shadow_opacity
	,0.0,1.0,0.85)
