shader_type canvas_item;
// Red edge glow shown when the jar is about to overflow.
void fragment() {
	vec2 d = UV - 0.5;
	float v = smoothstep(0.32, 0.75, length(d * vec2(1.0, 0.8)));
	COLOR = vec4(0.95, 0.15, 0.3, v * 0.55);
}
