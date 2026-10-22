shader_type canvas_item;

// Clip the existing image into an antialiased rounded square.
void fragment() {
	float radius = 0.17;
	vec2 q = abs(UV - vec2(0.5)) - vec2(0.5 - radius);
	float distance_to_edge = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
	float edge = max(fwidth(distance_to_edge), 0.001);
	COLOR.a *= 1.0 - smoothstep(-edge, edge, distance_to_edge);
}
