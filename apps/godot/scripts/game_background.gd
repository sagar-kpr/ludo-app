extends Control

# Original code-native blue game fabric; no competitor artwork or foliage.
var finish: ShaderMaterial
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := ColorRect.new()
	fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.color = Color("f4f6fa")
	var shader := Shader.new()
	shader.code = """
	shader_type canvas_item;
	uniform float aspect = 0.5;
	void fragment() {
		vec2 p = (UV-vec2(0.5))*vec2(aspect,1.0);
		float glow = exp(-dot(p,p)*4.0);
		vec3 base = mix(vec3(0.035,0.085,0.17),vec3(0.10,0.29,0.48),glow);
		vec2 grid = mat2(vec2(0.819,-0.574),vec2(0.574,0.819))*p*11.0;
		vec2 cell = fract(grid)-0.5;
		vec2 q = abs(cell)-vec2(0.31);
		float tile = 1.0-smoothstep(0.0,0.02,length(max(q,vec2(0.0)))+min(max(q.x,q.y),0.0)-0.045);
		float pip = 1.0-smoothstep(0.048,0.065,length(cell));
		for (int i=0;i<4;i++) {
			vec2 dot_pos = vec2((i<2?-1.0:1.0)*0.17,(i==0||i==2?-1.0:1.0)*0.17);
			pip += 1.0-smoothstep(0.048,0.065,length(cell-dot_pos));
		}
		base += vec3(0.021,0.034,0.052)*tile-vec3(0.016,0.025,0.038)*min(pip,1.0);
		COLOR = vec4(base,1.0);
	}
	"""
	finish = ShaderMaterial.new()
	finish.shader = shader
	fill.material = finish
	add_child(fill)
	resized.connect(func(): finish.set_shader_parameter("aspect",size.x/maxf(size.y,1.0)))
	finish.set_shader_parameter("aspect",size.x/maxf(size.y,1.0))
