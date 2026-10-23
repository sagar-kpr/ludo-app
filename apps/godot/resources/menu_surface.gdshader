shader_type canvas_item;

uniform vec2 surface_size = vec2(190.0, 268.0);
uniform vec4 accent : source_color = vec4(0.18, 0.57, 1.0, 1.0);
uniform vec4 top_color : source_color = vec4(0.055, 0.15, 0.26, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.025, 0.07, 0.14, 1.0);
uniform float radius = 22.0;
uniform float border_width = 1.2;

void fragment() {
	vec2 q = abs((UV - vec2(0.5)) * surface_size) - (surface_size * 0.5 - vec2(radius));
	float d = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
	float coverage = 1.0 - smoothstep(-0.65, 0.65, d);
	float border = 1.0 - smoothstep(border_width - 0.5, border_width + 0.5, -d);
	float light = exp(-length((UV - vec2(0.48, 0.05)) * vec2(1.5, 1.0)) * 4.0);
	vec3 fill = mix(top_color.rgb, bottom_color.rgb, UV.y) + accent.rgb * light * 0.045;
	COLOR = vec4(mix(fill, accent.rgb, border * 0.88), coverage) * COLOR;
}
